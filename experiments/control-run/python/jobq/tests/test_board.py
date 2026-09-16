"""The board restarts itself from the log, within a budget, and `--crash-every` rehearses it."""

import contextlib
import io
import unittest
from unittest import mock

from jobq.board import Board, BoardOptions
from jobq.contract import ContractError
from jobq.jobs import Job
from jobq.queue import Chaos, Queue
from jobq.store import LOG_NAME, Store, StoreOpenError, replay
from support import QueueCase, body_of

RESTARTING = {"error": "the service is restarting; read the job to learn what happened"}
SPENT = {"error": "jobq is stopping: the restart budget is spent"}
JOB = {"queue": "emails", "payload": "p", "max_tries": 3}


class FakeMonotonic:
    def __init__(self) -> None:
        self.s = 1000.0

    def __call__(self) -> float:
        return self.s


class BoardCase(QueueCase):
    def setUp(self) -> None:
        super().setUp()
        self.seconds = FakeMonotonic()
        self._quiet = contextlib.redirect_stderr(io.StringIO())
        self.stderr = self._quiet.__enter__()

    def tearDown(self) -> None:
        self._quiet.__exit__(None, None, None)
        super().tearDown()

    def board(self, **options: int) -> None:
        """Reopen the folder as a board with these options and the fake monotonic clock."""
        self.api.close()
        self.api = Board(
            self.dir, self.clock, self.ops, BoardOptions(**options), monotonic=self.seconds
        )

    def assert_board_is_the_log(self) -> None:
        self.assertEqual(self.queue.snapshot(), replay(self.dir).jobs)

    def health(self) -> dict[str, object]:
        response = self.call("GET", "/health")
        self.assertEqual(response.status, 200)
        return body_of(response)


class ChaosTest(unittest.TestCase):
    def test_zero_never_fails(self) -> None:
        chaos = Chaos(0)
        self.assertFalse(any(chaos.fails(1) for _ in range(1000)))

    def test_every_nth_change_fails_and_a_batch_counts_each_change(self) -> None:
        chaos = Chaos(3)
        self.assertEqual([chaos.fails(1) for _ in range(6)], [False, False, True] * 2)
        self.assertTrue(chaos.fails(5))  # changes 7 to 11 hold 9
        self.assertTrue(chaos.fails(1))  # 12
        self.assertFalse(chaos.fails(2))  # 13 and 14

    def test_a_negative_count_is_refused(self) -> None:
        with self.assertRaises(ContractError):
            Chaos(-1)


class RestartTest(BoardCase):
    def test_the_crashing_write_is_a_503_and_is_on_the_board_after(self) -> None:
        self.board(crash_every=2)
        self.assertEqual(self.health()["restarts"], 0)
        self.assertEqual(self.call("POST", "/jobs", JOB).status, 201)
        crashed = self.call("POST", "/jobs", JOB)
        self.assertEqual((crashed.status, crashed.json()), (503, RESTARTING))
        self.assertEqual(self.health()["restarts"], 1)
        self.assertEqual(body_of(self.call("GET", "/jobs/j_2"))["state"], "queued")
        self.assert_board_is_the_log()
        self.assertIn("rebuilding it from the log", self.stderr.getvalue())

    def test_the_switch_counts_writes_not_requests(self) -> None:
        self.board(crash_every=3)
        for _ in range(4):
            self.assertEqual(self.call("GET", "/health").status, 200)
            self.assertEqual(self.call("GET", "/jobs").status, 200)
        self.create(delay_ms=100)
        self.create(delay_ms=100)
        self.clock.advance(100)
        # The look this read takes queues both jobs: changes 3 and 4, and 3 fails.
        self.assertEqual(self.call("GET", "/jobs/j_1").status, 503)
        self.assertEqual(self.api.restarts, 1)
        self.assertEqual([job.state for job in self.queue.snapshot().values()], ["queued"] * 2)
        self.assert_board_is_the_log()

    def test_every_kind_of_write_counts(self) -> None:
        self.board(crash_every=1, max_restarts=100)
        refused = [
            self.call("POST", "/jobs", JOB | {"max_tries": 1}).status,  # j_1
            self.call("POST", "/jobs", JOB).status,  # j_2
            self.call("POST", "/queues/emails/lease", {"lease_ms": 1000}).status,  # j_1
            self.call("POST", "/jobs/j_1/fail", {"reason": "r"}).status,  # dead
            self.call("POST", "/jobs/j_1/retry").status,
            self.call("POST", "/queues/emails/lease", {"lease_ms": 1000}).status,  # j_1
            self.call("POST", "/jobs/j_1/ack").status,
            self.call("DELETE", "/jobs/j_1").status,
        ]
        self.assertEqual(refused, [503] * 8)
        self.assertEqual(self.api.restarts, 8)
        self.assertEqual(list(replay(self.dir).jobs), [2])
        self.assert_board_is_the_log()

    def test_leases_survive_with_their_lease_until_and_ids_continue(self) -> None:
        self.board(crash_every=3)
        first = self.create()
        leased = self.call("POST", "/queues/emails/lease", {"lease_ms": 5000})
        self.assertEqual(leased.status, 200)
        self.assertEqual(self.call("POST", "/jobs", JOB).status, 503)  # j_2, on disk
        after = body_of(self.call("GET", f"/jobs/{first}"))
        self.assertEqual(after, body_of(leased))
        self.assertEqual(self.create(), "j_3")
        self.assertEqual(self.call("POST", f"/jobs/{first}/ack").status, 200)
        self.clock.advance(5000)
        self.assert_board_is_the_log()

    def test_a_lease_that_ran_out_during_the_restart_is_returned_at_the_next_look(self) -> None:
        self.board(crash_every=2)
        job_id = self.create()
        self.assertEqual(self.call("POST", "/queues/emails/lease", {"lease_ms": 100}).status, 503)
        self.clock.advance(100)
        self.assertEqual(body_of(self.call("GET", f"/jobs/{job_id}"))["state"], "queued")

    def test_an_unexpected_error_while_a_change_is_applied_restarts_the_board(self) -> None:
        job_id = self.create()
        real = Queue._apply
        calls: list[Job | None] = []

        def half_applied(queue: Queue, before: Job | None, after: Job | None) -> None:
            calls.append(after)
            real(queue, before, after)
            if len(calls) == 1:
                raise ZeroDivisionError("mid-apply")

        with mock.patch.object(Queue, "_apply", half_applied):
            response = self.call("POST", "/queues/emails/lease", {"lease_ms": 1000})
        self.assertEqual((response.status, response.json()), (503, RESTARTING))
        self.assertEqual(self.api.restarts, 1)
        self.assertEqual(body_of(self.call("GET", f"/jobs/{job_id}"))["state"], "leased")
        self.assert_board_is_the_log()
        self.assertIn("ZeroDivisionError", self.stderr.getvalue())

    def test_a_failing_idle_look_restarts_the_board(self) -> None:
        self.board(crash_every=1)
        with mock.patch.object(Chaos, "fails", return_value=False):
            self.create(delay_ms=10)
        self.clock.advance(10)
        self.assertEqual(self.api.expire_due(), 0)
        self.assertEqual(self.api.restarts, 1)
        self.assertEqual(self.queue.snapshot()[1].state, "queued")

    def test_a_store_that_cannot_be_written_is_not_a_restart(self) -> None:
        self.board(crash_every=1)
        self.ops.failing = True
        self.assertEqual(self.call("POST", "/jobs", JOB).status, 503)
        self.assertEqual(self.api.restarts, 0)

    def test_the_board_after_a_restart_is_the_board_a_fresh_serve_opens(self) -> None:
        self.board(crash_every=2, max_restarts=100)
        for _ in range(7):
            self.call("POST", "/jobs", JOB)
            self.call("POST", "/queues/emails/lease", {"lease_ms": 1000})
        self.assertEqual(self.api.restarts, 7)
        before = self.queue.snapshot()
        self.restart()
        self.assertEqual(self.queue.snapshot(), before)
        self.assertEqual(self.health()["restarts"], 0)


