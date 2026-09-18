"""Change 6: the archive pruned, the rename rule's `next_id`, the change-5 folder, and every
error the store declares, each reached by a test here (see `DeclaredErrorTest`)."""

import errno
import io
import json
import os
import shutil
import unittest
from pathlib import Path
from typing import Any
from unittest import mock

from jobq.board import Board, BoardOptions
from jobq.cli import EXIT_FAILURE, EXIT_OK, EXIT_USAGE, parse_serve_flags, run
from jobq.clock import iso_utc
from jobq.contract import ContractError
from jobq.jobs import Job
from jobq.queue import PRUNE_EVERY_MS, prune_step
from jobq.store import (
    ARCHIVE_NAME,
    LOG_NAME,
    ArchivedRecord,
    ArchivePutRecord,
    CounterRecord,
    PruneRecord,
    PutRecord,
    RenameRecord,
    Store,
    StoreError,
    StoreOpenError,
    compact,
    replay,
)
from support import FIXTURES, body_of
from test_archive import RETAIN_MS, ArchiveCase, finished, lines, listed
from test_change5 import crashing
from test_store import StoreCase, job

HOUR_MS = 3_600_000


def archived(number: int, archived_ms: int, queue: str = "q", key: str | None = None) -> Job:
    return finished(number, archived_ms=archived_ms).model_copy(update={"queue": queue, "key": key})


def write(path: Path, *records: object) -> None:
    with open(path, "a", encoding="utf-8") as file:
        for record in records:
            if isinstance(record, str):
                file.write(record)
            else:
                assert hasattr(record, "model_dump_json")
                file.write(record.model_dump_json() + "\n")


def invoke(*argv: str) -> tuple[int, str, str]:
    stdout, stderr = io.StringIO(), io.StringIO()
    code = run(list(argv), stdout, stderr)
    return code, stdout.getvalue(), stderr.getvalue()


class PruneStepTest(unittest.TestCase):
    """The prune as a pure step over the archive and the key map."""

    def setUp(self) -> None:
        self.archive = {
            1: archived(1, 1_000, key="a"),  # well before the cutoff
            2: archived(2, 5_000, key="b"),  # exactly at it
            3: archived(3, 5_001, key="c"),  # one ms after it
            4: archived(4, 9_000),
        }
        self.live = {5: job(5).model_copy(update={"key": "d"})}
        self.keys = {("q", "a"): 1, ("q", "b"): 2, ("q", "c"): 3, ("q", "d"): 5}

    def test_jobs_at_or_before_the_cutoff_go_and_their_keys_are_freed(self) -> None:
        after = prune_step(self.live, self.archive, self.keys, now=15_000, older_than_ms=10_000)
        self.assertEqual([j.number for j in after.removed], [1, 2])
        self.assertEqual(list(after.archived), [3, 4])
        self.assertEqual(after.keys, {("q", "c"): 3, ("q", "d"): 5})

    def test_nothing_older_removes_nothing(self) -> None:
        after = prune_step(self.live, self.archive, self.keys, now=15_000, older_than_ms=HOUR_MS)
        self.assertEqual((after.removed, after.archived, after.keys), ([], self.archive, self.keys))

    def test_the_age_is_at_least_a_second(self) -> None:
        with self.assertRaisesRegex(ContractError, "older_than_ms is at least 1,000"):
            prune_step(self.live, self.archive, self.keys, now=15_000, older_than_ms=999)

    def test_a_live_job_is_never_removed(self) -> None:
        # A board that broke its own rule (a job both live and archived) trips the never.
        live = {1: job(1)}
        with self.assertRaisesRegex(ContractError, "never removes a live job"):
            prune_step(live, self.archive, self.keys, now=15_000, older_than_ms=10_000)


class PruneCase(ArchiveCase):
    def prune(self, older_than_ms: object, token: str | None = "w1") -> tuple[int, Any]:
        response = self.call("POST", "/archive/prune", {"older_than_ms": older_than_ms}, token)
        return response.status, body_of(response)

    def archive_info(self) -> dict[str, Any]:
        response = self.call("GET", "/archive")
        self.assertEqual(response.status, 200)
        return body_of(response)

    def two_ages(self) -> tuple[str, str]:
        """A keyed job archived an hour ago and another archived now; their ids."""
        old = self.keyed("old-key")[1]["id"]
        self.lease_and_ack(str(old))
        self.clock.advance(RETAIN_MS)
        self.health()  # the look that archives it
        self.clock.advance(HOUR_MS)
        young = self.keyed("young-key")[1]["id"]
        self.lease_and_ack(str(young))
        self.clock.advance(RETAIN_MS)
        self.health()
        return str(old), str(young)

    def queue_names(self) -> list[str]:
        queues: list[dict[str, Any]] = json.loads(self.call("GET", "/queues").body)["queues"]
        return [queue["name"] for queue in queues]

    def lease_and_ack(self, job_id: str) -> None:
        leased = body_of(self.call("POST", "/queues/emails/lease"))
        self.assertEqual(leased["id"], job_id)
        self.assertEqual(self.call("POST", f"/jobs/{job_id}/ack").status, 200)


