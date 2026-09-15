import shutil
import unittest
from collections.abc import Callable
from unittest import mock

from jobq.contract import ContractError
from jobq.jobs import Job
from jobq.queue import Conflict, NotFound, check_transition
from jobq.store import LOG_NAME, StoreError, compact, replay
from support import FIXTURES, QueueCase


def leased(queue_case: QueueCase, job_id: str) -> Job:
    job = queue_case.queue.get(job_id)
    assert job is not None
    return job


class LifecycleTest(QueueCase):
    def test_create_queues_a_job_with_a_new_id(self) -> None:
        first = self.queue.create("emails", "a", 3)
        second = self.queue.create("emails", "b", 3)
        self.assertEqual((first.id, second.id), ("j_1", "j_2"))
        self.assertEqual((first.state, first.tries), ("queued", 0))

    def test_lease_hands_out_the_oldest_queued_job_of_that_queue(self) -> None:
        self.queue.create("other", "x", 3)
        self.queue.create("emails", "a", 3)
        self.queue.create("emails", "b", 3)
        job = self.queue.lease("emails", "w1", 1000)
        assert job is not None
        self.assertEqual((job.id, job.payload), ("j_2", "a"))

    def test_lease_ensures_the_job_is_leased_to_the_caller_one_try_higher(self) -> None:
        self.queue.create("emails", "a", 3)
        job = self.queue.lease("emails", "w1", 1000)
        assert job is not None
        self.assertEqual((job.state, job.worker, job.tries), ("leased", "w1", 1))
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

    def test_fail_requeues_with_the_reason_until_the_last_try(self) -> None:
        self.queue.create("emails", "a", 2)
        self.queue.lease("emails", "w1", 1000)
        first = self.queue.fail("j_1", "w1", "smtp down")
        assert isinstance(first, Job)
        self.assertEqual((first.state, first.tries, first.reason), ("queued", 1, "smtp down"))
        self.queue.lease("emails", "w2", 1000)
        second = self.queue.fail("j_1", "w2", "still down")
        assert isinstance(second, Job)
        self.assertEqual((second.state, second.tries), ("dead", 2))
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
    def test_a_lease_that_runs_out_is_leased_again_with_tries_2(self) -> None:
        self.queue.create("emails", "a", 3)
        self.queue.lease("emails", "w1", 1000)
        self.clock.advance(1000)
        again = self.queue.lease("emails", "w2", 1000)
        assert again is not None
        self.assertEqual((again.id, again.worker, again.tries), ("j_1", "w2", 2))

    def test_a_lease_that_runs_out_on_its_last_try_is_dead(self) -> None:
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

    def test_a_look_whose_expiry_write_fails_changes_nothing_and_retries(self) -> None:
        for _ in range(3):
            self.queue.create("emails", "a", 3)
            self.queue.lease("emails", "w1", 100)
        self.clock.advance(100)
        before = self.queue.snapshot()
        size = self.queue.store.size
        self.ops.failing = True
        with self.assertRaises(StoreError):
            self.queue.counts()
        self.assertEqual((self.queue.snapshot(), self.queue.store.size), (before, size))
        self.ops.failing = False
        self.assertEqual(self.queue.counts()["queued"], 3)
        self.assertEqual(replay(self.dir).jobs, self.queue.snapshot())

    def test_run_out_leases_are_returned_in_one_write(self) -> None:
        for _ in range(50):
            self.queue.create("emails", "a", 3)
            self.queue.lease("emails", "w1", 100)
        self.clock.advance(100)
        with mock.patch.object(self.ops, "fsync", wraps=self.ops.fsync) as fsync:
            self.assertEqual(self.queue.expire_due(), 50)
        self.assertEqual(fsync.call_count, 1)