class BudgetTest(BoardCase):
    def test_the_failure_after_the_last_restart_stops_the_board(self) -> None:
        self.board(crash_every=1, max_restarts=2, restart_window_s=60)
        self.assertEqual(self.call("POST", "/jobs", JOB).status, 503)
        self.seconds.s += 30
        self.assertEqual(self.call("POST", "/jobs", JOB).status, 503)
        self.assertFalse(self.api.exhausted)
        self.seconds.s += 29
        spent = self.call("POST", "/jobs", JOB)
        self.assertEqual(spent.status, 503)
        self.assertTrue(self.api.exhausted)
        self.assertEqual(self.api.restarts, 2)
        size = (self.dir / LOG_NAME).stat().st_size
        for method, path in (("POST", "/jobs"), ("GET", "/health"), ("GET", "/jobs/j_1")):
            answer = self.call(method, path, JOB if method == "POST" else None)
            self.assertEqual((answer.status, answer.json()), (503, SPENT))
        self.assertEqual(self.api.expire_due(), 0)
        # The spent board wrote its third record and nothing more, and the folder reopens.
        self.assertEqual((self.dir / LOG_NAME).stat().st_size, size)
        store, replayed = Store.open(self.dir)
        store.close()
        self.assertEqual(list(replayed.jobs), [1, 2, 3])
        self.assertIn("2 restarts in 60 s; stopping", self.stderr.getvalue())

    def test_a_failure_after_the_window_starts_a_fresh_count(self) -> None:
        self.board(crash_every=1, max_restarts=1, restart_window_s=10)
        for _ in range(5):
            self.assertEqual(self.call("POST", "/jobs", JOB).status, 503)
            self.assertFalse(self.api.exhausted)
            self.seconds.s += 10
        self.assertEqual(self.api.restarts, 5)
        self.seconds.s -= 1  # nine seconds after the last restart
        self.call("POST", "/jobs", JOB)
        self.assertTrue(self.api.exhausted)

    def test_no_restarts_allowed_stops_at_the_first_failure(self) -> None:
        self.board(crash_every=1, max_restarts=0)
        self.assertEqual(self.call("POST", "/jobs", JOB).status, 503)
        self.assertTrue(self.api.exhausted)
        self.assertEqual(self.api.restarts, 0)
        self.assertEqual(list(replay(self.dir).jobs), [1])

    def test_a_folder_that_will_not_reopen_spends_the_budget(self) -> None:
        self.board(crash_every=1, max_restarts=3)
        unopenable = mock.patch.object(Store, "open", side_effect=StoreOpenError("gone"))
        with unopenable, mock.patch("jobq.board.time.sleep") as sleep:
            self.assertEqual(self.call("POST", "/jobs", JOB).status, 503)
        self.assertTrue(self.api.exhausted)
        self.assertEqual((self.api.restarts, sleep.call_count), (3, 3))
        self.assertIn("cannot be rebuilt: gone", self.stderr.getvalue())

    def test_the_budget_is_checked(self) -> None:
        with self.assertRaises(ContractError):
            self.board(max_restarts=-1)
        self.api = self.open()
        with self.assertRaises(ContractError):
            self.board(restart_window_s=0)
        self.api = self.open()


if __name__ == "__main__":
    unittest.main()
