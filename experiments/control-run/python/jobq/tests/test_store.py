import errno
import os
import tempfile
import unittest
from pathlib import Path

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
from support import FailingOps


def job(number: int, state: str = "queued") -> Job:
    return Job.model_validate(
        {
            "number": number,
            "queue": "q",
            "state": state,
            "payload": f"payload {number}",
            "attempts": 0,
            "max_attempts": 2,
            "created_ms": 1,
            "updated_ms": 1,
        }
    )


class StoreTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

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
        with self.assertRaisesRegex(StoreOpenError, "line 1 is not a record"):
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


if __name__ == "__main__":
    unittest.main()
