import unittest

from jobq.contract import ContractError
from jobq.jobs import Job
from jobq.queue import Conflict, NotFound, check_transition
from jobq.store import StoreError, replay
from support import QueueCase


def leased(queue_case: QueueCase, job_id: str) -> Job:
    job = queue_case.queue.get(job_id)
    assert job is not None
    return job


class LifecycleTest(QueueCase):
    def test_create_queues_a_job_with_a_new_id(self) -> None:
        first = self.queue.create("emails", "a", 3)
        second = self.queue.create("emails", "b", 3)
        self.assertEqual((first.id, second.id), ("j_1", "j_2"))
        self.assertEqual((first.state, first.attempts), ("queued", 0))

    def test_lease_hands_out_the_oldest_queued_job_of_that_queue(self) -> None:
        self.queue.create("other", "x", 3)
        self.queue.create("emails", "a", 3)
        self.queue.create("emails", "b", 3)
        job = self.queue.lease("emails", "w1", 1000)
        assert job is not None
        self.assertEqual((job.id, job.payload), ("j_2", "a"))

    def test_lease_ensures_the_job_is_leased_to_the_caller_one_attempt_higher(self) -> None:
        self.queue.create("emails", "a", 3)
        job = self.queue.lease("emails", "w1", 1000)
        assert job is not None
        self.assertEqual((job.state, job.worker, job.attempts), ("leased", "w1", 1))
        self.assertEqual(job.lease_until_ms, self.clock.ms + 1000)

    def test_lease_with_nothing_queued_is_none(self) -> None:
        self.assertIsNone(self.queue.lease("emails", "w1", 1000))
        self.queue.create("emails", "a", 3)
        self.queue.lease("emails", "w1", 1000)
        self.assertIsNone(self.queue.lease("emails", "w2", 1000))

    def test_ack_ensures_the_job_is_done(self) -> None:
        self.queue.create("emails", "a", 3)
        self.queue.lease("emails", "w1", 1000)
        done = self.queue.ack("j_1", "w1")
        assert isinstance(done, Job)
        self.assertEqual((done.state, done.worker, done.lease_until_ms), ("done", None, None))

    def test_ack_by_a_worker_without_the_lease_is_a_conflict(self) -> None:
        self.queue.create("emails", "a", 3)
        self.assertIsInstance(self.queue.ack("j_1", "w1"), Conflict)
        self.queue.lease("emails", "w1", 1000)
        self.assertIsInstance(self.queue.ack("j_1", "w2"), Conflict)
        self.assertIsInstance(self.queue.ack("j_9", "w1"), NotFound)
        self.assertIsInstance(self.queue.ack("nonsense", "w1"), NotFound)

    def test_fail_requeues_with_the_reason_until_the_last_attempt(self) -> None:
        self.queue.create("emails", "a", 2)
        self.queue.lease("emails", "w1", 1000)
        first = self.queue.fail("j_1", "w1", "smtp down")
        assert isinstance(first, Job)
        self.assertEqual((first.state, first.attempts, first.reason), ("queued", 1, "smtp down"))
        self.queue.lease("emails", "w2", 1000)
        second = self.queue.fail("j_1", "w2", "still down")
        assert isinstance(second, Job)
        self.assertEqual((second.state, second.attempts), ("dead", 2))
        self.assertIsNone(self.queue.lease("emails", "w1", 1000))

    def test_fail_without_the_lease_is_a_conflict(self) -> None:
        self.queue.create("emails", "a", 2)
        self.assertIsInstance(self.queue.fail("j_1", "w1", "x"), Conflict)
        self.assertIsInstance(self.queue.fail("j_2", "w1", "x"), NotFound)

    def test_delete(self) -> None:
        self.queue.create("emails", "a", 1)
        self.queue.create("emails", "b", 1)
        self.queue.create("emails", "c", 1)
        self.queue.lease("emails", "w1", 1000)
        self.assertIsInstance(self.queue.delete("j_1"), Conflict)
        self.assertIsInstance(self.queue.delete("j_2"), Job)
        self.assertIsNone(self.queue.get("j_2"))
        self.assertIsInstance(self.queue.delete("j_2"), NotFound)
        self.queue.ack("j_1", "w1")
        self.assertIsInstance(self.queue.delete("j_1"), Job)
        job = self.queue.lease("emails", "w1", 1000)
        assert job is not None
        self.assertEqual(job.id, "j_3")

    def test_a_done_job_is_never_leased_again(self) -> None:
        self.queue.create("emails", "a", 3)
        self.queue.lease("emails", "w1", 1000)
        self.queue.ack("j_1", "w1")
        self.clock.advance(10_000)
        self.assertIsNone(self.queue.lease("emails", "w2", 1000))
        self.assertEqual(leased(self, "j_1").state, "done")

    def test_list_by_id_filtered_at_most_100(self) -> None:
        for n in range(120):
            self.queue.create("a" if n % 2 else "b", str(n), 1)
        self.queue.lease("a", "w1", 1000)
        self.assertEqual(len(self.queue.jobs(None, None)), 100)
        self.assertEqual([j.id for j in self.queue.jobs("a", "leased")], ["j_2"])
        numbers = [j.number for j in self.queue.jobs("b", "queued")]
        self.assertEqual(numbers, sorted(numbers))
        self.assertEqual(len(numbers), 60)