class ReplayTest(QueueCase):
    def test_create_lease_stop_start_finds_the_lease_run_out(self) -> None:
        self.queue.create("emails", "a", 3)
        self.queue.lease("emails", "w1", 5000)
        self.restart()
        self.assertEqual(leased(self, "j_1").state, "leased")
        self.clock.advance(5000)
        self.restart()
        job = leased(self, "j_1")
        self.assertEqual((job.state, job.tries, job.worker), ("queued", 1, None))

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
        self.assertEqual((job.id, job.tries), ("j_1", 1))
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

    def test_rejects_max_tries_outside_1_to_100(self) -> None:
        for value in (0, 101):
            with self.assertRaisesRegex(ContractError, "requires max_tries is 1 to 100"):
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
        second = first.model_copy(update={"worker": "w2", "tries": 2})
        with self.assertRaisesRegex(ContractError, "never held by two workers"):
            check_transition(first, second)
        size = self.queue.store.size
        with self.assertRaisesRegex(ContractError, "never held by two workers"):
            self.queue._commit(first, second)
        self.assertEqual(self.queue.store.size, size)

    def test_a_done_or_dead_job_is_never_leased(self) -> None:
        for state in ("done", "dead"):
            before = self.job(state=state, tries=2)
            after = before.model_copy(
                update={"state": "leased", "worker": "w1", "lease_until_ms": 1, "tries": 3}
            )
            with self.assertRaisesRegex(ContractError, f"never goes {state} -> leased"):
                check_transition(before, after)

    def test_tries_never_exceed_max_tries(self) -> None:
        before = self.job(state="leased", tries=2, worker="w1", lease_until_ms=1)
        after = before.model_copy(update={"state": "queued", "tries": 3, "worker": None})
        with self.assertRaisesRegex(ContractError, "tries never exceed max_tries"):
            check_transition(before, after)

    def test_a_leased_job_on_its_last_try_never_goes_back_to_queued(self) -> None:
        before = self.job(state="leased", tries=2, worker="w1", lease_until_ms=1)
        after = before.model_copy(update={"state": "queued", "worker": None})
        with self.assertRaisesRegex(ContractError, "dead exactly when"):
            check_transition(before, after)

    def test_skipping_the_lease_is_never_allowed(self) -> None:
        before = self.job()
        with self.assertRaisesRegex(ContractError, "never goes queued -> done"):
            check_transition(before, before.model_copy(update={"state": "done"}))

    def test_a_job_never_changes_its_payload(self) -> None:
        before = self.job(state="leased", tries=1, worker="w1", lease_until_ms=1)
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