class PruneTest(PruneCase):
    def test_a_prune_removes_the_old_archived_job_and_frees_its_key(self) -> None:
        old, young = self.two_ages()
        self.assertEqual(self.health()["archived"], 2)
        self.assertEqual(self.prune(HOUR_MS // 2), (200, {"pruned": 1, "remaining": 1}))
        self.assertEqual(self.call("GET", f"/jobs/{old}").status, 404)
        self.assertEqual(self.call("GET", f"/jobs/{young}").status, 200)
        self.assertEqual(listed(self.call("GET", "/jobs?queue=emails&key=old-key")), [])
        self.assertEqual(self.health()["archived"], 1)
        self.assertEqual(self.archive_info()["archived"], 1)
        status, again = self.keyed("old-key")
        self.assertEqual((status, again["state"]), (201, "queued"))
        self.assertNotEqual(again["id"], old)
        status, same = self.keyed("young-key")
        self.assertEqual((status, same["id"]), (200, young))

    def test_a_prune_is_one_record_naming_the_cutoff_and_the_count(self) -> None:
        self.two_ages()
        self.keyed("third")
        self.lease_and_ack("j_3")
        self.clock.advance(RETAIN_MS)
        self.health()
        self.clock.advance(1_000)
        before = lines(self.dir / LOG_NAME)
        archive = (self.dir / ARCHIVE_NAME).read_bytes()
        now = self.clock.now_ms()
        self.assertEqual(self.prune(1_000), (200, {"pruned": 3, "remaining": 0}))
        after = lines(self.dir / LOG_NAME)
        self.assertEqual(after[: len(before)], before)
        self.assertEqual(
            after[len(before) :], [{"kind": "prune", "cutoff_ms": now - 1_000, "count": 3}]
        )
        self.assertEqual((self.dir / ARCHIVE_NAME).read_bytes(), archive)
        self.assertEqual(replay(self.dir).archived, {})

    def test_a_prune_that_removes_nothing_writes_nothing(self) -> None:
        self.two_ages()
        size = self.queue.store.size
        self.assertEqual(self.prune(10 * HOUR_MS), (200, {"pruned": 0, "remaining": 2}))
        self.assertEqual(self.queue.store.size, size)

    def test_a_live_job_is_never_pruned_whatever_its_age(self) -> None:
        queued = self.create(queue="other")
        self.finish()  # done, but on the board until RETAIN_MS passes
        self.clock.advance(RETAIN_MS - 1)
        self.assertEqual(self.prune(1_000), (200, {"pruned": 0, "remaining": 0}))
        self.assertEqual(body_of(self.call("GET", f"/jobs/{queued}"))["state"], "queued")
        health = self.health()
        self.assertEqual((health["queued"], health["done"]), (1, 1))

    def test_a_younger_archived_job_is_kept_to_the_millisecond(self) -> None:
        self.finish()
        self.clock.advance(RETAIN_MS)
        self.health()  # archived now
        self.clock.advance(4_999)
        self.assertEqual(self.prune(5_000), (200, {"pruned": 0, "remaining": 1}))
        self.clock.advance(1)
        self.assertEqual(self.prune(5_000), (200, {"pruned": 1, "remaining": 0}))

    def test_the_body_is_checked(self) -> None:
        for bad in (999, 0, -1, 1000.0, "5000", True, None):
            self.assertEqual(self.prune(bad)[0], 400, bad)
        extra = self.call("POST", "/archive/prune", {"older_than_ms": 5_000, "x": 1})
        self.assertEqual(extra.status, 400)
        self.assertEqual(self.call("POST", "/archive/prune", raw=b"").status, 400)
        self.assertEqual(self.call("POST", "/archive/prune", raw=b"{").status, 400)
        self.assertEqual(self.prune(5_000, token=None)[0], 401)
        self.assertEqual(self.call("GET", "/archive/prune").status, 405)
        self.assertEqual(self.call("POST", "/archive").status, 405)
        self.assertEqual(self.call("GET", "/archive", token=None).status, 401)

    def test_the_archive_route_shows_the_count_the_oldest_and_the_bytes(self) -> None:
        self.assertEqual(
            self.archive_info(), {"archived": 0, "oldest_archived_at": None, "bytes": 0}
        )
        self.finish()
        self.clock.advance(RETAIN_MS)
        first = self.clock.now_ms()
        self.health()
        self.clock.advance(RETAIN_MS)
        self.finish()
        self.clock.advance(RETAIN_MS)
        info = self.archive_info()
        self.assertEqual(info["archived"], 2)
        self.assertEqual(info["oldest_archived_at"], iso_utc(first))
        self.assertEqual(info["bytes"], (self.dir / ARCHIVE_NAME).stat().st_size)

    def test_a_pruned_job_never_comes_back_across_a_restart(self) -> None:
        old, young = self.two_ages()
        self.prune(HOUR_MS // 2)
        count = self.health()["archived"]
        self.restart()
        self.assertEqual(self.call("GET", f"/jobs/{old}").status, 404)
        self.assertEqual(self.call("GET", f"/jobs/{young}").status, 200)
        self.assertEqual(self.health()["archived"], count)
        self.assertEqual(self.keyed("old-key")[0], 201)
        self.assertEqual(replay(self.dir).archived, self.queue.archived_snapshot())

    def test_a_pruned_job_never_comes_back_across_a_compaction(self) -> None:
        old, young = self.two_ages()
        self.prune(HOUR_MS // 2)
        self.api.close()
        compact(self.dir)
        log = lines(self.dir / LOG_NAME)
        self.assertEqual(log[0], {"kind": "counter", "next_number": 3, "prunes": 1})
        self.assertFalse(any(line["kind"] == "prune" for line in log))
        self.assertEqual([line["job"]["number"] for line in lines(self.dir / ARCHIVE_NAME)], [2])
        self.api = self.open()
        self.assertEqual(self.call("GET", f"/jobs/{old}").status, 404)
        self.assertEqual(self.call("GET", f"/jobs/{young}").status, 200)
        self.assertEqual(self.health()["archived"], 1)
        # The count carries on, so a job archived after the compaction is not taken by a
        # prune record the next compaction folds.
        self.assertEqual(self.keyed("old-key")[0], 201)

    def test_a_failed_prune_write_removes_nothing(self) -> None:
        old, _ = self.two_ages()
        self.ops.failing = True
        status, shown = self.prune(HOUR_MS // 2)
        self.ops.failing = False
        self.assertEqual(status, 503)
        self.assertIn("store unavailable", shown["error"])
        self.assertEqual(self.call("GET", f"/jobs/{old}").status, 200)
        self.assertEqual(self.keyed("old-key")[0], 200)
        self.restart()
        self.assertEqual(self.call("GET", f"/jobs/{old}").status, 200)

    def test_a_kill_after_the_record_leaves_the_prune_made(self) -> None:
        old, _ = self.two_ages()
        with crashing():
            self.assertEqual(self.prune(HOUR_MS // 2)[0], 503)
        self.assertEqual(self.api.restarts, 1)
        self.assertEqual(self.call("GET", f"/jobs/{old}").status, 404)
        self.assertEqual(self.health()["archived"], 1)

    def test_a_kill_mid_record_leaves_the_prune_unmade(self) -> None:
        old, _ = self.two_ages()
        self.api.close()
        now = self.clock.now_ms()
        whole = PruneRecord(cutoff_ms=now - HOUR_MS // 2, count=1).model_dump_json() + "\n"
        for torn in range(1, len(whole)):  # every length short of the whole line
            with self.subTest(torn=torn):
                size = (self.dir / LOG_NAME).stat().st_size
                write(self.dir / LOG_NAME, whole[:torn])
                state = replay(self.dir)
                self.assertIn(int(old[2:]), state.archived)
                store, _ = Store.open(self.dir)  # the open cuts the torn line
                store.close()
                self.assertEqual((self.dir / LOG_NAME).stat().st_size, size)
        write(self.dir / LOG_NAME, whole)
        self.assertNotIn(int(old[2:]), replay(self.dir).archived)
        self.api = self.open()

    def test_unmarked_archived_jobs_are_marked_in_the_prune_write(self) -> None:
        """A job whose `archived` mark failed to write is marked before the prune record,
        so no live record of it is left to come back."""
        self.finish()
        self.clock.advance(RETAIN_MS)
        real_write = self.ops.write

        def fail_the_marker(fd: int, data: bytes) -> int:
            if data.startswith(b'{"kind":"archived"'):
                raise OSError(errno.EIO, "injected")
            return real_write(fd, data)

        self.ops.write = fail_the_marker  # type: ignore[method-assign]
        self.health()
        self.ops.write = real_write  # type: ignore[method-assign]
        self.assertNotIn({"kind": "archived", "number": 1}, lines(self.dir / LOG_NAME))
        self.clock.advance(1_000)
        self.assertEqual(self.prune(1_000), (200, {"pruned": 1, "remaining": 0}))
        tail = lines(self.dir / LOG_NAME)[-2:]
        self.assertEqual(tail[0], {"kind": "archived", "number": 1})
        self.assertEqual(tail[1]["kind"], "prune")
        self.restart()
        self.assertEqual(self.call("GET", "/jobs/j_1").status, 404)
        self.assertEqual(self.health()["done"], 0)


class BackgroundPruneTest(PruneCase):
    """`--retention`: the idle look prunes with that age once a minute, on a fixture clock."""

    AGE_MS = 5_000

    def open(self, ops: object = None, options: BoardOptions | None = None) -> Board:
        chosen = options or BoardOptions(retain_ms=RETAIN_MS, retention_ms=self.AGE_MS)
        return Board(self.dir, self.clock, self.ops, chosen)

    def test_the_idle_look_prunes_every_minute(self) -> None:
        self.api.expire_due()  # the first look prunes (nothing) and sets the next for a minute on
        self.finish()
        self.clock.advance(RETAIN_MS)
        self.health()
        self.clock.advance(self.AGE_MS)
        size = self.queue.store.size
        self.api.expire_due()
        self.assertEqual((self.health()["archived"], self.queue.store.size), (1, size))
        self.clock.advance(PRUNE_EVERY_MS - RETAIN_MS - self.AGE_MS - 1)
        self.api.expire_due()
        self.assertEqual(self.health()["archived"], 1)
        self.clock.advance(1)
        self.api.expire_due()
        self.assertEqual(self.health()["archived"], 0)
        self.assertEqual(lines(self.dir / LOG_NAME)[-1]["kind"], "prune")
        self.assertEqual(lines(self.dir / LOG_NAME)[-1]["count"], 1)

    def test_a_background_prune_that_removes_nothing_writes_nothing(self) -> None:
        self.create()  # a live job, however old, is not the prune's
        size = self.queue.store.size
        for _ in range(3):
            self.clock.advance(PRUNE_EVERY_MS)
            self.api.expire_due()
        self.assertEqual(self.health()["queued"], 1)
        self.assertEqual(self.queue.store.size, size)

    def test_the_first_look_after_a_start_prunes(self) -> None:
        self.finish()
        self.clock.advance(RETAIN_MS)
        self.health()
        self.api.close()
        self.clock.advance(HOUR_MS)
        self.api = self.open()
        self.api.expire_due()
        self.assertEqual(self.health()["archived"], 0)

    def test_without_retention_nothing_is_pruned_in_the_background(self) -> None:
        self.api.close()
        self.api = self.open(options=BoardOptions(retain_ms=RETAIN_MS))
        self.finish()
        self.clock.advance(RETAIN_MS)
        self.health()
        self.clock.advance(10 * HOUR_MS)
        self.api.expire_due()
        self.assertEqual(self.health()["archived"], 1)


class RetentionFlagTest(unittest.TestCase):
    def test_retention_is_0_or_at_least_a_second(self) -> None:
        self.assertEqual(parse_serve_flags([])[1].retention_ms, 0)
        self.assertEqual(parse_serve_flags(["--retention", "0"])[1].retention_ms, 0)
        self.assertEqual(parse_serve_flags(["--retention", "1000"])[1].retention_ms, 1000)
        for bad in ("999", "1", "-5", "1e4", "", "x", "12345678901234"):
            code, _, err = invoke("serve", "/nonexistent", "--retention", bad)
            self.assertEqual(code, EXIT_USAGE, bad)
            self.assertIn("--retention", err)


class OfflinePruneTest(PruneCase):
    def test_jobq_prune_removes_and_prints_the_two_counts(self) -> None:
        self.finish()
        self.clock.advance(RETAIN_MS)
        self.health()
        self.api.close()
        code, out, _ = invoke("prune", str(self.dir), "--older-than-ms", "1000")
        self.assertEqual(code, EXIT_OK)
        self.assertEqual(out, f"jobq: pruned {self.dir}: pruned 1, remaining 0\n")
        self.assertEqual(lines(self.dir / LOG_NAME)[-1]["kind"], "prune")
        size = (self.dir / LOG_NAME).stat().st_size
        code, out, _ = invoke("prune", str(self.dir), "--older-than-ms", "1000")
        self.assertEqual(out, f"jobq: pruned {self.dir}: pruned 0, remaining 0\n")
        self.assertEqual((self.dir / LOG_NAME).stat().st_size, size)
        code, out, _ = invoke("verify", str(self.dir))
        self.assertEqual(code, EXIT_OK)
        self.assertIn("archived 0", out)
        self.api = self.open()

    def test_it_refuses_a_bad_age_a_missing_folder_and_a_folder_in_use(self) -> None:
        for bad in ("999", "x", "-1000"):
            self.assertEqual(invoke("prune", str(self.dir), "--older-than-ms", bad)[0], EXIT_USAGE)
        self.assertEqual(invoke("prune", str(self.dir))[0], EXIT_USAGE)
        code, _, err = invoke("prune", str(self.dir), "--older-than-ms", "1000")
        self.assertEqual(code, EXIT_FAILURE)
        self.assertIn("in use by another jobq", err)
        code, _, err = invoke("prune", str(self.dir / "missing"), "--older-than-ms", "1000")
        self.assertEqual(code, EXIT_FAILURE)


class PruneReplayTest(StoreCase):
    """The prune record in order with the archive: what it takes, and what it does not."""

    def test_an_archive_record_written_after_the_prune_is_not_taken(self) -> None:
        write(
            self.dir / LOG_NAME,
            CounterRecord(next_number=4),
            PruneRecord(cutoff_ms=100, count=1),
        )
        write(
            self.dir / ARCHIVE_NAME,
            ArchivePutRecord(job=archived(1, 50)),  # before the prune, older: gone
            ArchivePutRecord(job=archived(2, 150)),  # before the prune, younger: kept
            # after the prune, older by a clock that went back: kept
            ArchivePutRecord(job=archived(3, 50), prunes=1),
        )
        state = replay(self.dir)
        self.assertEqual(list(state.archived), [2, 3])
        self.assertEqual((state.prunes, state.next_number), (1, 4))

    def test_a_stale_live_record_of_a_pruned_job_stays_gone(self) -> None:
        write(
            self.dir / LOG_NAME,
            PutRecord(job=finished(1)),  # its `archived` mark never written
            PruneRecord(cutoff_ms=100, count=1),
        )
        write(self.dir / ARCHIVE_NAME, ArchivePutRecord(job=archived(1, 50)))
        state = replay(self.dir)
        self.assertEqual((state.jobs, state.archived), ({}, {}))

    def test_two_prunes_each_take_their_own(self) -> None:
        write(
            self.dir / LOG_NAME,
            PruneRecord(cutoff_ms=100, count=1),
            PruneRecord(cutoff_ms=200, count=1),
        )
        write(
            self.dir / ARCHIVE_NAME,
            ArchivePutRecord(job=archived(1, 50)),
            ArchivePutRecord(job=archived(2, 150), prunes=1),
            ArchivePutRecord(job=archived(3, 250), prunes=1),
        )
        state = replay(self.dir)
        self.assertEqual(list(state.archived), [3])
        self.assertEqual(state.pruned, {1: 1, 2: 1})

    def test_a_compaction_cut_short_after_the_archive_opens(self) -> None:
        """A kill between the archive's rename and the log's: the archive holds no pruned
        job, and the old log's prune record takes fewer than it says, which is allowed."""
        write(
            self.dir / LOG_NAME,
            PutRecord(job=finished(1)),
            ArchivedRecord(number=1),
            PutRecord(job=finished(2)),
            ArchivedRecord(number=2),
            PruneRecord(cutoff_ms=100, count=1),
        )
        write(self.dir / ARCHIVE_NAME, ArchivePutRecord(job=archived(2, 150), prunes=1))
        state = replay(self.dir)
        self.assertEqual((list(state.archived), state.jobs), ([2], {}))


class CompactionKillTest(PruneCase):
    """Persistence named twice: a compaction killed after a file's rename and before the
    directory's fsync, and between the two renames, leaves a folder that opens to the same
    state."""

    def a_folder_with_everything(self) -> None:
        self.two_ages()
        self.prune(HOUR_MS // 2)
        self.create(queue="other")
        self.assertEqual(self.call("POST", "/queues/emails/rename", {"to": "mail"}).status, 200)
        self.create(queue="emails")
        self.api.close()

    def test_a_kill_at_each_point_of_the_compaction(self) -> None:
        self.a_folder_with_everything()
        before = replay(self.dir)
        saved = self.dir.parent / (self.dir.name + "-saved")
        shutil.copytree(self.dir, saved)
        self.addCleanup(shutil.rmtree, saved)
        real_rename, real_fsync = os.rename, os.fsync

        class Killed(BaseException):
            pass

        renamed: list[str] = []

        def rename(src: Any, dst: Any, **kw: Any) -> None:
            real_rename(src, dst, **kw)
            renamed.append(str(dst))

        points = [("after the archive rename", ARCHIVE_NAME), ("after the log rename", LOG_NAME)]
        for label, target in points:
            with self.subTest(label):
                shutil.rmtree(self.dir)
                shutil.copytree(saved, self.dir)
                renamed.clear()

                def fsync(fd: int, target: str = target) -> None:
                    if renamed and renamed[-1] == target and os.path.isdir(f"/proc/self/fd/{fd}"):
                        raise Killed  # the directory's fsync never runs
                    real_fsync(fd)

                with (
                    mock.patch("jobq.store.os.rename", rename),
                    mock.patch("jobq.store.os.fsync", fsync),
                    self.assertRaises(Killed),
                ):
                    compact(self.dir)
                for leftover in ("jobs.log.compact", "jobq.archive.compact"):
                    self.assertFalse((self.dir / leftover).exists())
                after = replay(self.dir)
                self.assertEqual(after.jobs, before.jobs)
                self.assertEqual(after.archived, before.archived)
                self.assertEqual(after.next_number, before.next_number)
                self.assertEqual(invoke("verify", str(self.dir))[0], EXIT_OK)
                compact(self.dir)
                self.assertEqual(replay(self.dir).archived, before.archived)
        self.api = self.open()


class RenameNextIdTest(PruneCase):
    """The corrected rename rule: a rename carries `next_id`; a job created into the old name
    after it is in a fresh queue, archived or not, restart or compaction."""

    def test_a_job_created_into_the_old_name_after_the_rename_and_archived_later(self) -> None:
        self.finish()  # j_1 in emails, done
        self.assertEqual(self.call("POST", "/queues/emails/rename", {"to": "mail"}).status, 200)
        self.assertEqual(lines(self.dir / LOG_NAME)[-1]["next_id"], 2)
        fresh = self.finish()  # j_2 in a fresh emails
        self.clock.advance(RETAIN_MS)
        self.assertEqual(self.health()["archived"], 2)
        for reopen in ("restart", "compact"):
            if reopen == "compact":
                self.api.close()
                compact(self.dir)
                self.api = self.open()
            else:
                self.restart()
            self.assertEqual(body_of(self.call("GET", "/jobs/j_1"))["queue"], "mail", reopen)
            self.assertEqual(body_of(self.call("GET", f"/jobs/{fresh}"))["queue"], "emails", reopen)

    def test_next_id_bounds_the_rename_at_replay(self) -> None:
        write(
            self.dir / LOG_NAME,
            PutRecord(job=job(1).model_copy(update={"queue": "a"})),
            RenameRecord(name="a", to="b", next_id=2),
            PutRecord(job=job(2).model_copy(update={"queue": "a"})),
        )
        write(
            self.dir / ARCHIVE_NAME,
            # written before the rename by its count, but created after it by its number
            ArchivePutRecord(job=archived(3, 50, queue="a")),
            ArchivePutRecord(job=archived(4, 50, queue="a")),
        )
        # j_3 and j_4 are numbered past next_id: the rename never moves them.
        state = replay(self.dir)
        self.assertEqual(state.jobs[1].queue, "b")
        self.assertEqual(state.jobs[2].queue, "a")
        self.assertEqual([j.queue for j in state.archived.values()], ["a", "a"])

    def test_a_rename_after_the_archive_write_does_not_move_it_twice(self) -> None:
        """c is renamed into a after a was renamed away: a job archived from c after both
        renames is in a, not moved on by the first rename."""
        write(
            self.dir / LOG_NAME,
            PutRecord(job=job(1).model_copy(update={"queue": "a"})),
            PutRecord(job=job(2).model_copy(update={"queue": "c"})),
            RenameRecord(name="a", to="b", next_id=3),
            RenameRecord(name="c", to="a", next_id=3),
        )
        write(self.dir / ARCHIVE_NAME, ArchivePutRecord(job=archived(2, 50, queue="a"), renames=2))
        state = replay(self.dir)
        self.assertEqual(state.archived[2].queue, "a")

    def test_a_change_5_rename_without_next_id_is_read(self) -> None:
        write(
            self.dir / LOG_NAME,
            PutRecord(job=job(1).model_copy(update={"queue": "a"})),
            '{"kind":"rename","name":"a","to":"b"}\n',
            PutRecord(job=job(2).model_copy(update={"queue": "a"})),
        )
        state = replay(self.dir)
        self.assertEqual({n: j.queue for n, j in state.jobs.items()}, {1: "b", 2: "a"})


class Change5FolderTest(PruneCase):
    """The folder the change-5 program wrote (`tests/fixtures/change5`): two compacted
    archived jobs, a rename record without `next_id`, a job created into the old name after
    it, and a job archived after it."""

    def setUp(self) -> None:
        super().setUp()
        self.api.close()
        for name in (LOG_NAME, ARCHIVE_NAME):
            shutil.copy(FIXTURES / "change5" / name, self.dir / name)
        self.clock.ms = 1_789_721_700_000  # a minute after the fixture was written
        self.api = self.open()

    def test_it_opens_with_every_job_in_its_queue(self) -> None:
        self.assertEqual(self.queue_names(), ["old-a", "old-b"])
        self.assertEqual(self.health()["archived"], 3)
        for number in (1, 2, 3):
            self.assertEqual(body_of(self.call("GET", f"/jobs/j_{number}"))["queue"], "old-c")
        self.assertEqual(body_of(self.call("GET", "/jobs/j_6"))["queue"], "old-a")
        self.assertEqual(self.keyed("k1", queue="old-a")[1]["id"], "j_6")
        self.assertEqual(self.keyed("k2", queue="old-c")[1]["id"], "j_2")
        self.assertEqual(self.keyed("k2", queue="old-a")[0], 201)

    def test_it_prunes_renames_compacts_and_reopens(self) -> None:
        self.assertEqual(self.prune(1_000), (200, {"pruned": 3, "remaining": 0}))
        self.assertEqual(self.keyed("k3", queue="old-c")[0], 201)
        self.assertEqual(self.call("POST", "/queues/old-a/rename", {"to": "new-a"}).status, 200)
        self.api.close()
        self.assertEqual(invoke("verify", str(self.dir))[0], EXIT_OK)
        compact(self.dir)
        self.api = self.open()
        self.assertEqual(self.queue_names(), ["new-a", "old-b", "old-c"])
        self.assertEqual(self.health()["archived"], 0)

    def test_the_generation_five_sequence_opens(self) -> None:
        """Compact, one more rename, a stop: the folder is never refused at open."""
        self.api.close()
        compact(self.dir)
        self.api = self.open()
        self.assertEqual(self.call("POST", "/queues/old-b/rename", {"to": "new-b"}).status, 200)
        self.finish()
        self.clock.advance(RETAIN_MS)
        self.health()
        self.api.close()
        code, _, err = invoke("verify", str(self.dir))
        self.assertEqual(code, EXIT_OK, err)
        self.api = self.open()
        self.assertEqual(body_of(self.call("GET", "/jobs/j_4"))["queue"], "new-b")


class DeclaredErrorTest(StoreCase):
    """Every error the store declares, each reached. The names are the report's list."""

    def refused(self, *records: object, archive: tuple[object, ...] = ()) -> str:
        write(self.dir / LOG_NAME, *records)
        if archive:
            write(self.dir / ARCHIVE_NAME, *archive)
        with self.assertRaises(StoreOpenError) as raised:
            Store.open(self.dir)
        code, _, err = invoke("verify", str(self.dir))
        self.assertEqual(code, EXIT_FAILURE)
        self.assertIn(str(raised.exception), err)
        return str(raised.exception)

    def test_a_missing_folder(self) -> None:
        with self.assertRaisesRegex(StoreOpenError, "No such file or directory"):
            Store.open(self.dir / "missing")

    def test_a_folder_in_use(self) -> None:
        store, _ = Store.open(self.dir)
        try:
            with self.assertRaisesRegex(StoreOpenError, "in use by another jobq"):
                Store.open(self.dir)
        finally:
            store.close()

    def test_a_bad_record(self) -> None:
        self.assertIn("line 1", self.refused("not json\n"))

    def test_a_record_breaking_a_job_rule(self) -> None:
        self.assertIn("record j_1", self.refused(PutRecord(job=finished(1, archived_ms=5))))

    def test_a_bad_archive_record(self) -> None:
        message = self.refused(archive=(ArchivePutRecord(job=finished(1)),))
        self.assertIn("archive record j_1: an archived job has an archived_at", message)

    def test_a_rename_record_with_a_bad_name(self) -> None:
        message = self.refused('{"kind":"rename","name":"a b","to":"c","next_id":1}\n')
        self.assertIn("record line 1: rename.name value error, queue must be", message)

    def test_a_rename_record_to_its_own_name(self) -> None:
        message = self.refused(RenameRecord(name="a", to="a", next_id=1))
        self.assertIn("a rename of a to itself", message)

    def test_a_rename_record_with_next_id_past_the_counter(self) -> None:
        message = self.refused(RenameRecord(name="a", to="b", next_id=7))
        self.assertIn("next_id 7 is past the counter 1", message)

    def test_a_rename_record_with_a_bad_next_id(self) -> None:
        message = self.refused('{"kind":"rename","name":"a","to":"b","next_id":0}\n')
        self.assertIn("next_id", message)

    def test_an_archive_record_past_the_logs_renames(self) -> None:
        message = self.refused(archive=(ArchivePutRecord(job=archived(1, 5), renames=1),))
        self.assertIn("renames 1 is past the log's 0", message)

    def test_a_prune_record_with_a_bad_cutoff(self) -> None:
        for bad in ('"cutoff_ms":-1', '"cutoff_ms":1.5', '"cutoff_ms":"9"'):
            with self.subTest(bad):
                (self.dir / LOG_NAME).unlink(missing_ok=True)
                message = self.refused(f'{{"kind":"prune",{bad},"count":1}}\n')
                self.assertIn("record line 1: prune.cutoff_ms", message)

    def test_a_prune_record_with_a_bad_count(self) -> None:
        message = self.refused('{"kind":"prune","cutoff_ms":5,"count":0}\n')
        self.assertIn("record line 1: prune.count", message)

    def test_a_prune_record_taking_more_than_its_count(self) -> None:
        message = self.refused(
            PruneRecord(cutoff_ms=100, count=1),
            archive=(ArchivePutRecord(job=archived(1, 5)), ArchivePutRecord(job=archived(2, 6))),
        )
        self.assertIn("record line 1: a prune at cutoff 100 takes 2 archived jobs", message)

    def test_an_archive_record_past_the_logs_prunes(self) -> None:
        message = self.refused(archive=(ArchivePutRecord(job=archived(1, 5), prunes=1),))
        self.assertIn("prunes 1 is past the log's 0", message)

    def test_a_key_clash(self) -> None:
        message = self.refused(
            PutRecord(job=job(1).model_copy(update={"key": "k"})),
            PutRecord(job=job(2).model_copy(update={"key": "k"})),
        )
        self.assertIn("key 'k' also names j_1", message)

    def test_a_full_disk(self) -> None:
        class FullDisk:
            def write(self, fd: int, data: bytes) -> int:
                raise OSError(errno.ENOSPC, os.strerror(errno.ENOSPC))

            def fsync(self, fd: int) -> None:
                os.fsync(fd)

        store, _ = Store.open(self.dir, FullDisk())
        try:
            with self.assertRaisesRegex(StoreError, "No space left on device"):
                store.append(PruneRecord(cutoff_ms=1, count=1))
        finally:
            store.close()
        self.assertEqual((self.dir / LOG_NAME).stat().st_size, 0)

    def test_a_write_that_fails(self) -> None:
        class FailingFsync:
            def write(self, fd: int, data: bytes) -> int:
                return os.write(fd, data)

            def fsync(self, fd: int) -> None:
                raise OSError(errno.EIO, os.strerror(errno.EIO))

        store, _ = Store.open(self.dir, FailingFsync())
        try:
            with self.assertRaisesRegex(StoreError, "Input/output error"):
                store.append_archive([ArchivePutRecord(job=archived(1, 5))])
        finally:
            store.close()
        self.assertEqual((self.dir / ARCHIVE_NAME).stat().st_size, 0)

    def test_a_compaction_that_cannot_write(self) -> None:
        write(self.dir / LOG_NAME, PutRecord(job=job(1)))
        with (
            mock.patch("jobq.store.os.write", side_effect=OSError(errno.EIO, "Input/output error")),
            self.assertRaisesRegex(StoreOpenError, "compacting"),
        ):
            compact(self.dir)
        self.assertEqual(replay(self.dir).jobs, {1: job(1)})


class BenchFlagTest(unittest.TestCase):
    def test_bench_flags_are_checked(self) -> None:
        for bad in (
            ["--jobs", "7"],
            ["--jobs", "x"],
            ["--workers", "0"],
            ["--workers"],
            ["--bogus", "1"],
            ["--jobs", "10", "--jobs", "10"],
        ):
            self.assertEqual(invoke("bench", str(FIXTURES), *bad)[0], EXIT_USAGE, bad)
        code, _, err = invoke("bench", "/nonexistent-jobq-dir")
        self.assertEqual(
            (code, err), (EXIT_FAILURE, "jobq: /nonexistent-jobq-dir: no such directory\n")
        )


class BenchErrorTest(StoreCase):
    def test_a_service_that_does_not_start_fails_the_bench(self) -> None:
        source = self.dir / "src"
        (source / "jobq").mkdir(parents=True)
        (source / "jobq" / "__init__.py").write_text("")
        (source / "jobq" / "__main__.py").write_text("import sys\nsys.exit('no service')\n")
        (self.dir / "data").mkdir()
        code, _, err = invoke("bench", str(self.dir / "data"), "--serve-src", str(source))
        self.assertEqual(code, EXIT_FAILURE)
        self.assertEqual(err, "jobq: bench failed: the service did not start: 'no service'\n")


class BenchRunTest(StoreCase):
    """A small `jobq bench` end to end: a line per number, and the folder reopens."""

    def test_a_small_bench_prints_every_number(self) -> None:
        code, out, err = invoke("bench", str(self.dir), "--jobs", "80", "--workers", "4")
        self.assertEqual(code, EXIT_OK, err)
        heads = [line.split(":")[0] for line in out.splitlines()]
        self.assertEqual(
            heads,
            [
                "creates",
                "pairs, 1 workers",
                "pairs, 4 workers",
                "rss after pairs",
                "restart with a 0 MB folder",
            ],
        )
        self.assertEqual(invoke("verify", str(self.dir))[0], EXIT_OK)


if __name__ == "__main__":
    unittest.main()
