import errno
import json
import os
import re
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from jobq.jobs import Job
from jobq.store import (
    LOG_NAME,
    DeleteRecord,
    PutRecord,
    Store,
    StoreError,
    StoreOpenError,
    compact,
    replay,
)
from support import FIXTURES, FailingOps


def job(number: int, state: str = "queued") -> Job:
    """A well-formed job in `state`: the tries and the fields that state must carry."""
    waiting = state in {"queued", "scheduled"}
    return Job.model_validate(
        {
            "number": number,
            "queue": "q",
            "state": state,
            "payload": f"payload {number}",
            "tries": 0 if waiting else 1,
            "max_tries": 2,
            "backoff_ms": 0,
            "created_ms": 1,
            "updated_ms": 1,
        }
        | ({"run_at_ms": 9} if state == "scheduled" else {})
        | ({"worker": "w1", "lease_until_ms": 9} if state == "leased" else {})
    )


def old_record(number: int, state: str = "queued", **fields: object) -> str:
    """A put record in the shape the round 7 program wrote, spaced as a hand writes it."""
    job_fields = {
        "number": number,
        "queue": "q",
        "state": state,
        "payload": f"payload {number}",
        "attempts": 0,
        "max_attempts": 2,
        "created_ms": 1,
        "updated_ms": 1,
    } | fields
    return json.dumps({"kind": "put", "job": job_fields}) + "\n"