class ScheduledTest(QueueCase):
    def test_a_delayed_job_is_not_leased_before_run_at_and_is_leased_after(self) -> None:
        job = self.queue.create("emails", "a", 3, delay_ms=5000)
        self.assertEqual((job.state, job.run_at_ms), ("scheduled", self.clock.ms + 5000))
        self.clock.advance(4999)
        self.assertIsNone(self.queue.lease("emails", "w1", 1000))
        self.clock.advance(1)
        leased_job = self.queue.lease("emails", "w1", 1000)
        assert leased_job is not None
        self.assertEqual((leased_job.id, leased_job.tries, leased_job.run_at_ms), ("j_1", 1, None))

    def test_a_fail_with_backoff_is_scheduled_at_now_plus_backoff(self) -> None:
        self.queue.create("emails", "a", 3, backoff_ms=2000)
        self.queue.lease("emails", "w1", 1000)
        self.clock.advance(300)
        failed = self.queue.fail("j_1", "w1", "smtp down")
        assert isinstance(failed, Job)
        self.assertEqual((failed.state, failed.tries, failed.reason), ("scheduled", 1, "smtp down"))
        self.assertEqual((failed.run_at_ms, failed.worker), (self.clock.ms + 2000, None))
        self.clock.advance(1999)
        self.assertIsNone(self.queue.lease("emails", "w2", 1000))
        self.clock.advance(1)
        again = self.queue.lease("emails", "w2", 1000)
        assert again is not None
        self.assertEqual((again.id, again.tries), ("j_1", 2))

    def test_a_fail_with_backoff_on_the_last_try_is_dead(self) -> None:
        self.queue.create("emails", "a", 1, backoff_ms=2000)
        self.queue.lease("emails", "w1", 1000)
        failed = self.queue.fail("j_1", "w1", "x")
        assert isinstance(failed, Job)
        self.assertEqual((failed.state, failed.tries, failed.run_at_ms), ("dead", 1, None))

    def test_a_run_out_lease_with_backoff_is_scheduled_and_without_is_queued(self) -> None:
        self.queue.create("emails", "a", 3, backoff_ms=500)
        self.queue.create("emails", "b", 3)
        self.queue.lease("emails", "w1", 1000)
        self.queue.lease("emails", "w1", 1000)
        self.clock.advance(1000)
        backed_off, requeued = leased(self, "j_1"), leased(self, "j_2")
        due = self.clock.ms + 500
        self.assertEqual((backed_off.state, backed_off.run_at_ms), ("scheduled", due))
        self.assertEqual((requeued.state, requeued.run_at_ms), ("queued", None))
        self.assertEqual(replay(self.dir).jobs, self.queue.snapshot())

    def test_a_run_out_lease_with_backoff_on_the_last_try_is_dead(self) -> None:
        self.queue.create("emails", "a", 1, backoff_ms=500)
        self.queue.lease("emails", "w1", 1000)
        self.clock.advance(1000)
        self.assertEqual(leased(self, "j_1").state, "dead")

    def test_a_due_job_counts_as_queued_in_id_order(self) -> None:
        self.queue.create("emails", "a", 3, delay_ms=1000)
        self.queue.create("emails", "b", 3)
        self.clock.advance(1000)
        first = self.queue.lease("emails", "w1", 1000)
        assert first is not None
        self.assertEqual(first.id, "j_1")

    def test_every_look_queues_a_due_job_and_records_it(self) -> None:
        looks: list[Callable[[], object]] = [
            lambda: self.queue.get("j_1"),
            lambda: self.queue.jobs("emails", "scheduled"),
            self.queue.counts,
            self.queue.expire_due,
            lambda: self.queue.lease("other", "w1", 1000),
            lambda: self.queue.ack("j_1", "w1"),
        ]
        for number, look in enumerate(looks, start=1):
            self.queue.create("emails", "a", 3, delay_ms=100)
            self.clock.advance(99)
            look()
            self.assertEqual(replay(self.dir).jobs[number].state, "scheduled", number)
            self.clock.advance(1)
            look()
            self.assertEqual(replay(self.dir).jobs[number].state, "queued", number)
        self.assertEqual(replay(self.dir).jobs, self.queue.snapshot())

    def test_due_jobs_are_queued_in_one_write(self) -> None:
        for _ in range(50):
            self.queue.create("emails", "a", 3, delay_ms=100)
        self.clock.advance(100)
        with mock.patch.object(self.ops, "fsync", wraps=self.ops.fsync) as fsync:
            self.assertEqual(self.queue.expire_due(), 50)
        self.assertEqual(fsync.call_count, 1)

    def test_a_look_whose_due_write_fails_changes_nothing_and_retries(self) -> None:
        self.queue.create("emails", "a", 3, delay_ms=100)
        self.clock.advance(100)
        before, size = self.queue.snapshot(), self.queue.store.size
        self.ops.failing = True
        with self.assertRaises(StoreError):
            self.queue.counts()
        self.assertEqual((self.queue.snapshot(), self.queue.store.size), (before, size))
        self.ops.failing = False
        self.assertEqual(self.queue.counts()["queued"], 1)
        self.assertEqual(replay(self.dir).jobs, self.queue.snapshot())

    def test_a_scheduled_job_can_be_deleted(self) -> None:
        self.queue.create("emails", "a", 3, delay_ms=100)
        self.assertIsInstance(self.queue.delete("j_1"), Job)
        self.clock.advance(100)
        self.assertEqual(self.queue.expire_due(), 0)
        self.assertIsNone(self.queue.lease("emails", "w1", 1000))

    def test_a_scheduled_job_survives_a_restart(self) -> None:
        job = self.queue.create("emails", "a", 3, delay_ms=5000)
        self.restart()
        self.assertEqual(leased(self, "j_1"), job)
        self.clock.advance(5000)
        self.restart()
        again = self.queue.lease("emails", "w1", 1000)
        assert again is not None
        self.assertEqual((again.id, again.tries), ("j_1", 1))


