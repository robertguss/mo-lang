"""Change 5: a lease handed off to another worker, and a queue renamed with jobs in flight."""

import contextlib
import io
import json
import unittest
from typing import Any
from unittest import mock

from jobq.board import Board, BoardOptions
from jobq.clock import FakeClock
from jobq.contract import ContractError
from jobq.jobs import Job, handoff_token_problem
from jobq.queue import Chaos, check_transition, rename_step
from jobq.store import (
    ARCHIVE_NAME,
    LOG_NAME,
    ArchivedRecord,
    ArchivePutRecord,
    CounterRecord,
    DeleteRecord,
    PutRecord,
    RenameRecord,
    Store,
    compact,
    replay,
)
from support import QueueCase, body_of
from test_archive import RETAIN_MS, ArchiveCase, finished, invoke, lines, listed
from test_store import StoreCase, job

LEASE_MS = 10_000


def crashing() -> contextlib.ExitStack:
    """Every change the board applies fails after its record is on disk."""
    stack = contextlib.ExitStack()
    stack.enter_context(mock.patch.object(Chaos, "fails", lambda _self, changes: changes > 0))
    stack.enter_context(contextlib.redirect_stderr(io.StringIO()))
    return stack


class HandoffRuleTest(unittest.TestCase):
    def test_to_is_a_token_of_at_most_128_bytes(self) -> None:
        for good in ("w", "x" * 128, "worker-2@host:9", "!~"):
            self.assertIsNone(handoff_token_problem(good), good)
        for bad in ("", "x" * 129, "has space", "tab\there", "é", "new\nline"):
            self.assertIsNotNone(handoff_token_problem(bad), bad)


class HandoffCase(QueueCase):
    def leased(self, worker: str = "w1") -> dict[str, Any]:
        """A job in `emails`, leased to `worker` for `LEASE_MS`."""
        self.create()
        response = self.call("POST", "/queues/emails/lease", {"lease_ms": LEASE_MS}, token=worker)
        self.assertEqual(response.status, 200)
        return body_of(response)

    def handoff(self, job_id: str, frm: str, to: object) -> tuple[int, dict[str, Any]]:
        response = self.call("POST", f"/jobs/{job_id}/handoff", {"to": to}, token=frm)
        return response.status, body_of(response)

    def ack(self, job_id: str, worker: str) -> int:
        return self.call("POST", f"/jobs/{job_id}/ack", token=worker).status


