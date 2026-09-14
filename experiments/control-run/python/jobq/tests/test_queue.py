import random
import tempfile
import unittest
from collections.abc import Callable
from functools import partial
from pathlib import Path
from typing import Any

from jobq.clock import ManualClock
from jobq.contract import ContractError
from jobq.fs import MemoryFile, OsFs
from jobq.model import MAX_PAYLOAD_BYTES, Job, JobState
from jobq.queue import LEASE_RAN_OUT, LIST_LIMIT, Queue, Refusal, _Txn, check_change
from jobq.store import DeleteRecord, PutRecord, Record, Store, StoreCorrupt, encode
from tests.support import LOG, START_MS, Rig


def leased(result: Job | None) -> Job:
    if result is None:
        raise AssertionError("expected a lease")
    return result


def done(result: Job | Refusal) -> Job:
    if isinstance(result, Refusal):
        raise AssertionError(f"expected a job, got {result}")
    return result


class LifecycleTest(unittest.TestCase):
    def setUp(self) -> None:
        self.rig = Rig()
        self.queue = self.rig.queue

    def test_create_is_queued_with_no_attempts_and_a_fresh_id(self) -> None:
        first = self.queue.create("emails", "a", 3)
        second = self.queue.create("emails", "b", 3)
        self.assertEqual((first.id, second.id), ("j_1", "j_2"))
        self.assertEqual((first.state, first.attempts, first.created_at), ("queued", 0, START_MS))

    def test_lease_hands_out_the_oldest_queued_job_of_that_queue(self) -> None:
        self.queue.create("other", "x", 3)
        oldest = self.queue.create("emails", "a", 3)
        self.queue.create("emails", "b", 3)
        job = leased(self.queue.lease("emails", "w1", 1_000))
        self.assertEqual(job.id, oldest.id)
        self.assertEqual((job.state, job.worker, job.attempts), ("leased", "w1", 1))
        self.assertEqual(job.lease_until, START_MS + 1_000)

    def test_lease_on_an_empty_queue_is_none(self) -> None:
        self.assertIsNone(self.queue.lease("emails", "w1", 1_000))

    def test_ack_by_the_holder_is_done(self) -> None:
        job = self.queue.create("emails", "a", 3)
        self.queue.lease("emails", "w1", 1_000)
        acked = done(self.queue.ack(job.id, "w1"))
        self.assertEqual((acked.state, acked.worker, acked.lease_until), ("done", None, None))

    def test_ack_by_another_worker_or_of_an_unleased_job_is_a_conflict(self) -> None:
        job = self.queue.create("emails", "a", 3)
        self.assertIs(self.queue.ack(job.id, "w1"), Refusal.CONFLICT)
        self.queue.lease("emails", "w1", 1_000)
        self.assertIs(self.queue.ack(job.id, "w2"), Refusal.CONFLICT)
        self.assertIs(self.queue.ack("j_99", "w1"), Refusal.NOT_FOUND)

    def test_fail_with_attempts_left_is_queued_with_its_reason(self) -> None:
        job = self.queue.create("emails", "a", 2)
        self.queue.lease("emails", "w1", 1_000)
        failed = done(self.queue.fail(job.id, "w1", "smtp down"))
        self.assertEqual((failed.state, failed.attempts, failed.reason), ("queued", 1, "smtp down"))

    def test_fail_on_the_last_attempt_is_dead(self) -> None:
        job = self.queue.create("emails", "a", 1)
        self.queue.lease("emails", "w1", 1_000)
        self.assertEqual(done(self.queue.fail(job.id, "w1", "boom")).state, "dead")
        self.assertIsNone(self.queue.lease("emails", "w1", 1_000))

    def test_delete_is_refused_only_while_leased(self) -> None:
        queued = self.queue.create("emails", "a", 3)
        held = self.queue.create("emails", "b", 3)
        self.assertIsNone(self.queue.delete(queued.id))
        self.queue.lease("emails", "w1", 1_000)
        self.assertIs(self.queue.delete(held.id), Refusal.CONFLICT)
        self.queue.ack(held.id, "w1")
        self.assertIsNone(self.queue.delete(held.id))
        self.assertIs(self.queue.delete(held.id), Refusal.NOT_FOUND)
        self.assertIsNone(self.queue.get(held.id))

    def test_list_filters_in_id_order_and_stops_at_100(self) -> None:
        for number in range(LIST_LIMIT + 20):
            self.queue.create("a" if number % 2 else "b", "x", 3)
        self.queue.lease("a", "w1", 1_000)
        everything = self.queue.list()
        self.assertEqual(len(everything), LIST_LIMIT)
        self.assertEqual([job.id for job in everything[:3]], ["j_1", "j_2", "j_3"])
        self.assertEqual([job.id for job in self.queue.list("a", JobState.LEASED)], ["j_2"])
        self.assertTrue(all(job.queue == "b" for job in self.queue.list("b")))

    def test_health_counts_every_state(self) -> None:
        for _ in range(4):
            self.queue.create("emails", "a", 1)
        self.queue.lease("emails", "w1", 1_000)
        second = leased(self.queue.lease("emails", "w1", 1_000))
        third = leased(self.queue.lease("emails", "w1", 1_000))
        self.queue.ack(second.id, "w1")
        self.queue.fail(third.id, "w1", "x")
        self.rig.clock.advance(250)
        health = self.queue.health()
        self.assertEqual((health.queued, health.leased, health.done, health.dead), (1, 1, 1, 1))
        self.assertEqual(health.uptime_ms, 250)

    def test_ids_never_repeat_after_a_delete_restart_and_compaction(self) -> None:
        self.queue.create("emails", "a", 3)
        last = self.queue.create("emails", "b", 3)
        self.queue.delete(last.id)
        self.assertEqual(self.rig.restart().create("emails", "c", 3).id, "j_3")
        self.rig.queue.delete("j_3")
        self.rig.queue.compact()
        self.assertEqual(self.rig.restart().create("emails", "d", 3).id, "j_4")