class RetryTest(QueueCase):
    def dead_job(self) -> str:
        job = self.queue.create("emails", "a", 2, backoff_ms=100)
        for worker in ("w1", "w2"):
            self.clock.advance(100)
            self.queue.lease("emails", worker, 1000)
            self.queue.fail(job.id, worker, "boom")
        self.assertEqual(leased(self, job.id).state, "dead")
        return job.id

    def test_a_retry_of_a_dead_job_is_queued_with_tries_0_and_leased_again(self) -> None:
        job_id = self.dead_job()
        retried = self.queue.retry(job_id)
        assert isinstance(retried, Job)
        self.assertEqual((retried.state, retried.tries, retried.reason), ("queued", 0, None))
        self.assertEqual((retried.run_at_ms, retried.worker, retried.lease_until_ms), (None,) * 3)
        kept = (retried.queue, retried.payload, retried.max_tries, retried.backoff_ms)
        self.assertEqual(kept, ("emails", "a", 2, 100))
        self.assertEqual(replay(self.dir).jobs[retried.number], retried)
        again = self.queue.lease("emails", "w3", 1000)
        assert again is not None
        self.assertEqual((again.id, again.tries), (job_id, 1))

    def test_a_retried_job_takes_its_place_by_id(self) -> None:
        job_id = self.dead_job()
        self.queue.create("emails", "b", 1)
        self.queue.retry(job_id)
        first = self.queue.lease("emails", "w1", 1000)
        assert first is not None
        self.assertEqual(first.id, job_id)

    def test_a_retry_of_a_job_that_is_not_dead_is_a_conflict(self) -> None:
        self.queue.create("q", "queued", 3)
        self.queue.create("s", "scheduled", 3, delay_ms=10_000)
        self.queue.create("l", "leased", 3)
        self.queue.lease("l", "w1", 1000)
        self.queue.create("d", "done", 3)
        self.queue.lease("d", "w1", 1000)
        self.queue.ack("j_4", "w1")
        before, size = self.queue.snapshot(), self.queue.store.size
        for job_id in ("j_1", "j_2", "j_3", "j_4"):
            self.assertIsInstance(self.queue.retry(job_id), Conflict, job_id)
        self.assertEqual((self.queue.snapshot(), self.queue.store.size), (before, size))
        self.assertIsInstance(self.queue.retry("j_9"), NotFound)

    def test_a_retry_the_store_refuses_leaves_the_job_dead(self) -> None:
        job_id = self.dead_job()
        self.ops.failing = True
        with self.assertRaises(StoreError):
            self.queue.retry(job_id)
        self.ops.failing = False
        self.assertEqual(leased(self, job_id).state, "dead")

    def test_a_retry_survives_a_restart(self) -> None:
        self.queue.retry(self.dead_job())
        before = self.queue.snapshot()
        self.restart()
        self.assertEqual(self.queue.snapshot(), before)


class OldLogTest(QueueCase):
    """A folder the round 7 program served, before the tries rename: tests/fixtures/round7."""

    STOPPED_MS = 1_789_511_081_953  # just after the fixture's last write
    J5_LEASE_UNTIL_MS = 1_789_514_681_952

    def setUp(self) -> None:
        super().setUp()
        self.queue.store.close()
        shutil.copyfile(FIXTURES / "round7" / LOG_NAME, self.dir / LOG_NAME)
        self.clock.ms = self.STOPPED_MS
        self.queue, self.api = self.open()

    def test_the_fixture_is_in_the_old_shape(self) -> None:
        log = (FIXTURES / "round7" / LOG_NAME).read_bytes()
        self.assertIn(b'"max_attempts":', log)
        self.assertNotIn(b'"tries"', log)
        self.assertNotIn(b'"backoff_ms"', log)

    def test_every_job_replays_with_its_state(self) -> None:
        summary = {
            job.id: (job.state, job.tries, job.max_tries, job.backoff_ms, job.worker, job.reason)
            for job in self.queue.snapshot().values()
        }
        self.assertEqual(
            summary,
            {
                "j_1": ("done", 1, 2, 0, None, None),
                "j_2": ("dead", 1, 1, 0, None, "bad address"),
                "j_3": ("queued", 1, 3, 0, None, "smtp down"),
                "j_5": ("leased", 1, 3, 0, "w4", None),
                "j_6": ("queued", 0, 5, 0, None, None),
            },
        )
        counts = {"queued": 2, "scheduled": 0, "leased": 1, "done": 1, "dead": 1}
        self.assertEqual(self.queue.counts(), counts)
        self.assertEqual(self.queue.create("emails", "new", 1).id, "j_7")

    def test_the_job_leased_when_the_old_service_stopped_is_queued_at_its_next_look(self) -> None:
        self.clock.ms = self.J5_LEASE_UNTIL_MS
        job = leased(self, "j_5")
        self.assertEqual((job.state, job.tries, job.worker), ("queued", 1, None))
        self.assertEqual(replay(self.dir).jobs[5], job)
        again = self.queue.lease("reports", "w9", 1000)
        assert again is not None
        self.assertEqual((again.id, again.tries), ("j_5", 2))

    def test_old_jobs_take_the_new_routes(self) -> None:
        retried = self.queue.retry("j_2")
        assert isinstance(retried, Job)
        self.assertEqual((retried.state, retried.tries, retried.reason), ("queued", 0, None))
        first = self.queue.lease("emails", "w1", 1000)
        assert first is not None
        self.assertEqual((first.id, first.tries), ("j_2", 1))

    def test_writes_after_the_replay_use_only_the_new_names(self) -> None:
        size = len((self.dir / LOG_NAME).read_bytes())
        self.queue.create("emails", "new", 2, backoff_ms=10)
        self.queue.retry("j_2")
        appended = (self.dir / LOG_NAME).read_bytes()[size:]
        self.assertEqual(appended.count(b"\n"), 2)
        self.assertNotIn(b"attempts", appended)

    def test_compaction_leaves_no_old_name_and_keeps_every_job(self) -> None:
        before = self.queue.snapshot()
        self.queue.store.close()
        records = compact(self.dir)
        self.queue, self.api = self.open()
        self.assertEqual(records, (14, 6))
        self.assertNotIn(b"attempts", (self.dir / LOG_NAME).read_bytes())
        self.assertEqual(self.queue.snapshot(), before)