class HandoffTest(HandoffCase):
    def test_the_holder_hands_the_lease_to_another_worker(self) -> None:
        held = self.leased("w1")
        self.clock.advance(5)
        status, handed = self.handoff(held["id"], "w1", "w2")
        self.assertEqual(status, 200)
        self.assertEqual(handed["worker"], "w2")
        self.assertEqual(handed["state"], "leased")
        for kept in ("lease_until", "tries", "created_at", "payload", "queue"):
            self.assertEqual(handed[kept], held[kept], kept)
        self.assertNotEqual(handed["updated_at"], held["updated_at"])
        self.assertEqual(body_of(self.call("GET", f"/jobs/{held['id']}")), handed)
        self.assertEqual(self.ack(held["id"], "w1"), 409)
        self.assertEqual(self.ack(held["id"], "w2"), 200)

    def test_the_new_worker_may_fail_it(self) -> None:
        held = self.leased("w1")
        self.handoff(held["id"], "w1", "w2")
        response = self.call("POST", f"/jobs/{held['id']}/fail", {"reason": "r"}, token="w1")
        self.assertEqual(response.status, 409)
        response = self.call("POST", f"/jobs/{held['id']}/fail", {"reason": "r"}, token="w2")
        self.assertEqual((response.status, body_of(response)["state"]), (200, "queued"))

    def test_a_stranger_cannot_hand_it_off(self) -> None:
        held = self.leased("w1")
        before = self.queue.snapshot()
        self.assertEqual(self.handoff(held["id"], "w9", "w9")[0], 409)
        self.assertEqual(self.handoff(held["id"], "w9", "w2")[0], 409)
        self.assertEqual(self.queue.snapshot(), before)

    def test_an_unknown_or_unleased_job(self) -> None:
        self.assertEqual(self.handoff("j_99", "w1", "w2")[0], 404)
        self.assertEqual(self.handoff("nope", "w1", "w2")[0], 404)
        queued = self.create()
        self.assertEqual(self.handoff(queued, "w1", "w2")[0], 409)

    def test_a_run_out_lease_cannot_be_handed_off(self) -> None:
        held = self.leased("w1")
        self.clock.advance(LEASE_MS)
        self.assertEqual(self.handoff(held["id"], "w1", "w2")[0], 409)
        self.assertEqual(body_of(self.call("GET", f"/jobs/{held['id']}"))["state"], "queued")

    def test_a_handoff_to_the_holder_changes_nothing(self) -> None:
        held = self.leased("w1")
        size = self.queue.store.size
        self.clock.advance(5)
        status, same = self.handoff(held["id"], "w1", "w1")
        self.assertEqual((status, same), (200, held))
        self.assertEqual(self.queue.store.size, size)
        self.assertEqual(self.ack(held["id"], "w1"), 200)

    def test_twice_in_a_row(self) -> None:
        held = self.leased("A")
        self.assertEqual(self.handoff(held["id"], "A", "B")[0], 200)
        self.assertEqual(self.handoff(held["id"], "A", "C")[0], 409)
        status, handed = self.handoff(held["id"], "B", "C")
        self.assertEqual((status, handed["worker"]), (200, "C"))
        self.assertEqual(handed["lease_until"], held["lease_until"])
        self.assertEqual(self.ack(held["id"], "A"), 409)
        self.assertEqual(self.ack(held["id"], "B"), 409)
        self.assertEqual(self.ack(held["id"], "C"), 200)

    def test_a_bad_to_is_400(self) -> None:
        held = self.leased("w1")
        for body in ({"to": ""}, {"to": "x" * 129}, {"to": "a b"}, {"to": 5}, {"to": None}, {}):
            with self.subTest(body=body):
                response = self.call("POST", f"/jobs/{held['id']}/handoff", body)
                self.assertEqual(response.status, 400)
        response = self.call("POST", f"/jobs/{held['id']}/handoff", {"to": "w2", "x": 1})
        self.assertEqual(response.status, 400)
        self.assertEqual(self.call("POST", f"/jobs/{held['id']}/handoff", raw=b"").status, 400)
        self.assertEqual(self.call("GET", f"/jobs/{held['id']}/handoff").status, 405)
        self.assertEqual(self.handoff(held["id"], "w1", "x" * 128)[0], 200)

    def test_the_handed_off_lease_runs_out_once_at_its_old_deadline(self) -> None:
        held = self.leased("w1")
        self.handoff(held["id"], "w1", "w2")
        self.clock.advance(LEASE_MS - 1)
        self.assertEqual(body_of(self.call("GET", "/health", token=None))["leased"], 1)
        self.clock.advance(1)
        health = body_of(self.call("GET", "/health", token=None))
        self.assertEqual((health["leased"], health["queued"]), (0, 1))
        self.assertEqual(self.ack(held["id"], "w2"), 409)
        self.queue.check_all()

    def test_a_handoff_survives_a_restart(self) -> None:
        held = self.leased("w1")
        self.handoff(held["id"], "w1", "w2")
        self.restart()
        shown = body_of(self.call("GET", f"/jobs/{held['id']}"))
        self.assertEqual((shown["worker"], shown["lease_until"]), ("w2", held["lease_until"]))
        self.assertEqual(self.ack(held["id"], "w1"), 409)
        self.assertEqual(self.ack(held["id"], "w2"), 200)

    def test_a_handoff_that_cannot_be_written_changes_nothing(self) -> None:
        held = self.leased("w1")
        before = self.queue.snapshot()
        self.ops.failing = True
        self.assertEqual(self.handoff(held["id"], "w1", "w2")[0], 503)
        self.ops.failing = False
        self.assertEqual(self.queue.snapshot(), before)
        self.assertEqual(replay(self.dir).jobs, before)
        self.assertEqual(self.ack(held["id"], "w1"), 200)

    def test_a_handoff_counts_for_the_chaos_switch(self) -> None:
        held = self.leased("w1")
        with crashing():
            self.assertEqual(self.handoff(held["id"], "w1", "w2")[0], 503)
        self.assertEqual(self.api.restarts, 1)
        self.assertEqual(body_of(self.call("GET", f"/jobs/{held['id']}"))["worker"], "w2")
        self.assertEqual(self.ack(held["id"], "w2"), 200)

    def test_the_chaos_count_includes_handoffs(self) -> None:
        chaos = Chaos(2)
        self.assertFalse(chaos.fails(1))
        self.assertTrue(chaos.fails(1))