class LeaseRunsOutTest(unittest.TestCase):
    def setUp(self) -> None:
        self.rig = Rig()
        self.queue = self.rig.queue

    def test_a_lease_that_runs_out_is_leased_again_with_attempts_2(self) -> None:
        job = self.queue.create("emails", "a", 3)
        self.queue.lease("emails", "w1", 100)
        self.rig.clock.advance(100)
        again = leased(self.queue.lease("emails", "w2", 100))
        self.assertEqual((again.id, again.attempts, again.worker), (job.id, 2, "w2"))
        self.assertEqual(again.reason, LEASE_RAN_OUT)

    def test_a_lease_that_runs_out_on_its_last_attempt_is_dead(self) -> None:
        job = self.queue.create("emails", "a", 1)
        self.queue.lease("emails", "w1", 100)
        self.rig.clock.advance(100)
        self.assertEqual(leased(self.queue.get(job.id)).state, "dead")
        self.assertIsNone(self.queue.lease("emails", "w1", 100))

    def test_an_ack_after_the_lease_ran_out_is_a_conflict(self) -> None:
        job = self.queue.create("emails", "a", 3)
        self.queue.lease("emails", "w1", 100)
        self.rig.clock.advance(100)
        self.assertIs(self.queue.ack(job.id, "w1"), Refusal.CONFLICT)
        self.assertIs(self.queue.fail(job.id, "w1", "late"), Refusal.CONFLICT)

    def test_a_lease_that_ran_out_blocks_the_job_for_no_more_than_one_look(self) -> None:
        job = self.queue.create("emails", "a", 3)
        self.queue.lease("emails", "w1", 100)
        self.rig.clock.advance(100)
        self.assertIs(self.queue.ack(job.id, "w1"), Refusal.CONFLICT)
        self.assertEqual(leased(self.queue.lease("emails", "w2", 100)).id, job.id)

    def test_every_kind_of_look_expires_the_lease(self) -> None:
        looks: list[Callable[[Queue], object]] = [
            lambda q: q.get("j_1"),
            lambda q: q.list(),
            lambda q: q.health(),
            lambda q: q.expire(),
            lambda q: q.delete("j_99"),
            lambda q: q.lease("other", "w9", 100),
            lambda q: q.ack("j_99", "w9"),
            lambda q: q.fail("j_99", "w9", "x"),
        ]
        for look in looks:
            rig = Rig()
            rig.queue.create("emails", "a", 3)
            rig.queue.lease("emails", "w1", 100)
            rig.clock.advance(100)
            look(rig.queue)
            with self.subTest(look=look):
                self.assertEqual(rig.queue.snapshot()["j_1"].state, "queued")
                self.assertEqual(rig.restart().snapshot()["j_1"].state, "queued")

    def test_lease_expiry_is_durable_before_the_look_returns(self) -> None:
        self.queue.create("emails", "a", 3)
        self.queue.lease("emails", "w1", 100)
        self.rig.clock.advance(100)
        self.queue.get("j_1")
        self.assertIn(b'"reason":"lease ran out"', self.rig.durable_log())


