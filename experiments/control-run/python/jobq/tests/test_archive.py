"""Change 4: idempotent creates by key, and done or dead jobs archived out of the log."""

import contextlib
import errno
import io
import json
import os
import unittest
from typing import Any
from unittest import mock

from jobq.api import Response
from jobq.board import Board, BoardOptions
from jobq.cli import EXIT_FAILURE, EXIT_OK, UsageError, parse_serve_flags, run
from jobq.clock import FakeClock
from jobq.jobs import DEFAULT_RETAIN_MS, Job, key_problem
from jobq.queue import Chaos, archive_step
from jobq.store import (
    ARCHIVE_NAME,
    LOG_NAME,
    ArchivedRecord,
    DeleteRecord,
    PutRecord,
    Store,
    StoreOpenError,
    compact,
    replay,
)
from support import QueueCase, body_of
from test_store import StoreCase, job

RETAIN_MS = 10_000
JOB = {"queue": "emails", "payload": "p", "max_tries": 1}


def finished(number: int, state: str = "done", updated_ms: int = 1, **fields: object) -> Job:
    return job(number, state).model_copy(update={"updated_ms": updated_ms} | fields)


def lines(path: os.PathLike[str]) -> list[dict[str, Any]]:
    with open(path, encoding="utf-8") as file:
        return [json.loads(line) for line in file]


def listed(response: Response) -> list[str]:
    """The ids a `{"jobs": [...]}` answer shows."""
    return [job["id"] for job in json.loads(response.body)["jobs"]]


class KeyRuleTest(unittest.TestCase):
    def test_a_key_follows_the_queue_names_rule(self) -> None:
        for good in ("a", "order-17_retry", "x" * 64, "A9"):
            self.assertIsNone(key_problem(good), good)
        for bad in ("", "x" * 65, "has space", "é", "a/b", "a.b"):
            self.assertIsNotNone(key_problem(bad), bad)


class ArchiveStepTest(unittest.TestCase):
    def test_only_done_and_dead_jobs_past_retain_ms_move(self) -> None:
        clock = FakeClock(100_000)
        board = [
            finished(1, "done", updated_ms=100_000 - RETAIN_MS),
            finished(2, "dead", updated_ms=100_000 - RETAIN_MS - 1),
            finished(3, "done", updated_ms=100_000 - RETAIN_MS + 1),
            job(4, "queued"),
            job(5, "leased"),
        ]
        moved = archive_step(board, clock.now_ms(), RETAIN_MS)
        self.assertEqual([j.number for j in moved], [1, 2])
        self.assertTrue(all(j.archived_ms == 100_000 for j in moved))
        self.assertEqual(moved[0].model_copy(update={"archived_ms": None}), board[0])


class ArchiveCase(QueueCase):
    """A board whose jobs archive `RETAIN_MS` after they finish."""

    def open(self, ops: object = None, options: BoardOptions | None = None) -> Board:
        chosen = options or BoardOptions(retain_ms=RETAIN_MS)
        return Board(self.dir, self.clock, self.ops, chosen)

    def keyed(
        self, key: str, queue: str = "emails", **fields: object
    ) -> tuple[int, dict[str, object]]:
        response = self.call(
            "POST", "/jobs", {"queue": queue, "payload": "p", "max_tries": 1, "key": key} | fields
        )
        return response.status, body_of(response)

    def finish(self, state: str = "done") -> str:
        """A job in `emails`, leased and then acked or failed to its last try."""
        job_id = self.create(max_tries=1)
        self.assertEqual(self.call("POST", "/queues/emails/lease").status, 200)
        if state == "done":
            self.assertEqual(self.call("POST", f"/jobs/{job_id}/ack").status, 200)
        else:
            self.assertEqual(self.call("POST", f"/jobs/{job_id}/fail", {"reason": "x"}).status, 200)
        return job_id

    def health(self) -> dict[str, object]:
        return body_of(self.call("GET", "/health", token=None))