class HandoffNeverTest(QueueCase):
    def lease(self) -> Job:
        self.queue.create("emails", "a", 3)
        leased = self.queue.lease("emails", "w1", 1000)
        assert leased is not None
        return leased

    def test_a_handoff_moves_only_the_worker(self) -> None:
        first = self.lease()
        check_transition(first, first.model_copy(update={"worker": "w2"}))
        broken: list[tuple[dict[str, object], str]] = [
            ({"worker": "w2", "lease_until_ms": (first.lease_until_ms or 0) + 1}, "lease_until"),
            ({"worker": "w2", "tries": 2}, "never held by two workers"),
            ({"worker": "w1"}, "never held by two workers"),
            ({"worker": "w2", "updated_ms": first.lease_until_ms}, "only a live lease"),
            ({"worker": "w2", "reason": "r"}, "only the worker moves"),
            ({"worker": "w2", "queue": "other"}, "fields are fixed"),
        ]
        for update, rule in broken:
            with self.subTest(rule=rule), self.assertRaisesRegex(ContractError, rule):
                check_transition(first, first.model_copy(update=update))

    def test_a_broken_handoff_is_never_written(self) -> None:
        first = self.lease()
        size = self.queue.store.size
        with self.assertRaisesRegex(ContractError, "lease_until"):
            self.queue._commit(
                first, first.model_copy(update={"worker": "w2", "lease_until_ms": 5})
            )
        self.assertEqual(self.queue.store.size, size)


def board_of(*jobs: Job) -> dict[int, Job]:
    return {j.number: j for j in jobs}


class RenameStepTest(unittest.TestCase):
    """The rename as a pure step over the board, the archive, and the key map."""

    def test_every_job_in_every_state_moves_with_its_key_and_its_lease(self) -> None:
        states = ["queued", "scheduled", "leased", "done", "dead"]
        live = board_of(
            *[job(n, s).model_copy(update={"key": f"k{n}"}) for n, s in enumerate(states, 1)],
            job(6).model_copy(update={"queue": "other", "key": "k1"}),
        )
        archived = board_of(finished(7, archived_ms=5, key="k7"))
        keys = {(j.queue, j.key): n for n, j in (live | archived).items() if j.key is not None}
        after = rename_step(live, archived, keys, "q", "r")
        self.assertEqual(after.moved, 6)
        self.assertEqual([j.queue for j in after.jobs.values()], ["r"] * 5 + ["other"])
        self.assertEqual(after.archived[7].queue, "r")
        self.assertEqual(after.jobs[3].worker, live[3].worker)
        self.assertEqual(after.jobs[3].lease_until_ms, live[3].lease_until_ms)
        self.assertEqual(
            after.keys,
            {("r", "k1"): 1, ("r", "k2"): 2, ("r", "k3"): 3, ("r", "k4"): 4, ("r", "k5"): 5}
            | {("other", "k1"): 6, ("r", "k7"): 7},
        )
        self.assertEqual(live[1].queue, "q")  # the step changes nothing it was given

    def test_a_key_clash_cannot_happen(self) -> None:
        # The target holds no job, live or archived, so no key is used in it: every key moved
        # from `q` lands on a free (r, key). The step requires the target empty rather than
        # merging, which is why no clash-handling code exists; a used target is refused.
        live = board_of(
            job(1).model_copy(update={"key": "k"}),
            job(2).model_copy(update={"queue": "r", "key": "k"}),
        )
        keys = {("q", "k"): 1, ("r", "k"): 2}
        with self.assertRaisesRegex(ContractError, "to is empty"):
            rename_step(live, {}, keys, "q", "r")
        with self.assertRaisesRegex(ContractError, "no key is used in to"):
            rename_step(board_of(job(1)), {}, {("r", "k"): 9}, "q", "r")
        with self.assertRaisesRegex(ContractError, "another name"):
            rename_step(live, {}, keys, "q", "q")