class ReplayTest(unittest.TestCase):
    def test_create_lease_stop_start_finds_the_lease_run_out(self) -> None:
        clock = ManualClock(START_MS)
        with tempfile.TemporaryDirectory() as tmp:
            store = Store(OsFs(), Path(tmp))
            queue = Queue.open(store, clock)
            job = queue.create("emails", "a", 3)
            queue.lease("emails", "w1", 5_000)
            store.close()
            clock.advance(5_000)
            store = Store(OsFs(), Path(tmp))
            queue = Queue.open(store, clock)
            self.assertEqual(queue.snapshot()[job.id].state, "leased")
            self.assertEqual(leased(queue.get(job.id)).state, "queued")
            self.assertEqual(leased(queue.lease("emails", "w2", 100)).attempts, 2)
            store.close()

    def test_a_job_is_never_lost(self) -> None:
        rig = Rig()
        rng = random.Random(7)
        for step in range(300):
            choice = rng.randrange(6)
            ids = list(rig.queue.snapshot())
            if choice == 0 or not ids:
                rig.queue.create(rng.choice(["a", "b"]), f"p{step}", rng.randint(1, 3))
            elif choice == 1:
                rig.queue.lease(rng.choice(["a", "b"]), rng.choice(["w1", "w2"]), 100)
            elif choice == 2:
                rig.queue.ack(rng.choice(ids), rng.choice(["w1", "w2"]))
            elif choice == 3:
                rig.queue.fail(rng.choice(ids), rng.choice(["w1", "w2"]), "x")
            elif choice == 4:
                rig.queue.delete(rng.choice(ids))
            else:
                rig.clock.advance(rng.randint(0, 150))
            before = rig.queue.snapshot()
            with self.subTest(step=step):
                self.assertEqual(rig.restart().snapshot(), before)


class RequiresTest(unittest.TestCase):
    def setUp(self) -> None:
        self.queue = Rig().queue

    def assert_rejects(self, call: Callable[[], object]) -> None:
        with self.assertRaisesRegex(ContractError, "^requires "):
            call()

    def test_create_rejects_a_bad_queue_name(self) -> None:
        for name in ("", "q" * 65, "a b", "é"):
            self.assert_rejects(partial(self.queue.create, name, "x", 3))

    def test_create_rejects_a_bad_payload(self) -> None:
        self.assert_rejects(lambda: self.queue.create("q", "x" * (MAX_PAYLOAD_BYTES + 1), 3))
        self.assert_rejects(lambda: self.queue.create("q", "a\x00", 3))
        self.queue.create("q", "x" * MAX_PAYLOAD_BYTES, 3)

    def test_create_rejects_max_attempts_out_of_range(self) -> None:
        self.assert_rejects(lambda: self.queue.create("q", "x", 0))
        self.assert_rejects(lambda: self.queue.create("q", "x", 101))

    def test_lease_rejects_lease_ms_out_of_range(self) -> None:
        self.assert_rejects(lambda: self.queue.lease("q", "w1", 99))
        self.assert_rejects(lambda: self.queue.lease("q", "w1", 3_600_001))

    def test_lease_rejects_a_bad_queue_name_or_worker(self) -> None:
        self.assert_rejects(lambda: self.queue.lease("", "w1", 1_000))
        self.assert_rejects(lambda: self.queue.lease("q", "", 1_000))

    def test_fail_rejects_a_bad_reason(self) -> None:
        self.assert_rejects(lambda: self.queue.fail("j_1", "w1", "a\rb"))