class ScheduleRequiresTest(QueueCase):
    def test_rejects_delay_ms_outside_0_to_86400000(self) -> None:
        for value in (-1, 86_400_001):
            with self.assertRaisesRegex(ContractError, "requires delay_ms is 0 to 86,400,000"):
                self.queue.create("q", "a", 1, delay_ms=value)

    def test_rejects_backoff_ms_outside_0_to_3600000(self) -> None:
        for value in (-1, 3_600_001):
            with self.assertRaisesRegex(ContractError, "requires backoff_ms is 0 to 3,600,000"):
                self.queue.create("q", "a", 1, backoff_ms=value)


class ScheduleNeversTest(QueueCase):
    """The nevers the change added or opened, tried directly."""

    def job(self, **update: object) -> Job:
        base = self.queue.create("emails", "a", 2, backoff_ms=100)
        return base.model_copy(update=update)

    def test_a_scheduled_job_is_never_leased(self) -> None:
        before = self.job(state="scheduled", run_at_ms=5)
        after = before.model_copy(
            update={"state": "leased", "tries": 1, "worker": "w1", "lease_until_ms": 9}
        )
        with self.assertRaisesRegex(ContractError, "never goes scheduled -> leased"):
            check_transition(before, after)

    def test_a_scheduled_job_is_never_queued_before_its_run_at(self) -> None:
        run_at = self.clock.ms + 10
        before = self.job(state="scheduled", run_at_ms=run_at)
        early = before.model_copy(
            update={"state": "queued", "run_at_ms": None, "updated_ms": run_at - 1}
        )
        with self.assertRaisesRegex(ContractError, "never queued before its run_at"):
            check_transition(before, early)
        check_transition(before, early.model_copy(update={"updated_ms": run_at}))

    def test_a_retry_never_touches_a_job_that_is_not_dead(self) -> None:
        for state, text in (
            ("done", "never goes done -> queued"),
            ("queued", "never goes queued -> queued"),
            ("scheduled", "only a retry resets"),
            ("leased", "only a retry resets"),
        ):
            before = self.job(state=state, tries=1)
            after = before.model_copy(update={"state": "queued", "tries": 0})
            with self.assertRaisesRegex(ContractError, text, msg=state):
                check_transition(before, after)

    def test_a_retry_always_sets_tries_to_0(self) -> None:
        before = self.job(state="dead", tries=2)
        with self.assertRaisesRegex(ContractError, "a retry sets tries to 0"):
            check_transition(before, before.model_copy(update={"state": "queued"}))

    def test_a_returned_job_is_scheduled_exactly_when_it_has_a_backoff(self) -> None:
        before = self.job(state="leased", tries=1, worker="w1", lease_until_ms=1)
        returned = {"state": "queued", "worker": None, "lease_until_ms": None}
        queued = before.model_copy(update=returned)
        with self.assertRaisesRegex(ContractError, "scheduled exactly when it has a backoff"):
            check_transition(before, queued)

    def test_backoff_is_fixed_at_creation(self) -> None:
        before = self.job(state="leased", tries=1, worker="w1", lease_until_ms=1)
        after = before.model_copy(update={"state": "done", "backoff_ms": 0, "worker": None})
        with self.assertRaisesRegex(ContractError, "fields are fixed"):
            check_transition(before, after)


class ScheduleInvariantsTest(QueueCase):
    def test_run_at_exactly_while_scheduled(self) -> None:
        job = self.queue.create("emails", "a", 3)
        self.queue._jobs[job.number] = job.model_copy(update={"run_at_ms": 5})
        self.queue._touched.append(job.number)
        with self.assertRaisesRegex(ContractError, "invariant run_at exactly while scheduled"):
            self.queue.counts()

    def test_the_scheduled_count_is_right(self) -> None:
        self.queue.create("emails", "a", 3, delay_ms=100)
        self.queue._counts["scheduled"] -= 1
        self.queue._counts["dead"] += 1
        with self.assertRaisesRegex(ContractError, "invariant the scheduled count is right"):
            self.queue.check_all()


if __name__ == "__main__":
    unittest.main()