class RenameTest(ArchiveCase):
    def rename(self, name: str, to: object) -> tuple[int, dict[str, Any]]:
        response = self.call("POST", f"/queues/{name}/rename", {"to": to}, token="operator")
        return response.status, body_of(response)

    def queues(self) -> dict[str, dict[str, Any]]:
        shown = body_of(self.call("GET", "/queues"))["queues"]
        assert isinstance(shown, list)
        return {row.pop("name"): row for row in shown}

    def a_busy_queue(self) -> dict[str, str]:
        """`emails` with an archived job, a done and a dead one, a leased one held by w1, a
        scheduled and a queued one, most keyed; and a job in `other` with the same key."""
        ids = {"archived": self.finish()}
        self.clock.advance(RETAIN_MS)
        self.call("GET", "/health", token=None)
        ids["done"] = self.finish()
        ids["dead"] = self.finish("dead")
        ids["leased"] = str(self.keyed("kl", max_tries=2)[1]["id"])
        self.assertEqual(self.call("POST", "/queues/emails/lease").status, 200)
        ids["scheduled"] = str(self.keyed("ks", delay_ms=60_000)[1]["id"])
        ids["queued"] = str(self.keyed("kq")[1]["id"])
        ids["other"] = str(self.keyed("kq", queue="other")[1]["id"])
        self.assertEqual(self.queue.archived_count, 1)
        return ids

    def test_every_job_moves_in_every_state(self) -> None:
        ids = self.a_busy_queue()
        counts = self.queues()["emails"]
        self.assertEqual(self.rename("emails", "mail"), (200, {"queue": "mail", "moved": 6}))
        for state, job_id in ids.items():
            shown = body_of(self.call("GET", f"/jobs/{job_id}"))
            self.assertEqual(shown["queue"], "other" if state == "other" else "mail", state)
        queues = self.queues()
        self.assertEqual((sorted(queues), queues["mail"]), (["mail", "other"], counts))
        self.assertEqual(len(listed(self.call("GET", "/jobs?queue=mail"))), 5)
        self.assertEqual(listed(self.call("GET", "/jobs?queue=emails")), [])

    def test_keys_move_with_the_queue(self) -> None:
        ids = self.a_busy_queue()
        self.rename("emails", "mail")
        for key, state in (("kl", "leased"), ("kq", "queued"), ("ks", "scheduled")):
            found = listed(self.call("GET", f"/jobs?queue=mail&key={key}"))
            self.assertEqual(found, [ids[state]])
            self.assertEqual(listed(self.call("GET", f"/jobs?queue=emails&key={key}")), [])
        self.assertEqual(listed(self.call("GET", "/jobs?queue=other&key=kq")), [ids["other"]])
        self.assertEqual(
            self.keyed("kq", queue="mail"),
            (200, body_of(self.call("GET", f"/jobs/{ids['queued']}"))),
        )
        status, fresh = self.keyed("kq")
        self.assertEqual((status, fresh["queue"]), (201, "emails"))
        self.queue.check_all()

    def test_a_lease_in_flight_is_untouched_and_its_ack_succeeds(self) -> None:
        ids = self.a_busy_queue()
        before = body_of(self.call("GET", f"/jobs/{ids['leased']}"))
        self.rename("emails", "mail")
        after = body_of(self.call("GET", f"/jobs/{ids['leased']}"))
        self.assertEqual(after, before | {"queue": "mail"})
        self.assertEqual(self.call("POST", f"/jobs/{ids['leased']}/ack").status, 200)

    def test_a_lease_in_flight_may_be_failed_after(self) -> None:
        ids = self.a_busy_queue()
        self.rename("emails", "mail")
        response = self.call("POST", f"/jobs/{ids['leased']}/fail", {"reason": "r"})
        self.assertEqual((response.status, body_of(response)["queue"]), (200, "mail"))
        leased = self.call("POST", "/queues/mail/lease", token="w2")
        self.assertEqual(body_of(leased)["id"], ids["leased"])

    def test_leases_follow_the_new_name(self) -> None:
        ids = self.a_busy_queue()
        self.rename("emails", "mail")
        self.assertEqual(self.call("POST", "/queues/emails/lease").status, 204)
        leased = self.call("POST", "/queues/mail/lease")
        self.assertEqual((leased.status, body_of(leased)["id"]), (200, ids["queued"]))

    def test_a_new_job_in_the_old_name_starts_a_fresh_queue(self) -> None:
        self.a_busy_queue()
        self.rename("emails", "mail")
        job_id = self.create()
        self.assertEqual(self.queues()["emails"]["queued"], 1)
        leased = self.call("POST", "/queues/emails/lease")
        self.assertEqual(body_of(leased)["id"], job_id)

    def test_renaming_back_restores_everything(self) -> None:
        ids = self.a_busy_queue()
        before = {i: body_of(self.call("GET", f"/jobs/{i}")) for i in ids.values()}
        keys = {k: listed(self.call("GET", f"/jobs?queue=emails&key={k}")) for k in ("kl", "kq")}
        self.rename("emails", "mail")
        self.assertEqual(self.rename("mail", "emails"), (200, {"queue": "emails", "moved": 6}))
        self.assertEqual({i: body_of(self.call("GET", f"/jobs/{i}")) for i in ids.values()}, before)
        for key, found in keys.items():
            self.assertEqual(listed(self.call("GET", f"/jobs?queue=emails&key={key}")), found)
        self.restart()
        self.assertEqual({i: body_of(self.call("GET", f"/jobs/{i}")) for i in ids.values()}, before)

    def test_the_refusals(self) -> None:
        self.a_busy_queue()
        self.assertEqual(self.rename("nothing", "x")[0], 404)
        self.assertEqual(self.rename("emails", "other"), (409, {"error": "exists"}))
        self.assertEqual(self.rename("emails", "emails"), (409, {"error": "exists"}))
        for bad in ("", "a b", "x" * 65, 5, None):
            self.assertEqual(self.rename("emails", bad)[0], 400, bad)
        self.assertEqual(self.rename("bad%20name", "x")[0], 400)
        response = self.call("POST", "/queues/emails/rename", {"to": "x", "extra": 1})
        self.assertEqual(response.status, 400)
        self.assertEqual(self.call("GET", "/queues/emails/rename").status, 405)
        self.assertEqual(
            self.call("POST", "/queues/emails/rename", {"to": "x"}, token=None).status, 401
        )
        self.assertEqual(sorted(self.queues()), ["emails", "other"])

    def test_a_queue_holding_only_archived_jobs(self) -> None:
        archived_id = self.finish()
        self.clock.advance(RETAIN_MS)
        self.assertEqual(self.queues(), {})
        self.assertEqual(self.rename("emails", "mail"), (200, {"queue": "mail", "moved": 1}))
        self.assertEqual(body_of(self.call("GET", f"/jobs/{archived_id}"))["queue"], "mail")
        self.create(queue="fresh")
        self.assertEqual(self.rename("fresh", "mail"), (409, {"error": "exists"}))

    def test_a_rename_is_one_durable_record(self) -> None:
        self.a_busy_queue()
        before = lines(self.dir / LOG_NAME)
        archive = (self.dir / ARCHIVE_NAME).read_bytes()
        self.rename("emails", "mail")
        self.assertEqual(
            lines(self.dir / LOG_NAME),
            [*before, {"kind": "rename", "name": "emails", "to": "mail", "next_id": 8}],
        )
        self.assertEqual((self.dir / ARCHIVE_NAME).read_bytes(), archive)
        self.assertEqual(replay(self.dir).jobs, self.queue.snapshot())
        self.assertEqual(replay(self.dir).archived, self.queue.archived_snapshot())

    def test_a_rename_survives_a_restart_and_a_compaction(self) -> None:
        ids = self.a_busy_queue()
        self.rename("emails", "mail")
        shown = {i: body_of(self.call("GET", f"/jobs/{i}")) for i in ids.values()}
        self.restart()
        self.assertEqual({i: body_of(self.call("GET", f"/jobs/{i}")) for i in ids.values()}, shown)
        self.api.close()
        compact(self.dir)
        self.api = self.open()
        self.assertEqual({i: body_of(self.call("GET", f"/jobs/{i}")) for i in ids.values()}, shown)
        self.assertEqual(listed(self.call("GET", "/jobs?queue=mail&key=kq")), [ids["queued"]])
        self.queue.check_all()

    def test_a_rename_that_cannot_be_written_moves_nothing(self) -> None:
        self.a_busy_queue()
        before = (self.queue.snapshot(), self.queue.archived_snapshot())
        self.ops.failing = True
        self.assertEqual(self.rename("emails", "mail")[0], 503)
        self.ops.failing = False
        self.assertEqual((self.queue.snapshot(), self.queue.archived_snapshot()), before)
        self.assertEqual(replay(self.dir).jobs, before[0])
        self.assertNotIn("rename", (self.dir / LOG_NAME).read_text())
        self.assertEqual(self.call("POST", "/queues/mail/lease").status, 204)
        self.assertEqual(self.rename("emails", "mail")[0], 200)

    def test_a_failure_after_the_write_leaves_every_job_moved(self) -> None:
        ids = self.a_busy_queue()
        with crashing():
            self.assertEqual(self.rename("emails", "mail")[0], 503)
        self.assertEqual(self.api.restarts, 1)
        for state, job_id in ids.items():
            shown = body_of(self.call("GET", f"/jobs/{job_id}"))["queue"]
            self.assertEqual(shown, "other" if state == "other" else "mail")
        self.assertEqual(self.call("POST", f"/jobs/{ids['leased']}/ack").status, 200)

    def test_an_archive_written_after_a_rename_keeps_a_reused_name(self) -> None:
        old = self.finish()
        self.rename("emails", "mail")
        reused = self.finish()  # a fresh `emails`, archived after the rename record
        self.clock.advance(RETAIN_MS)
        self.assertEqual(self.health()["archived"], 2)
        records = lines(self.dir / ARCHIVE_NAME)
        self.assertEqual(
            [(r["job"]["queue"], r.get("renames", 0)) for r in records],
            [("mail", 1), ("emails", 1)],
        )
        for reopen in (self.restart, self.compact_and_restart):
            reopen()
            self.assertEqual(body_of(self.call("GET", f"/jobs/{old}"))["queue"], "mail")
            self.assertEqual(body_of(self.call("GET", f"/jobs/{reused}"))["queue"], "emails")

    def compact_and_restart(self) -> None:
        self.api.close()
        compact(self.dir)
        self.api = self.open()

    def test_a_handoff_and_a_rename_together(self) -> None:
        job_id = str(self.keyed("k", max_tries=2)[1]["id"])
        self.call("POST", "/queues/emails/lease", token="A")
        self.rename("emails", "mail")
        response = self.call("POST", f"/jobs/{job_id}/handoff", {"to": "B"}, token="A")
        self.assertEqual((response.status, body_of(response)["queue"]), (200, "mail"))
        self.restart()
        shown = body_of(self.call("GET", f"/jobs/{job_id}"))
        self.assertEqual((shown["queue"], shown["worker"]), ("mail", "B"))
        self.assertEqual(self.call("POST", f"/jobs/{job_id}/ack", token="B").status, 200)