class LeaseRunsOutTest(QueueCase):
    def test_a_lease_that_runs_out_is_leased_again_with_attempts_2(self) -> None:
        self.queue.create("emails", "a", 3)
        self.queue.lease("emails", "w1", 1000)
        self.clock.advance(1000)
        again = self.queue.lease("emails", "w2", 1000)
        assert again is not None
        self.assertEqual((again.id, again.worker, again.attempts), ("j_1", "w2", 2))

    def test_a_lease_that_runs_out_on_its_last_attempt_is_dead(self) -> None:
        self.queue.create("emails", "a", 1)
        self.queue.lease("emails", "w1", 1000)
        self.clock.advance(1001)
        self.assertEqual(leased(self, "j_1").state, "dead")
        self.assertIsNone(self.queue.lease("emails", "w2", 1000))

    def test_a_lease_is_live_until_its_last_millisecond(self) -> None:
        self.queue.create("emails", "a", 3)
        self.queue.lease("emails", "w1", 1000)
        self.clock.advance(999)
        self.assertEqual(leased(self, "j_1").state, "leased")
        self.clock.advance(1)
        self.assertEqual(leased(self, "j_1").state, "queued")

    def test_acking_after_the_lease_ran_out_is_a_conflict(self) -> None:
        self.queue.create("emails", "a", 3)
        self.queue.lease("emails", "w1", 1000)
        self.clock.advance(1500)
        self.assertIsInstance(self.queue.ack("j_1", "w1"), Conflict)
        self.assertEqual(leased(self, "j_1").state, "queued")

    def test_a_run_out_lease_never_blocks_for_more_than_one_look(self) -> None:
        self.queue.create("emails", "a", 3)
        self.queue.lease("emails", "w1", 100)
        self.clock.advance(100)
        job = self.queue.lease("emails", "w2", 100)
        assert job is not None
        self.assertEqual(job.worker, "w2")

    def test_the_idle_look_returns_run_out_leases_and_records_them(self) -> None:
        for _ in range(3):
            self.queue.create("emails", "a", 3)
            self.queue.lease("emails", "w1", 100)
        self.clock.advance(100)
        self.assertEqual(self.queue.expire_due(), 3)
        self.assertEqual(self.queue.counts()["queued"], 3)
        self.assertEqual(replay(self.dir).jobs, self.queue.snapshot())


class ReplayTest(QueueCase):
    def test_create_lease_stop_start_finds_the_lease_run_out(self) -> None:
        self.queue.create("emails", "a", 3)
        self.queue.lease("emails", "w1", 5000)
        self.restart()
        self.assertEqual(leased(self, "j_1").state, "leased")
        self.clock.advance(5000)
        self.restart()
        job = leased(self, "j_1")
        self.assertEqual((job.state, job.attempts, job.worker), ("queued", 1, None))

    def test_no_job_is_lost_across_a_restart(self) -> None:
        for n in range(10):
            self.queue.create("emails", str(n), 2)
        self.queue.lease("emails", "w1", 5000)
        self.queue.ack("j_1", "w1")
        self.queue.lease("emails", "w1", 5000)
        self.queue.fail("j_2", "w1", "x")
        self.queue.delete("j_3")
        before = self.queue.snapshot()
        self.restart()
        self.assertEqual(self.queue.snapshot(), before)

    def test_ids_never_repeat_after_a_delete_and_restart(self) -> None:
        self.queue.create("emails", "a", 1)
        self.queue.create("emails", "b", 1)
        self.queue.delete("j_2")
        self.restart()
        self.assertEqual(self.queue.create("emails", "c", 1).id, "j_3")


class DurabilityTest(QueueCase):
    def test_a_change_the_store_refuses_is_not_applied(self) -> None:
        self.queue.create("emails", "a", 3)
        before = self.queue.snapshot()
        size = self.queue.store.size
        self.ops.failing = True
        with self.assertRaises(StoreError):
            self.queue.create("emails", "b", 3)
        with self.assertRaises(StoreError):
            self.queue.lease("emails", "w1", 1000)
        self.assertEqual(self.queue.snapshot(), before)
        self.assertEqual((self.queue.store.size, replay(self.dir).jobs), (size, before))
        self.ops.failing = False
        job = self.queue.lease("emails", "w1", 1000)
        assert job is not None
        self.assertEqual((job.id, job.attempts), ("j_1", 1))
        self.assertEqual(self.queue.create("emails", "b", 3).id, "j_2")

    def test_the_record_is_in_the_store_when_the_change_returns(self) -> None:
        job = self.queue.create("emails", "a", 3)
        self.assertEqual(replay(self.dir).jobs[job.number], job)
        leased_job = self.queue.lease("emails", "w1", 1000)
        self.assertEqual(replay(self.dir).jobs[job.number], leased_job)