class StoreCase(unittest.TestCase):
    """A fresh store directory per test."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()


class StoreTest(StoreCase):
    def test_an_empty_directory_replays_to_nothing(self) -> None:
        store, state = Store.open(self.dir)
        store.close()
        self.assertEqual((state.jobs, state.next_number, state.records), ({}, 1, 0))

    def test_appended_records_replay_with_the_last_record_per_job(self) -> None:
        store, _ = Store.open(self.dir)
        store.append(PutRecord(job=job(1)))
        store.append(PutRecord(job=job(2)))
        store.append(PutRecord(job=job(1, "done")))
        store.append(DeleteRecord(number=2))
        store.close()
        _, state = Store.open(self.dir)
        self.assertEqual(state.jobs, {1: job(1, "done")})
        self.assertEqual((state.next_number, state.records), (3, 4))

    def test_a_torn_last_line_is_cut_off(self) -> None:
        store, _ = Store.open(self.dir)
        store.append(PutRecord(job=job(1)))
        store.close()
        whole = (self.dir / LOG_NAME).stat().st_size
        with (self.dir / LOG_NAME).open("ab") as log:
            log.write(b'{"kind": "put", "job": {"num')
        store, state = Store.open(self.dir)
        self.assertEqual(list(state.jobs), [1])
        self.assertEqual((self.dir / LOG_NAME).stat().st_size, whole)
        store.append(PutRecord(job=job(2)))
        store.close()
        self.assertEqual(list(replay(self.dir).jobs), [1, 2])

    def test_a_corrupt_whole_line_refuses_to_open(self) -> None:
        (self.dir / LOG_NAME).write_bytes(b'{"kind": "put"}\n')
        with self.assertRaisesRegex(StoreOpenError, "record line 1: job field required"):
            Store.open(self.dir)

    def test_a_second_open_of_the_same_directory_is_refused(self) -> None:
        store, _ = Store.open(self.dir)
        try:
            with self.assertRaisesRegex(StoreOpenError, "in use"):
                Store.open(self.dir)
        finally:
            store.close()

    def test_a_missing_directory_is_refused(self) -> None:
        with self.assertRaises(StoreOpenError):
            Store.open(self.dir / "missing")

    def test_a_failed_write_leaves_the_log_as_it_was(self) -> None:
        ops = FailingOps()
        store, _ = Store.open(self.dir, ops)
        store.append(PutRecord(job=job(1)))
        before = (self.dir / LOG_NAME).read_bytes()
        ops.failing = True
        with self.assertRaisesRegex(StoreError, "injected write failure"):
            store.append(PutRecord(job=job(2)))
        self.assertEqual((self.dir / LOG_NAME).read_bytes(), before)
        ops.fail_fsync_only = True
        with self.assertRaisesRegex(StoreError, "injected fsync failure"):
            store.append(PutRecord(job=job(2)))
        self.assertEqual((self.dir / LOG_NAME).read_bytes(), before)
        ops.failing = False
        store.append(PutRecord(job=job(2)))
        store.close()
        self.assertEqual(list(replay(self.dir).jobs), [1, 2])

    def test_a_write_that_makes_no_progress_is_a_failure(self) -> None:
        class Stuck:
            def write(self, fd: int, data: bytes) -> int:
                return 0

            def fsync(self, fd: int) -> None:
                raise OSError(errno.EIO, "unreachable")

        store, _ = Store.open(self.dir, Stuck())
        with self.assertRaisesRegex(StoreError, "short write"):
            store.append(PutRecord(job=job(1)))
        store.close()
        self.assertEqual((self.dir / LOG_NAME).stat().st_size, 0)

    def test_compaction_keeps_live_jobs_and_the_counter(self) -> None:
        store, _ = Store.open(self.dir)
        for number in (1, 2, 3):
            store.append(PutRecord(job=job(number)))
        store.append(PutRecord(job=job(1, "done")))
        store.append(DeleteRecord(number=3))
        store.close()
        before = replay(self.dir)
        self.assertEqual(compact(self.dir), (5, 3))
        after = replay(self.dir)
        self.assertEqual(after.jobs, before.jobs)
        self.assertEqual(after.next_number, 4)
        self.assertEqual(len((self.dir / LOG_NAME).read_bytes().splitlines()), 3)
        self.assertFalse(any(name.endswith(".compact") for name in os.listdir(self.dir)))

    def test_compaction_refuses_a_directory_in_use(self) -> None:
        store, _ = Store.open(self.dir)
        try:
            with self.assertRaises(StoreOpenError):
                compact(self.dir)
        finally:
            store.close()


def put(number: int = 1, **fields: object) -> str:
    """A put record written by hand, so a state the API can never produce can be tried."""
    job_fields = {
        "number": number,
        "queue": "q",
        "state": "queued",
        "payload": f"payload {number}",
        "tries": 0,
        "max_tries": 3,
        "backoff_ms": 0,
        "created_ms": 1,
        "updated_ms": 1,
    } | fields
    return json.dumps({"kind": "put", "job": job_fields}) + "\n"


class WellFormedRecordTest(StoreCase):
    """A record in a state the API can never produce refuses the folder before it is served."""

    def refusal(self, log: str) -> str:
        (self.dir / LOG_NAME).write_text(log)
        with self.assertRaises(StoreOpenError) as refused:
            Store.open(self.dir)
        return str(refused.exception)

    def test_each_state_refuses_the_folder_naming_the_record_and_the_rule(self) -> None:
        for fields, rule in (
            ({"state": "queued", "tries": 3}, "a queued job has tries below max_tries"),
            ({"state": "queued", "worker": "w1"}, "a queued job has no worker"),
            ({"state": "scheduled", "tries": 1}, "a scheduled job has a run_at"),
            ({"state": "leased", "tries": 1}, "a leased job has a worker"),
            ({"state": "leased", "tries": 0, "worker": "w1", "lease_until_ms": 9},
             "a leased job has 1 to max_tries tries"),
            ({"state": "done", "tries": 0}, "a done job has 1 to max_tries tries"),
            ({"state": "dead", "tries": 0}, "a dead job has 1 to max_tries tries"),
            ({"state": "dead", "tries": 1, "run_at_ms": 9}, "a dead job has no run_at"),
        ):
            message = self.refusal(put(**fields))
            self.assertRegex(message, f"{re.escape(str(self.dir))}: record j_1: {re.escape(rule)}")

    def test_the_first_ill_formed_record_is_the_one_named(self) -> None:
        log = put(1) + put(2, state="done", tries=0) + put(3, state="dead", tries=0)
        self.assertIn("record j_2: a done job has 1 to max_tries tries", self.refusal(log))

    def test_a_torn_ill_formed_last_line_is_cut_off_not_refused(self) -> None:
        (self.dir / LOG_NAME).write_text(put(1) + put(2, state="done", tries=0).rstrip("\n"))
        store, state = Store.open(self.dir)
        store.close()
        self.assertEqual(list(state.jobs), [1])

    def test_the_hand_written_ill_formed_folder_is_refused(self) -> None:
        log = (FIXTURES / "illformed" / LOG_NAME).read_text()
        self.assertIn("record j_2: a leased job has no run_at", self.refusal(log))

    def test_a_well_formed_record_in_every_state_opens(self) -> None:
        log = (
            put(1)
            + put(2, state="scheduled", run_at_ms=9)
            + put(3, state="leased", tries=1, worker="w1", lease_until_ms=9)
            + put(4, state="done", tries=1)
            + put(5, state="dead", tries=3)
        )
        (self.dir / LOG_NAME).write_text(log)
        store, state = Store.open(self.dir)
        store.close()
        self.assertEqual(list(state.jobs), [1, 2, 3, 4, 5])


class WriteRecoveryTest(StoreCase):
    """A store that cannot be written refuses every write and no more: nothing is latched."""

    def test_writes_resume_on_their_own_once_the_store_can_be_written(self) -> None:
        ops = FailingOps()
        store, _ = Store.open(self.dir, ops)
        try:
            store.append(PutRecord(job=job(1)))
            ops.failing = True
            for _ in range(3):
                with self.assertRaises(StoreError):
                    store.append(PutRecord(job=job(2)))
            ops.failing = False
            store.append(PutRecord(job=job(2)))
        finally:
            store.close()
        self.assertEqual(replay(self.dir).jobs, {1: job(1), 2: job(2)})

    def test_a_roll_back_that_failed_is_taken_again_before_the_next_write(self) -> None:
        ops = FailingOps()
        store, _ = Store.open(self.dir, ops)
        try:
            store.append(PutRecord(job=job(1)))
            ops.failing = True
            broken = mock.patch("jobq.store.os.ftruncate", side_effect=OSError(errno.EIO, "no"))
            with broken, self.assertRaises(StoreError):
                store.append(PutRecord(job=job(2)))
            self.assertGreater((self.dir / LOG_NAME).stat().st_size, store.size)
            ops.failing = False
            store.append(PutRecord(job=job(2, "done")))
        finally:
            store.close()
        self.assertEqual(replay(self.dir).jobs, {1: job(1), 2: job(2, "done")})


class OldLogTest(StoreTest):
    """Logs written before the tries rename, by hand in the old shape."""

    def test_a_log_in_the_old_shape_replays_in_the_new_one(self) -> None:
        lease = {"attempts": 1, "worker": "w1", "lease_until_ms": 9}
        (self.dir / LOG_NAME).write_text(
            old_record(1) + old_record(2, "leased", **lease) + '{"kind": "delete", "number": 3}\n'
        )
        store, state = Store.open(self.dir)
        store.close()
        held = {"tries": 1, "worker": "w1", "lease_until_ms": 9}
        leased = job(2, "leased").model_copy(update=held)
        self.assertEqual(state.jobs, {1: job(1), 2: leased})
        self.assertEqual((state.next_number, state.records), (4, 3))

    def test_old_and_new_records_of_one_job_replay_to_the_last(self) -> None:
        (self.dir / LOG_NAME).write_text(old_record(1))
        store, _ = Store.open(self.dir)
        store.append(PutRecord(job=job(1, "done")))
        store.close()
        self.assertEqual(replay(self.dir).jobs, {1: job(1, "done")})

    def test_compacting_an_old_log_leaves_no_old_name(self) -> None:
        (self.dir / LOG_NAME).write_text(
            old_record(1) + old_record(1, "dead", attempts=2, reason="r") + old_record(2)
        )
        before = replay(self.dir)
        self.assertEqual(compact(self.dir), (3, 3))
        log = (self.dir / LOG_NAME).read_bytes()
        self.assertNotIn(b"attempts", log)
        self.assertEqual((log.count(b'"tries":'), log.count(b'"backoff_ms":0')), (2, 2))
        self.assertEqual(replay(self.dir).jobs, before.jobs)

    def test_a_record_with_an_old_name_beside_its_new_one_refuses_to_open(self) -> None:
        (self.dir / LOG_NAME).write_text(old_record(1, tries=0))
        with self.assertRaisesRegex(StoreOpenError, "record j_1: .*not permitted"):
            Store.open(self.dir)


if __name__ == "__main__":
    unittest.main()