class IdempotentCreateTest(ArchiveCase):
    def test_a_keyed_create_is_201_and_shows_its_key(self) -> None:
        status, shown = self.keyed("order-1")
        self.assertEqual((status, shown["key"], shown["id"]), (201, "order-1", "j_1"))
        self.assertEqual(body_of(self.call("GET", "/jobs/j_1"))["key"], "order-1")

    def test_an_unkeyed_job_shows_no_key(self) -> None:
        self.assertNotIn("key", body_of(self.call("GET", f"/jobs/{self.create()}")))

    def test_a_bad_key_is_400(self) -> None:
        for bad in ("", "x" * 65, "a b", 7, None):
            body = JOB | {"key": bad}
            self.assertEqual(self.call("POST", "/jobs", body).status, 400, bad)
        self.assertEqual(self.health()["queued"], 0)

    def assert_repeat_answers(self, key: str, job_id: str, state: str) -> None:
        before = self.health()
        status, shown = self.keyed(key, payload="other", max_tries=5, delay_ms=100)
        self.assertEqual((status, shown["id"], shown["state"]), (200, job_id, state), state)
        self.assertEqual(shown["payload"], "p", "the rest of the second body is ignored")
        self.assertEqual(self.health() | {"uptime_ms": 0}, before | {"uptime_ms": 0})

    def test_a_repeated_key_answers_the_job_in_every_state(self) -> None:
        self.assertEqual(self.keyed("q1")[0], 201)
        self.assert_repeat_answers("q1", "j_1", "queued")
        self.assertEqual(self.keyed("s1", delay_ms=60_000)[0], 201)
        self.assert_repeat_answers("s1", "j_2", "scheduled")
        self.assertEqual(self.keyed("l1")[0], 201)
        self.assertEqual(body_of(self.call("POST", "/queues/emails/lease"))["id"], "j_1")
        self.assert_repeat_answers("q1", "j_1", "leased")
        self.call("POST", "/jobs/j_1/ack")
        self.assert_repeat_answers("q1", "j_1", "done")
        self.assertEqual(body_of(self.call("POST", "/queues/emails/lease"))["id"], "j_3")
        self.call("POST", "/jobs/j_3/fail", {"reason": "x"})
        self.assert_repeat_answers("l1", "j_3", "dead")
        self.clock.advance(RETAIN_MS)
        before = self.health()
        self.assertEqual(before["archived"], 2)
        status, shown = self.keyed("q1")
        self.assertEqual((status, shown["id"], shown["state"]), (200, "j_1", "done"))
        self.assertIn("archived_at", shown)
        self.assertEqual(self.health()["archived"], 2)

    def test_the_same_key_in_another_queue_is_another_job(self) -> None:
        self.assertEqual(self.keyed("k")[0], 201)
        status, shown = self.keyed("k", queue="reports")
        self.assertEqual((status, shown["id"]), (201, "j_2"))

    def test_a_delete_frees_the_key(self) -> None:
        self.keyed("k")
        self.assertEqual(self.call("DELETE", "/jobs/j_1").status, 204)
        status, shown = self.keyed("k")
        self.assertEqual((status, shown["id"]), (201, "j_2"))

    def test_a_delete_of_an_archived_job_frees_the_key(self) -> None:
        self.keyed("k")
        self.call("POST", "/queues/emails/lease")
        self.call("POST", "/jobs/j_1/ack")
        self.clock.advance(RETAIN_MS)
        self.assertEqual(self.keyed("k")[0], 200)
        self.assertEqual(self.call("DELETE", "/jobs/j_1").status, 204)
        status, shown = self.keyed("k")
        self.assertEqual((status, shown["id"]), (201, "j_2"))
        self.restart()
        self.assertEqual(self.keyed("k")[1]["id"], "j_2")

    def test_list_by_key(self) -> None:
        self.keyed("k")
        self.assertEqual(listed(self.call("GET", "/jobs?queue=emails&key=k")), ["j_1"])
        self.assertEqual(body_of(self.call("GET", "/jobs?queue=reports&key=k")), {"jobs": []})
        self.assertEqual(body_of(self.call("GET", "/jobs?queue=emails&key=z")), {"jobs": []})
        missing = self.call("GET", "/jobs?key=k")
        self.assertEqual((missing.status, body_of(missing)), (400, {"error": "key needs queue"}))
        self.assertEqual(self.call("GET", "/jobs?queue=emails&key=a%20b").status, 400)

    def test_list_by_key_finds_an_archived_job(self) -> None:
        self.keyed("k")
        self.call("POST", "/queues/emails/lease")
        self.call("POST", "/jobs/j_1/ack")
        self.clock.advance(RETAIN_MS)
        self.assertEqual(listed(self.call("GET", "/jobs?queue=emails&key=k")), ["j_1"])
        self.assertEqual(body_of(self.call("GET", "/jobs?queue=emails")), {"jobs": []})

    def test_the_key_map_survives_a_restart_a_self_restart_and_a_compaction(self) -> None:
        self.keyed("a")
        self.keyed("b")
        self.restart()
        self.assertEqual(self.keyed("a")[0], 200)
        with contextlib.redirect_stderr(io.StringIO()):
            self.api.fail("a test")
        self.assertEqual(self.api.restarts, 1)
        self.assertEqual(self.keyed("b")[0], 200)
        self.api.close()
        compact(self.dir)
        self.api = self.open()
        self.assertEqual((self.keyed("a")[0], self.keyed("b")[0]), (200, 200))
        self.assertEqual(self.keyed("c")[1]["id"], "j_3")