class RenameReplayTest(StoreCase):
    def write(self, name: str, *records: object) -> None:
        with open(self.dir / name, "a", encoding="utf-8") as file:
            for record in records:
                assert isinstance(
                    record,
                    PutRecord | DeleteRecord | ArchivedRecord | RenameRecord | CounterRecord,
                )
                file.write(record.model_dump_json() + "\n")

    def in_queue(self, number: int, queue: str, state: str = "queued") -> Job:
        return job(number, state).model_copy(update={"queue": queue})

    def test_a_rename_moves_only_the_jobs_written_before_it(self) -> None:
        self.write(
            LOG_NAME,
            PutRecord(job=self.in_queue(1, "a")),
            PutRecord(job=self.in_queue(2, "b")),
            RenameRecord(name="a", to="c"),
            PutRecord(job=self.in_queue(3, "a")),
            PutRecord(job=self.in_queue(1, "c", "leased")),
        )
        state = replay(self.dir)
        self.assertEqual({n: j.queue for n, j in state.jobs.items()}, {1: "c", 2: "b", 3: "a"})
        self.assertEqual((state.renames, state.records), (1, 5))
        self.assertEqual(state.jobs[1].worker, "w1")

    def test_a_rename_with_a_key_in_the_old_name(self) -> None:
        keyed = self.in_queue(1, "a").model_copy(update={"key": "k"})
        self.write(
            LOG_NAME,
            PutRecord(job=keyed),
            RenameRecord(name="a", to="c"),
            PutRecord(job=self.in_queue(2, "a").model_copy(update={"key": "k"})),
        )
        board = Board(self.dir, FakeClock())
        try:
            self.assertEqual(board.queue.keyed("c", "k"), keyed.model_copy(update={"queue": "c"}))
            found = board.queue.keyed("a", "k")
            self.assertEqual(None if found is None else found.number, 2)
        finally:
            board.close()

    def test_the_archive_takes_only_the_renames_after_it(self) -> None:
        self.write(
            LOG_NAME,
            RenameRecord(name="a", to="b"),
            RenameRecord(name="b", to="c"),
            RenameRecord(name="a", to="d"),
        )
        self.write(
            ARCHIVE_NAME,
            ArchivePutRecord(job=finished(1, archived_ms=5).model_copy(update={"queue": "a"})),
            ArchivePutRecord(
                job=finished(2, archived_ms=5).model_copy(update={"queue": "a"}), renames=2
            ),
            ArchivePutRecord(
                job=finished(3, archived_ms=5).model_copy(update={"queue": "b"}), renames=1
            ),
        )
        state = replay(self.dir)
        self.assertEqual({n: j.queue for n, j in state.archived.items()}, {1: "c", 2: "d", 3: "c"})

    def test_compact_folds_two_renames_and_an_old_archive_name(self) -> None:
        self.write(
            LOG_NAME,
            PutRecord(job=self.in_queue(1, "a")),
            ArchivedRecord(number=2),
            RenameRecord(name="a", to="b"),
            PutRecord(job=self.in_queue(3, "a")),
            RenameRecord(name="b", to="c"),
        )
        self.write(
            ARCHIVE_NAME,
            ArchivePutRecord(job=finished(2, archived_ms=5).model_copy(update={"queue": "a"})),
        )
        before = replay(self.dir)
        self.assertEqual(compact(self.dir), (5, 3))
        log = lines(self.dir / LOG_NAME)
        self.assertEqual(log[0], {"kind": "counter", "next_number": 4, "renames": 2})
        self.assertEqual([r["job"]["queue"] for r in log[1:]], ["c", "a"])
        self.assertNotIn("rename", [r["kind"] for r in log])
        archive = lines(self.dir / ARCHIVE_NAME)
        self.assertEqual([(r["job"]["queue"], r["renames"]) for r in archive], [("c", 2)])
        after = replay(self.dir)
        self.assertEqual((after.jobs, after.archived), (before.jobs, before.archived))
        # A kill after the archive's rewrite and before the log's: the old log still holds the
        # two renames, and the rewritten archive, stamped 2, takes neither again.
        (self.dir / LOG_NAME).unlink()
        self.write(
            LOG_NAME,
            PutRecord(job=self.in_queue(1, "a")),
            ArchivedRecord(number=2),
            RenameRecord(name="a", to="b"),
            PutRecord(job=self.in_queue(3, "a")),
            RenameRecord(name="b", to="c"),
            RenameRecord(name="c", to="e"),
        )
        self.assertEqual(replay(self.dir).archived[2].queue, "e")
        self.write(LOG_NAME, RenameRecord(name="e", to="c"))
        self.assertEqual(replay(self.dir).archived, before.archived)

    def test_a_record_after_compaction_counts_on_from_the_counter(self) -> None:
        self.write(
            LOG_NAME,
            CounterRecord(next_number=5, renames=3),
            RenameRecord(name="a", to="b"),
        )
        self.write(
            ARCHIVE_NAME,
            ArchivePutRecord(
                job=finished(1, archived_ms=5).model_copy(update={"queue": "a"}), renames=3
            ),
            ArchivePutRecord(
                job=finished(2, archived_ms=5).model_copy(update={"queue": "a"}), renames=4
            ),
        )
        state = replay(self.dir)
        self.assertEqual(state.renames, 4)
        self.assertEqual({n: j.queue for n, j in state.archived.items()}, {1: "b", 2: "a"})

    def test_verify_refuses_a_bad_rename_record(self) -> None:
        cases = [
            (
                '{"kind":"rename","name":"a b","to":"c"}',
                "record line 2: rename.name value error, queue must be",
            ),
            (
                '{"kind":"rename","name":"a","to":""}',
                "record line 2: rename.to value error, queue must be",
            ),
            ('{"kind":"rename","name":"a"}', "record line 2: rename.to field required"),
            ('{"kind":"rename","name":"a","to":"b","x":1}', "record line 2: rename.x extra inputs"),
        ]
        good = PutRecord(job=self.in_queue(1, "a")).model_dump_json()
        for line, rule in cases:
            with self.subTest(line=line):
                (self.dir / LOG_NAME).write_text(f"{good}\n{line}\n")
                code, out, err = invoke("verify", str(self.dir))
                self.assertEqual((code, out), (1, ""))
                self.assertTrue(err.startswith(f"jobq: {self.dir}: {rule}"), err)
                self.assertEqual(invoke("compact", str(self.dir))[0], 1)
                self.assertEqual(invoke("serve", str(self.dir), "--port", "0")[0], 1)

    def test_verify_refuses_an_archive_ahead_of_the_log(self) -> None:
        self.write(LOG_NAME, RenameRecord(name="a", to="b"))
        self.write(ARCHIVE_NAME, ArchivePutRecord(job=finished(1, archived_ms=5), renames=2))
        code, _, err = invoke("verify", str(self.dir))
        self.assertEqual(code, 1)
        self.assertIn("archive record j_1: renames 2 is past the log's 1", err)

    def test_verify_counts_with_the_renames_applied(self) -> None:
        self.write(
            LOG_NAME,
            PutRecord(job=self.in_queue(1, "a")),
            RenameRecord(name="a", to="b"),
            PutRecord(job=self.in_queue(1, "b", "leased")),
        )
        code, out, _ = invoke("verify", str(self.dir))
        self.assertEqual(code, 0)
        self.assertEqual(
            out,
            "1 jobs: queued 0, scheduled 0, leased 1, done 0, dead 0; next id j_2; archived 0\n",
        )
        store, state = Store.open(self.dir)
        store.close()
        self.assertEqual(state.jobs[1].queue, "b")

    def test_a_torn_rename_is_cut_and_moves_nothing(self) -> None:
        self.write(LOG_NAME, PutRecord(job=self.in_queue(1, "a")))
        whole = (self.dir / LOG_NAME).stat().st_size
        with open(self.dir / LOG_NAME, "a", encoding="utf-8") as file:
            file.write('{"kind":"rename","name":"a","to')
        store, state = Store.open(self.dir)
        store.close()
        self.assertEqual((state.jobs[1].queue, state.renames), ("a", 0))
        self.assertEqual((self.dir / LOG_NAME).stat().st_size, whole)


class ChaosOptionTest(QueueCase):
    def test_crash_every_counts_a_rename_as_one_change(self) -> None:
        self.api.close()
        self.api = self.open(options=BoardOptions(crash_every=3))
        self.create()
        self.create()
        with contextlib.redirect_stderr(io.StringIO()):
            response = self.call("POST", "/queues/emails/rename", {"to": "mail"})
        self.assertEqual((response.status, self.api.restarts), (503, 1))
        self.assertEqual(json.loads(self.call("GET", "/queues").body)["queues"][0]["name"], "mail")


if __name__ == "__main__":
    unittest.main()