class TamperedQueue(Queue):
    """Corrupts what a lease or an ack transaction returns, to show the ensures catch it."""

    def __init__(self, rig: Rig, lease: dict[str, Any], ack: dict[str, Any]) -> None:
        super().__init__(rig.store, rig.clock)
        self.lease_tamper = lease
        self.ack_tamper = ack

    def _transact[T](self, body: Callable[[_Txn], T]) -> T:
        result = super()._transact(body)
        if isinstance(result, tuple):
            before, after = result
            return (before, after.model_copy(update=self.lease_tamper))  # type: ignore[return-value]
        if isinstance(result, Job) and result.state is JobState.DONE:
            return result.model_copy(update=self.ack_tamper)
        return result


class EnsuresTest(unittest.TestCase):
    def test_lease_ensures_the_caller_holds_the_job_with_attempts_one_higher(self) -> None:
        for tamper in ({"worker": "w2"}, {"attempts": 2}, {"state": JobState.QUEUED}):
            queue = TamperedQueue(Rig(), lease=tamper, ack={})
            queue.create("q", "x", 3)
            with self.subTest(tamper=tamper), self.assertRaisesRegex(ContractError, "^ensures "):
                queue.lease("q", "w1", 1_000)

    def test_ack_ensures_the_job_is_done(self) -> None:
        queue = TamperedQueue(Rig(), lease={}, ack={"state": JobState.QUEUED})
        job = queue.create("q", "x", 3)
        queue.lease("q", "w1", 1_000)
        with self.assertRaisesRegex(ContractError, "^ensures the job is done"):
            queue.ack(job.id, "w1")

    def test_a_record_applied_before_it_is_durable_is_caught(self) -> None:
        rig = Rig()

        class Unsynced(Store):
            def append(self, records: Any) -> None:
                self.written += len(records)

        queue = Queue.open(Unsynced(rig.fs, Path("/other")), rig.clock)
        with self.assertRaisesRegex(ContractError, "durable"):
            queue.create("q", "x", 3)
        self.assertEqual(queue.snapshot(), {})


def base_job(**changes: Any) -> Job:
    fields: dict[str, Any] = {
        "id": "j_1",
        "queue": "q",
        "state": JobState.QUEUED,
        "payload": "x",
        "attempts": 0,
        "max_attempts": 3,
        "created_at": START_MS,
        "updated_at": START_MS,
    }
    fields.update(changes)
    fields["state"] = JobState(fields["state"])
    return Job.model_validate(fields)


LEASED = {"state": JobState.LEASED, "attempts": 1, "worker": "w1", "lease_until": START_MS + 1}


