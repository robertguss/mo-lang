import random
import tempfile
import unittest
from pathlib import Path

from jobq.fs import Faults, MemoryFile, MemoryFs, OsFs
from jobq.model import Job, JobState
from jobq.store import (
    CounterRecord,
    DeleteRecord,
    PutRecord,
    Record,
    Store,
    StoreCorrupt,
    StoreUnavailable,
    decode,
    encode,
)
from tests.support import LOG, SIM_DIR, START_MS

JOB = Job(
    id="j_1",
    queue="emails",
    state=JobState.QUEUED,
    payload="hello\nworld",
    attempts=0,
    max_attempts=3,
    created_at=START_MS,
    updated_at=START_MS,
)


def replayed(store: Store) -> list[Record]:
    records: list[Record] = []
    store.open(records.append)
    return records


class LineFormatTest(unittest.TestCase):
    def test_every_record_kind_round_trips(self) -> None:
        for record in (PutRecord(job=JOB), DeleteRecord(id="j_1"), CounterRecord(next_id=9)):
            with self.subTest(kind=record.kind):
                self.assertEqual(decode(encode(record)), record)

    def test_a_line_is_crc_space_json_newline(self) -> None:
        line = encode(DeleteRecord(id="j_1"))
        self.assertRegex(line.decode(), r"^[0-9a-f]{8} \{.*\}\n$")

    def test_a_damaged_or_torn_line_is_none(self) -> None:
        line = encode(PutRecord(job=JOB))
        self.assertIsNone(decode(line[:-1]))
        self.assertIsNone(decode(line[:20]))
        self.assertIsNone(decode(line.replace(b"hello", b"jello")))
        self.assertIsNone(decode(b"zzzzzzzz {}\n"))

    def test_a_whole_line_that_breaks_the_schema_is_corrupt(self) -> None:
        body = b'{"kind": "put", "job": {"id": "j_1"}}'
        import zlib

        with self.assertRaises(StoreCorrupt):
            decode(b"%08x %s\n" % (zlib.crc32(body), body))


class ReplayTest(unittest.TestCase):
    def test_records_replay_in_order(self) -> None:
        fs = MemoryFs()
        store = Store(fs, SIM_DIR)
        self.assertEqual(replayed(store), [])
        store.append([PutRecord(job=JOB)])
        store.append([CounterRecord(next_id=5), DeleteRecord(id="j_1")])
        self.assertEqual(len(replayed(Store(fs, SIM_DIR))), 3)

    def test_a_torn_last_line_is_cut_off(self) -> None:
        good = encode(PutRecord(job=JOB))
        torn = encode(DeleteRecord(id="j_1"))[:15]
        fs = MemoryFs()
        fs.files[LOG] = MemoryFile(bytearray(good + torn), good + torn)
        store = Store(fs, SIM_DIR)
        self.assertEqual(len(replayed(store)), 1)
        self.assertEqual(fs.files[LOG].durable, good)
        store.append([CounterRecord(next_id=2)])
        self.assertEqual(len(replayed(Store(fs, SIM_DIR))), 2)

    def test_a_damaged_line_before_the_last_is_corrupt(self) -> None:
        good = encode(PutRecord(job=JOB))
        damaged = good.replace(b"hello", b"jello")
        fs = MemoryFs()
        fs.files[LOG] = MemoryFile(bytearray(damaged + good), damaged + good)
        with self.assertRaises(StoreCorrupt):
            replayed(Store(fs, SIM_DIR))


class FailedWriteTest(unittest.TestCase):
    def test_a_failed_append_is_unavailable_and_leaves_the_log_as_it_was(self) -> None:
        faults = Faults(random.Random(1))
        fs = MemoryFs(faults)
        store = Store(fs, SIM_DIR)
        replayed(store)
        store.append([PutRecord(job=JOB)])
        before = fs.files[LOG].durable
        for seed in range(50):
            faults.rng.seed(seed)
            faults.rate = 1.0
            with self.assertRaises(StoreUnavailable):
                store.append([CounterRecord(next_id=seed + 2)])
            faults.rate = 0.0
            self.assertFalse(store.clean and fs.files[LOG].content != before)
        store.append([CounterRecord(next_id=99)])
        self.assertTrue(store.clean)
        self.assertEqual(fs.files[LOG].durable, before + encode(CounterRecord(next_id=99)))
        self.assertEqual(store.synced, store.written)


class CompactTest(unittest.TestCase):
    def test_compaction_replaces_the_log_atomically(self) -> None:
        fs = MemoryFs()
        store = Store(fs, SIM_DIR)
        replayed(store)
        for _ in range(10):
            store.append([PutRecord(job=JOB)])
        store.compact([CounterRecord(next_id=2), PutRecord(job=JOB)])
        self.assertEqual(len(replayed(Store(fs, SIM_DIR))), 2)


class OsFsTest(unittest.TestCase):
    def test_append_replay_and_compact_on_a_real_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            store = Store(OsFs(), Path(tmp))
            self.assertEqual(replayed(store), [])
            store.append([PutRecord(job=JOB), CounterRecord(next_id=3)])
            store.close()
            store = Store(OsFs(), Path(tmp))
            self.assertEqual(len(replayed(store)), 2)
            store.compact([CounterRecord(next_id=3)])
            self.assertEqual(replayed(Store(OsFs(), Path(tmp))), [CounterRecord(next_id=3)])
            self.assertEqual(sorted(p.name for p in Path(tmp).iterdir()), ["jobs.log"])

    def test_a_torn_tail_on_disk_is_truncated(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp, "jobs.log")
            good = encode(PutRecord(job=JOB))
            log.write_bytes(good + b"0000")
            store = Store(OsFs(), Path(tmp))
            self.assertEqual(len(replayed(store)), 1)
            store.close()
            self.assertEqual(log.read_bytes(), good)


if __name__ == "__main__":
    unittest.main()