class RequiresTest(QueueCase):
    def test_rejects_a_bad_queue_name(self) -> None:
        for name in ("", "a b", "q" * 65):
            with self.assertRaisesRegex(ContractError, "requires the queue name is valid"):
                self.queue.create(name, "a", 1)
            with self.assertRaisesRegex(ContractError, "requires the queue name is valid"):
                self.queue.lease(name, "w1", 1000)

    def test_rejects_a_bad_payload(self) -> None:
        for payload in ("x" * (60 * 1024 + 1), "tab\there"):
            with self.assertRaisesRegex(ContractError, "requires the payload is valid"):
                self.queue.create("q", payload, 1)

    def test_rejects_max_attempts_outside_1_to_100(self) -> None:
        for value in (0, 101):
            with self.assertRaisesRegex(ContractError, "requires max_attempts is 1 to 100"):
                self.queue.create("q", "a", value)

    def test_rejects_lease_ms_outside_100_to_3600000(self) -> None:
        for value in (99, 3_600_001):
            with self.assertRaisesRegex(ContractError, "requires lease_ms is 100 to 3,600,000"):
                self.queue.lease("q", "w1", value)

    def test_rejects_a_worker_that_is_not_a_token(self) -> None:
        with self.assertRaisesRegex(ContractError, "requires the worker is a token"):
            self.queue.lease("q", "two words", 1000)


class NeversTest(QueueCase):
    """Each never is checked on every change; these tests try to break them."""

    def job(self, **update: object) -> Job:
        base = self.queue.create("emails", "a", 2)
        return base.model_copy(update=update)

    def test_a_job_is_never_held_by_two_workers_at_once(self) -> None:
        self.queue.create("emails", "a", 3)
        first = self.queue.lease("emails", "w1", 1000)
        assert first is not None
        second = first.model_copy(update={"worker": "w2", "attempts": 2})
        with self.assertRaisesRegex(ContractError, "never held by two workers"):
            check_transition(first, second)
        size = self.queue.store.size
        with self.assertRaisesRegex(ContractError, "never held by two workers"):
            self.queue._commit(first, second)
        self.assertEqual(self.queue.store.size, size)

    def test_a_done_or_dead_job_is_never_leased(self) -> None:
        for state in ("done", "dead"):
            before = self.job(state=state, attempts=2)
            after = before.model_copy(
                update={"state": "leased", "worker": "w1", "lease_until_ms": 1, "attempts": 3}
            )
            with self.assertRaisesRegex(ContractError, f"never goes {state} -> leased"):
                check_transition(before, after)

    def test_attempts_never_exceed_max_attempts(self) -> None:
        before = self.job(state="leased", attempts=2, worker="w1", lease_until_ms=1)
        after = before.model_copy(update={"state": "queued", "attempts": 3, "worker": None})
        with self.assertRaisesRegex(ContractError, "attempts never exceed max_attempts"):
            check_transition(before, after)

    def test_a_leased_job_on_its_last_attempt_never_goes_back_to_queued(self) -> None:
        before = self.job(state="leased", attempts=2, worker="w1", lease_until_ms=1)
        after = before.model_copy(update={"state": "queued", "worker": None})
        with self.assertRaisesRegex(ContractError, "dead exactly when"):
            check_transition(before, after)

    def test_skipping_the_lease_is_never_allowed(self) -> None:
        before = self.job()
        with self.assertRaisesRegex(ContractError, "never goes queued -> done"):
            check_transition(before, before.model_copy(update={"state": "done"}))

    def test_a_job_never_changes_its_payload(self) -> None:
        before = self.job(state="leased", attempts=1, worker="w1", lease_until_ms=1)
        after = before.model_copy(update={"state": "done", "payload": "other"})
        with self.assertRaisesRegex(ContractError, "fields are fixed"):
            check_transition(before, after)


class InvariantsTest(QueueCase):
    """The invariants run after every operation; each test breaks one and makes a call."""

    def test_the_counts_add_up(self) -> None:
        self.queue.create("emails", "a", 3)
        self.queue._counts["done"] += 1
        with self.assertRaisesRegex(ContractError, "invariant the counts add up"):
            self.queue.get("j_1")

    def test_no_count_is_negative(self) -> None:
        self.queue.create("emails", "a", 3)
        self.queue._counts["done"] -= 1
        self.queue._counts["queued"] += 1
        with self.assertRaisesRegex(ContractError, "invariant no count is negative"):
            self.queue.counts()

    def test_a_worker_exactly_while_leased(self) -> None:
        job = self.queue.create("emails", "a", 3)
        self.queue._jobs[job.number] = job.model_copy(update={"worker": "w1"})
        self.queue._touched.append(job.number)
        with self.assertRaisesRegex(ContractError, "invariant a job has a worker exactly"):
            self.queue.counts()

    def test_a_job_sits_under_its_own_number(self) -> None:
        job = self.queue.create("emails", "a", 3)
        self.queue._jobs[job.number] = job.model_copy(update={"number": 5})
        self.queue._touched.append(job.number)
        with self.assertRaisesRegex(ContractError, "invariant a job sits under its own number"):
            self.queue.counts()


if __name__ == "__main__":
    unittest.main()