class KeyReplayTest(StoreCase):
    def test_the_map_is_rebuilt_from_a_written_log(self) -> None:
        store, _ = Store.open(self.dir)
        store.append(PutRecord(job=job(1).model_copy(update={"key": "k1"})))
        store.append(PutRecord(job=job(2).model_copy(update={"key": "k2"})))
        store.append(DeleteRecord(number=2))
        store.close()
        board = Board(self.dir, FakeClock())
        try:
            self.assertEqual(board.queue.keyed("q", "k1"), job(1).model_copy(update={"key": "k1"}))
            self.assertIsNone(board.queue.keyed("q", "k2"))
            self.assertIsNone(board.queue.keyed("other", "k1"))
        finally:
            board.close()

    def test_a_bad_key_in_a_record_refuses_the_folder(self) -> None:
        record = PutRecord(job=job(1)).model_dump(mode="json")
        record["job"]["key"] = "no spaces"
        (self.dir / LOG_NAME).write_text(json.dumps(record) + "\n")
        with self.assertRaisesRegex(StoreOpenError, "record j_1: job.key"):
            Store.open(self.dir)

    def test_a_key_naming_two_jobs_refuses_the_folder(self) -> None:
        store, _ = Store.open(self.dir)
        store.append(PutRecord(job=job(1).model_copy(update={"key": "k"})))
        store.append(PutRecord(job=job(2).model_copy(update={"key": "k"})))
        store.close()
        with self.assertRaisesRegex(StoreOpenError, "record j_2: key 'k' also names j_1 in q"):
            Store.open(self.dir)


class ArchiveMoveTest(ArchiveCase):
    def test_a_finished_job_is_archived_at_the_first_look_past_retain_ms(self) -> None:
        done, dead = self.finish("done"), self.finish("dead")
        self.clock.advance(RETAIN_MS - 1)
        health = self.health()
        self.assertEqual((health["done"], health["dead"], health["archived"]), (1, 1, 0))
        self.clock.advance(1)
        health = self.health()
        self.assertEqual((health["done"], health["dead"], health["archived"]), (0, 0, 2))
        replayed = replay(self.dir)
        self.assertEqual(replayed.jobs, {})
        self.assertEqual(sorted(replayed.archived), [1, 2])
        archive = lines(self.dir / ARCHIVE_NAME)
        self.assertEqual([r["job"]["archived_ms"] for r in archive], [self.clock.ms] * 2)
        log = lines(self.dir / LOG_NAME)
        self.assertEqual(
            log[-2:], [{"kind": "archived", "number": 1}, {"kind": "archived", "number": 2}]
        )
        for job_id, state in ((done, "done"), (dead, "dead")):
            shown = body_of(self.call("GET", f"/jobs/{job_id}"))
            self.assertEqual(shown["state"], state)
            self.assertTrue(str(shown["archived_at"]).endswith("Z"))

    def test_listings_never_show_an_archived_job(self) -> None:
        self.finish()
        self.create()
        self.clock.advance(RETAIN_MS)
        self.assertEqual(listed(self.call("GET", "/jobs")), ["j_2"])
        self.assertEqual(body_of(self.call("GET", "/jobs?state=done")), {"jobs": []})
        queues = json.loads(self.call("GET", "/queues").body)["queues"]
        self.assertEqual(queues[0]["done"], 0)

    def test_a_retried_job_is_not_archived_while_it_waits(self) -> None:
        self.finish("dead")
        self.clock.advance(RETAIN_MS - 1)
        self.assertEqual(self.call("POST", "/jobs/j_1/retry").status, 200)
        self.clock.advance(RETAIN_MS)
        self.assertEqual(self.health()["archived"], 0)

    def test_retry_ack_and_fail_of_an_archived_job_are_409(self) -> None:
        self.finish("dead")
        self.clock.advance(RETAIN_MS)
        retried = self.call("POST", "/jobs/j_1/retry")
        self.assertEqual((retried.status, body_of(retried)), (409, {"error": "archived"}))
        self.assertEqual(self.call("POST", "/jobs/j_1/ack").status, 409)
        self.assertEqual(self.call("POST", "/jobs/j_1/fail", {"reason": "x"}).status, 409)
        self.assertEqual(self.call("POST", "/jobs/j_9/retry").status, 404)

    def test_an_archived_job_is_deleted_by_a_tombstone_and_gone_after_compaction(self) -> None:
        self.finish()
        self.finish()
        self.clock.advance(RETAIN_MS)
        self.assertEqual(self.call("DELETE", "/jobs/j_1").status, 204)
        self.assertEqual(self.call("GET", "/jobs/j_1").status, 404)
        self.assertEqual(self.call("DELETE", "/jobs/j_1").status, 404)
        self.assertEqual(self.health()["archived"], 1)
        self.assertEqual(lines(self.dir / ARCHIVE_NAME)[-1], {"kind": "delete", "number": 1})
        self.restart()
        self.assertEqual(self.call("GET", "/jobs/j_1").status, 404)
        self.assertEqual(self.health()["archived"], 1)
        self.api.close()
        compact(self.dir)
        self.api = self.open()
        archive = lines(self.dir / ARCHIVE_NAME)
        self.assertEqual([r["job"]["number"] for r in archive], [2])
        self.assertEqual(lines(self.dir / LOG_NAME), [{"kind": "counter", "next_number": 3}])
        self.assertEqual(self.call("GET", "/jobs/j_2").status, 200)
        self.assertEqual(self.create(), "j_3")

    def test_an_archived_job_survives_a_restart_and_never_comes_back(self) -> None:
        self.finish()
        self.clock.advance(RETAIN_MS)
        self.health()
        self.restart()
        self.clock.advance(RETAIN_MS)
        self.assertEqual(self.health()["archived"], 1)
        self.assertEqual(self.queue.snapshot(), {})
        self.assertIn("archived_at", body_of(self.call("GET", "/jobs/j_1")))

    def test_the_default_retention_is_a_day(self) -> None:
        self.api.close()
        self.api = self.open(options=BoardOptions())
        self.finish()
        self.clock.advance(DEFAULT_RETAIN_MS - 1)
        self.assertEqual(self.health()["archived"], 0)
        self.clock.advance(1)
        self.assertEqual(self.health()["archived"], 1)