class NeverTest(unittest.TestCase):
    """Each never is asserted on every change; each test here tries to make the change."""

    def test_a_job_is_never_held_by_two_workers_at_once(self) -> None:
        rig = Rig()
        rig.queue.create("q", "x", 3)
        rig.queue.lease("q", "w1", 1_000)
        self.assertIsNone(rig.queue.lease("q", "w2", 1_000))
        with self.assertRaisesRegex(ContractError, "two workers"):
            check_change(base_job(**LEASED), base_job(**{**LEASED, "worker": "w2", "attempts": 2}))

    def test_a_done_job_is_never_leased_again(self) -> None:
        rig = Rig()
        job = rig.queue.create("q", "x", 3)
        rig.queue.lease("q", "w1", 1_000)
        rig.queue.ack(job.id, "w1")
        self.assertIsNone(rig.queue.lease("q", "w1", 1_000))
        done_job = base_job(state=JobState.DONE, attempts=1)
        with self.assertRaisesRegex(ContractError, "leased again"):
            check_change(done_job, base_job(**{**LEASED, "attempts": 2}))

    def test_a_dead_job_is_never_leased(self) -> None:
        dead = base_job(state=JobState.DEAD, attempts=3)
        with self.assertRaisesRegex(ContractError, "dead j_1 is leased"):
            check_change(dead, base_job(**{**LEASED, "attempts": 3}))

    def test_attempts_never_exceed_max_attempts(self) -> None:
        rig = Rig()
        job = rig.queue.create("q", "x", 3)
        for _ in range(10):
            rig.queue.lease("q", "w1", 100)
            rig.clock.advance(100)
            self.assertLessEqual(rig.queue.snapshot()[job.id].attempts, 3)
        self.assertEqual(leased(rig.queue.get(job.id)).state, "dead")
        with self.assertRaisesRegex(ContractError, "more attempts"):
            check_change(
                base_job(**{**LEASED, "attempts": 3}), base_job(state="queued", attempts=4)
            )

    def test_other_forbidden_changes(self) -> None:
        cases = [
            (base_job(**LEASED), None, "deleted while leased"),
            (base_job(), base_job(state=JobState.DONE), "goes queued to done"),
            (base_job(), base_job(payload="y"), "changes what it was created with"),
            (base_job(**LEASED), base_job(attempts=0), "changes attempts"),
        ]
        for old, new, message in cases:
            with self.subTest(message=message), self.assertRaisesRegex(ContractError, message):
                check_change(old, new)

    def test_a_response_is_never_sent_before_its_record_is_durable(self) -> None:
        rig = Rig()
        job_id = rig.create()
        self.assertIn(job_id.encode(), rig.durable_log())
        response = rig.call("POST", "/queues/emails/lease", body={"lease_ms": 1000})
        self.assertEqual(response.status, 200)
        self.assertIn(b'"state":"leased"', rig.durable_log())
        rig.faults.rate = 1.0
        response = rig.call("POST", f"/jobs/{job_id}/ack")
        self.assertEqual(response.status, 503)
        rig.faults.rate = 0.0
        self.assertNotIn(b'"state":"done"', rig.durable_log())
        self.assertEqual(rig.queue.snapshot()[job_id].state, "leased")
        self.assertEqual(rig.restart().snapshot()[job_id].state, "leased")


class InvariantTest(unittest.TestCase):
    """Every invariant kept here can be broken by a record the queue replays."""

    def assert_replay_trips(self, records: list[Record], message: str) -> None:
        rig = Rig()
        data = b"".join(map(encode, records))
        rig.fs.files[LOG] = MemoryFile(bytearray(data), data)
        with self.assertRaisesRegex(StoreCorrupt, message):
            rig.restart(crash=False)

    def put(self, **changes: Any) -> PutRecord:
        return PutRecord(job=base_job(**changes))

    def test_attempts_at_most_max_attempts(self) -> None:
        self.assert_replay_trips([self.put(state="dead", attempts=5)], "more attempts")

    def test_worker_and_lease_until_exactly_while_leased(self) -> None:
        self.assert_replay_trips([self.put(worker="w1")], "exactly while leased")
        self.assert_replay_trips(
            [self.put(state="leased", attempts=1, worker="w1")], "exactly while leased"
        )

    def test_a_queued_job_has_an_attempt_left(self) -> None:
        self.assert_replay_trips([self.put(attempts=3)], "has an attempt left")

    def test_a_dead_job_used_every_attempt(self) -> None:
        self.assert_replay_trips([self.put(state="dead", attempts=1)], "used every attempt")

    def test_a_leased_or_done_job_was_leased(self) -> None:
        self.assert_replay_trips([self.put(state="done")], "leased at least once")

    def test_updated_no_earlier_than_created(self) -> None:
        self.assert_replay_trips([self.put(updated_at=START_MS - 1)], "not updated before")

    def test_a_deleted_job_exists(self) -> None:
        self.assert_replay_trips([DeleteRecord(id="j_4")], "deleted j_4 exists")

    def test_replayed_changes_obey_the_nevers(self) -> None:
        self.assert_replay_trips(
            [self.put(state="done", attempts=1), self.put(**LEASED | {"attempts": 2})],
            "leased again",
        )


if __name__ == "__main__":
    unittest.main()