class ArchiveWriteFaultTest(ArchiveCase):
    """The move's two writes, with a failure or a kill between them."""

    def test_a_failed_archive_write_moves_nothing(self) -> None:
        self.finish()
        self.clock.advance(RETAIN_MS)
        self.ops.failing = True
        self.assertEqual(self.call("GET", "/health", token=None).status, 503)
        self.ops.failing = False
        self.assertEqual(replay(self.dir).archived, {})
        self.assertEqual(self.queue.archived_snapshot(), {})
        self.assertEqual(self.health()["archived"], 1)

    def test_a_failed_log_write_after_the_archive_write_still_moves_the_job(self) -> None:
        self.finish()
        self.clock.advance(RETAIN_MS)
        real_write = self.ops.write

        def fail_the_marker(fd: int, data: bytes) -> int:
            if b'"kind":"archived"' in data:
                raise OSError(errno.EIO, "injected")
            return real_write(fd, data)

        self.ops.write = fail_the_marker  # type: ignore[method-assign]
        health = self.health()
        self.assertEqual((health["done"], health["archived"]), (0, 1))
        self.assertEqual(replay(self.dir).jobs, {})  # the archive wins
        self.assertNotIn({"kind": "archived", "number": 1}, lines(self.dir / LOG_NAME))
        self.ops.write = real_write  # type: ignore[method-assign]
        self.health()
        self.assertIn({"kind": "archived", "number": 1}, lines(self.dir / LOG_NAME))

    def test_a_kill_between_the_writes_leaves_the_job_archived_once(self) -> None:
        self.finish()
        self.clock.advance(RETAIN_MS)
        with (
            mock.patch.object(Chaos, "fails", lambda _self, changes: changes > 0),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            self.assertEqual(self.call("GET", "/health", token=None).status, 503)
        self.assertEqual(self.api.restarts, 1)
        log = lines(self.dir / LOG_NAME)
        self.assertEqual(log[-1]["job"]["state"], "done")
        self.assertEqual(len(lines(self.dir / ARCHIVE_NAME)), 1)
        health = self.health()
        self.assertEqual((health["done"], health["archived"]), (0, 1))
        self.assertEqual(self.call("POST", "/jobs/j_1/retry").status, 409)


class OpenBothFilesTest(StoreCase):
    def write(self, name: str, *records: object) -> None:
        with open(self.dir / name, "a", encoding="utf-8") as file:
            for record in records:
                assert isinstance(record, PutRecord | DeleteRecord | ArchivedRecord)
                file.write(record.model_dump_json() + "\n")

    def test_a_job_in_both_files_is_archived_and_counted_once(self) -> None:
        live = finished(1, key="k")
        self.write(
            LOG_NAME, PutRecord(job=job(1).model_copy(update={"key": "k"})), PutRecord(job=live)
        )
        self.write(ARCHIVE_NAME, PutRecord(job=live.model_copy(update={"archived_ms": 5})))
        board = Board(self.dir, FakeClock())
        try:
            self.assertEqual(board.queue.snapshot(), {})
            self.assertEqual(board.queue.archived_count, 1)
            self.assertEqual(board.queue.counts()["done"], 0)
            self.assertEqual(
                board.queue.keyed("q", "k"), live.model_copy(update={"archived_ms": 5})
            )
        finally:
            board.close()
        code, out, _ = invoke("verify", str(self.dir))
        self.assertEqual(code, EXIT_OK)
        self.assertTrue(out.startswith("0 jobs:") and out.endswith("; archived 1\n"), out)

    def test_a_folder_without_an_archive_is_an_empty_archive(self) -> None:
        self.write(LOG_NAME, PutRecord(job=job(1)))
        state = replay(self.dir)
        self.assertEqual((list(state.jobs), state.archived), ([1], {}))

    def test_a_torn_last_archive_line_is_cut(self) -> None:
        self.write(ARCHIVE_NAME, PutRecord(job=finished(1, archived_ms=5)))
        whole = (self.dir / ARCHIVE_NAME).stat().st_size
        with open(self.dir / ARCHIVE_NAME, "a", encoding="utf-8") as file:
            file.write('{"kind":"put","job":{"num')
        store, state = Store.open(self.dir)
        store.close()
        self.assertEqual((list(state.archived), state.next_number), ([1], 2))
        self.assertEqual((self.dir / ARCHIVE_NAME).stat().st_size, whole)

    def test_verify_refuses_a_bad_archive_record(self) -> None:
        cases = [
            (finished(1, "done"), "archive record j_1: an archived job has an archived_at"),
            (
                job(1, "queued").model_copy(update={"archived_ms": 5}),
                "archive record j_1: a queued job has no archived_at",
            ),
        ]
        for record, rule in cases:
            with self.subTest(rule=rule):
                (self.dir / ARCHIVE_NAME).write_text(PutRecord(job=record).model_dump_json() + "\n")
                code, out, err = invoke("verify", str(self.dir))
                self.assertEqual((code, out), (EXIT_FAILURE, ""))
                self.assertEqual(err, f"jobq: {self.dir}: {rule}\n")
                self.assertEqual(invoke("compact", str(self.dir))[0], EXIT_FAILURE)
        (self.dir / ARCHIVE_NAME).write_text('{"kind":"counter","next_number":3}\n')
        self.assertEqual(invoke("verify", str(self.dir))[0], EXIT_FAILURE)

    def test_verify_refuses_an_archived_at_in_the_live_log(self) -> None:
        self.write(LOG_NAME, PutRecord(job=finished(1, archived_ms=5)))
        code, _, err = invoke("verify", str(self.dir))
        self.assertEqual(code, EXIT_FAILURE)
        self.assertIn("record j_1: a live job has no archived_at", err)


class RetainFlagTest(unittest.TestCase):
    def test_retain_ms_is_parsed_and_bounded(self) -> None:
        self.assertEqual(parse_serve_flags([])[1].retain_ms, 86_400_000)
        self.assertEqual(parse_serve_flags(["--retain-ms", "1000"])[1].retain_ms, 1000)
        top = parse_serve_flags(["--retain-ms", "2678400000"])[1].retain_ms
        self.assertEqual(top, 2_678_400_000)
        for bad in ("999", "2678400001", "-5", "1e4", "", "99999999999"):
            with self.assertRaises(UsageError, msg=bad):
                parse_serve_flags(["--retain-ms", bad])


def invoke(*argv: str) -> tuple[int, str, str]:
    stdout, stderr = io.StringIO(), io.StringIO()
    code = run(list(argv), stdout, stderr)
    return code, stdout.getvalue(), stderr.getvalue()


if __name__ == "__main__":
    unittest.main()
