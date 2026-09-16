import unittest
from typing import ClassVar
from unittest import mock

from jobq.clock import iso_utc
from jobq.contract import ContractError
from jobq.queue import Queue
from jobq.store import replay
from support import QueueCase, body_of


class CreateAndGetTest(QueueCase):
    def test_create_is_201_with_the_job(self) -> None:
        response = self.call(
            "POST", "/jobs", {"queue": "emails", "payload": "hi", "max_tries": 3}
        )
        self.assertEqual(response.status, 201)
        job = body_of(response)
        self.assertEqual(
            list(job),
            [
                "id",
                "queue",
                "state",
                "payload",
                "tries",
                "max_tries",
                "backoff_ms",
                "created_at",
                "updated_at",
            ],
        )
        self.assertEqual((job["id"], job["state"], job["tries"]), ("j_1", "queued", 0))

    def test_create_rejects_bad_bodies_with_400(self) -> None:
        for raw in (
            b"not json",
            b"[]",
            b"",
            b'{"queue": "emails", "payload": "hi"}',
            b'{"queue": "emails", "payload": 5, "max_tries": 3}',
            b'{"queue": "no way", "payload": "hi", "max_tries": 3}',
            b'{"queue": "emails", "payload": "hi", "max_tries": 0}',
        ):
            response = self.call("POST", "/jobs", raw=raw)
            self.assertEqual(response.status, 400, raw)
            self.assertIsInstance(body_of(response)["error"], str)

    def test_get_is_200_or_404(self) -> None:
        job_id = self.create()
        self.assertEqual(self.call("GET", f"/jobs/{job_id}").status, 200)
        self.assertEqual(self.call("GET", "/jobs/j_2").status, 404)
        self.assertEqual(self.call("GET", "/jobs/garbage").status, 404)


class RoutingTest(QueueCase):
    def test_unknown_routes_are_404(self) -> None:
        for path in ("/", "/nope", "/jobs/j_1/ack/more", "/jobs/", "/queues/q"):
            self.assertEqual(self.call("GET", path).status, 404, path)

    def test_a_method_the_route_lacks_is_405_with_allow(self) -> None:
        response = self.call("PUT", "/jobs")
        self.assertEqual((response.status, response.allow), (405, "POST, GET"))
        self.assertEqual(self.call("GET", "/jobs/j_1/ack").status, 405)
        self.assertEqual(self.call("POST", "/health").status, 405)

    def test_a_missing_token_is_401_except_health(self) -> None:
        self.assertEqual(self.call("GET", "/jobs", token=None).status, 401)
        self.assertEqual(self.call("POST", "/queues/q/lease", token=None).status, 401)
        self.assertEqual(self.call("GET", "/health", token=None).status, 200)


class ListTest(QueueCase):
    def test_lists_by_id_with_optional_filters(self) -> None:
        self.create("a")
        self.create("b")
        self.create("a")
        self.call("POST", "/queues/a/lease")
        everything = body_of(self.call("GET", "/jobs"))["jobs"]
        assert isinstance(everything, list)
        self.assertEqual([job["id"] for job in everything], ["j_1", "j_2", "j_3"])
        queued_a = body_of(self.call("GET", "/jobs?queue=a&state=queued"))["jobs"]
        assert isinstance(queued_a, list)
        self.assertEqual([job["id"] for job in queued_a], ["j_3"])

    def test_bad_queries_are_400(self) -> None:
        for query in ("state=gone", "queue=no%20way", "limit=5", "state=done&state=dead"):
            self.assertEqual(self.call("GET", f"/jobs?{query}").status, 400, query)


class DeleteTest(QueueCase):
    def test_delete_statuses(self) -> None:
        self.create()
        self.create()
        self.call("POST", "/queues/emails/lease")
        self.assertEqual(self.call("DELETE", "/jobs/j_1").status, 409)
        response = self.call("DELETE", "/jobs/j_2")
        self.assertEqual((response.status, response.body), (204, b""))
        self.assertEqual(self.call("DELETE", "/jobs/j_2").status, 404)


class LeaseAckFailTest(QueueCase):
    def test_lease_is_200_then_204(self) -> None:
        self.create()
        response = self.call("POST", "/queues/emails/lease", {"lease_ms": 1000}, token="w7")
        self.assertEqual(response.status, 200)
        job = body_of(response)
        self.assertEqual((job["state"], job["worker"], job["tries"]), ("leased", "w7", 1))
        self.assertIn("lease_until", job)
        self.assertEqual(self.call("POST", "/queues/emails/lease").status, 204)

    def test_lease_ms_defaults_to_30000(self) -> None:
        self.create()
        self.call("POST", "/queues/emails/lease")
        job = self.queue.get("j_1")
        assert job is not None
        self.assertEqual(job.lease_until_ms, self.clock.ms + 30_000)

    def test_bad_lease_requests_are_400(self) -> None:
        self.create()
        for body in ({"lease_ms": 99}, {"lease_ms": 3_600_001}, {"lease_ms": "1000"}, {"x": 1}):
            self.assertEqual(self.call("POST", "/queues/emails/lease", body).status, 400, body)
        self.assertEqual(self.call("POST", "/queues/bad!/lease").status, 400)

    def test_ack_statuses(self) -> None:
        self.create()
        self.call("POST", "/queues/emails/lease", token="w1")
        self.assertEqual(self.call("POST", "/jobs/j_1/ack", token="w2").status, 409)
        response = self.call("POST", "/jobs/j_1/ack", token="w1")
        self.assertEqual((response.status, body_of(response)["state"]), (200, "done"))
        self.assertEqual(self.call("POST", "/jobs/j_1/ack", token="w1").status, 409)
        self.assertEqual(self.call("POST", "/jobs/j_5/ack").status, 404)

    def test_fail_statuses(self) -> None:
        self.create(max_tries=1)
        self.assertEqual(self.call("POST", "/jobs/j_1/fail", {"reason": "x"}).status, 409)
        self.call("POST", "/queues/emails/lease")
        self.assertEqual(self.call("POST", "/jobs/j_1/fail", {}).status, 400)
        response = self.call("POST", "/jobs/j_1/fail", {"reason": "boom"})
        self.assertEqual(response.status, 200)
        job = body_of(response)
        self.assertEqual((job["state"], job["reason"]), ("dead", "boom"))
        self.assertNotIn("worker", job)
        self.assertEqual(self.call("POST", "/jobs/j_9/fail", {"reason": "x"}).status, 404)


class HealthAndStoreTest(QueueCase):
    def test_health_counts_each_state(self) -> None:
        for _ in range(3):
            self.create(max_tries=1)
        self.create(delay_ms=60_000)
        self.call("POST", "/queues/emails/lease")
        self.call("POST", "/jobs/j_1/ack")
        self.call("POST", "/queues/emails/lease")
        self.call("POST", "/jobs/j_2/fail", {"reason": "x"})
        self.clock.advance(250)
        self.call("POST", "/queues/emails/lease")
        health = body_of(self.call("GET", "/health", token=None))
        counts = {"queued": 0, "scheduled": 1, "leased": 1, "done": 1, "dead": 1}
        self.assertEqual(health, counts | {"uptime_ms": 250})

    def test_a_store_failure_is_503_with_the_store_unchanged(self) -> None:
        self.create()
        before = replay(self.dir)
        self.ops.failing = True
        for method, path, body in (
            ("POST", "/jobs", {"queue": "emails", "payload": "b", "max_tries": 1}),
            ("POST", "/queues/emails/lease", None),
            ("DELETE", "/jobs/j_1", None),
        ):
            response = self.call(method, path, body)
            self.assertEqual(response.status, 503, path)
            self.assertIn("store unavailable", str(body_of(response)["error"]))
        self.assertEqual(replay(self.dir), before)
        self.ops.failing = False
        self.assertEqual(self.call("GET", "/jobs/j_1").status, 200)


class ScheduleTest(QueueCase):
    def test_create_with_a_delay_is_scheduled_with_run_at(self) -> None:
        body = {"queue": "emails", "payload": "hi", "max_tries": 3}
        response = self.call("POST", "/jobs", body | {"delay_ms": 1500, "backoff_ms": 200})
        self.assertEqual(response.status, 201)
        job = body_of(response)
        self.assertEqual(list(job)[-1], "run_at")
        shown = (job["state"], job["tries"], job["backoff_ms"], job["run_at"])
        self.assertEqual(shown, ("scheduled", 0, 200, iso_utc(self.clock.ms + 1500)))

    def test_create_rejects_the_old_names_and_bad_delays_with_400(self) -> None:
        base: dict[str, object] = {"queue": "emails", "payload": "hi", "max_tries": 3}
        for body in (
            {"queue": "emails", "payload": "hi", "max_attempts": 3},
            base | {"attempts": 0},
            base | {"delay_ms": -1},
            base | {"delay_ms": 86_400_001},
            base | {"delay_ms": "5"},
            base | {"delay_ms": 1.5},
            base | {"backoff_ms": -1},
            base | {"backoff_ms": 3_600_001},
            base | {"backoff_ms": None},
        ):
            response = self.call("POST", "/jobs", body)
            self.assertEqual(response.status, 400, body)
            self.assertIsInstance(body_of(response)["error"], str)
        self.assertEqual(self.call("GET", "/jobs").json(), {"jobs": []})

    def test_fail_with_backoff_is_scheduled_and_a_lease_before_run_at_is_204(self) -> None:
        self.create(backoff_ms=5000)
        self.call("POST", "/queues/emails/lease", {"lease_ms": 1000})
        job = body_of(self.call("POST", "/jobs/j_1/fail", {"reason": "later"}))
        shown = (job["state"], job["tries"], job["run_at"], job["reason"])
        self.assertEqual(shown, ("scheduled", 1, iso_utc(self.clock.ms + 5000), "later"))
        self.assertNotIn("worker", job)
        self.clock.advance(4999)
        self.assertEqual(self.call("POST", "/queues/emails/lease").status, 204)
        self.clock.advance(1)
        again = body_of(self.call("POST", "/queues/emails/lease"))
        self.assertEqual((again["id"], again["tries"]), ("j_1", 2))
        self.assertNotIn("run_at", again)

    def test_lists_scheduled_jobs(self) -> None:
        self.create("a", delay_ms=100)
        self.create("a")
        self.create("b", delay_ms=100)
        scheduled = body_of(self.call("GET", "/jobs?state=scheduled"))["jobs"]
        assert isinstance(scheduled, list)
        self.assertEqual([job["id"] for job in scheduled], ["j_1", "j_3"])
        self.clock.advance(100)
        self.assertEqual(body_of(self.call("GET", "/jobs?state=scheduled"))["jobs"], [])
        queued = body_of(self.call("GET", "/jobs?queue=a&state=queued"))["jobs"]
        assert isinstance(queued, list)
        self.assertEqual([job["id"] for job in queued], ["j_1", "j_2"])

    def test_delete_a_scheduled_job_is_204(self) -> None:
        self.create(delay_ms=100)
        self.assertEqual(self.call("DELETE", "/jobs/j_1").status, 204)

    def test_a_due_move_the_store_refuses_is_503_with_the_store_unchanged(self) -> None:
        self.create(delay_ms=100)
        self.clock.advance(100)
        before = replay(self.dir)
        self.ops.failing = True
        for method, path in (
            ("GET", "/health"),
            ("GET", "/jobs/j_1"),
            ("GET", "/jobs"),
            ("POST", "/queues/emails/lease"),
        ):
            self.assertEqual(self.call(method, path).status, 503, path)
        self.assertEqual(replay(self.dir), before)
        self.ops.failing = False
        self.assertEqual(body_of(self.call("GET", "/jobs/j_1"))["state"], "queued")


class RetryTest(QueueCase):
    def test_retry_statuses(self) -> None:
        self.create(max_tries=1)
        self.create("other", delay_ms=1000)
        self.assertEqual(self.call("POST", "/jobs/j_1/retry").status, 409)
        self.assertEqual(self.call("POST", "/jobs/j_2/retry").status, 409)
        self.call("POST", "/queues/emails/lease", token="w1")
        self.assertEqual(self.call("POST", "/jobs/j_1/retry").status, 409)
        self.call("POST", "/jobs/j_1/fail", {"reason": "boom"}, token="w1")
        response = self.call("POST", "/jobs/j_1/retry", token="w2")
        self.assertEqual(response.status, 200)
        job = body_of(response)
        self.assertEqual((job["state"], job["tries"], job["max_tries"]), ("queued", 0, 1))
        self.assertNotIn("reason", job)
        conflict = self.call("POST", "/jobs/j_1/retry")
        self.assertEqual(conflict.status, 409)
        self.assertEqual(conflict.json(), {"error": "the job is not dead"})
        again = body_of(self.call("POST", "/queues/emails/lease", token="w3"))
        self.assertEqual((again["id"], again["tries"]), ("j_1", 1))
        self.call("POST", "/jobs/j_1/ack", token="w3")
        self.assertEqual(self.call("POST", "/jobs/j_1/retry").status, 409)
        self.assertEqual(self.call("POST", "/jobs/j_9/retry").status, 404)
        self.assertEqual(self.call("POST", "/jobs/j_1/retry", token=None).status, 401)
        self.assertEqual(self.call("GET", "/jobs/j_1/retry").status, 405)

    def test_a_retry_the_store_refuses_is_503_and_the_job_stays_dead(self) -> None:
        self.create(max_tries=1)
        self.call("POST", "/queues/emails/lease")
        self.call("POST", "/jobs/j_1/fail", {"reason": "boom"})
        self.ops.failing = True
        self.assertEqual(self.call("POST", "/jobs/j_1/retry").status, 503)
        self.ops.failing = False
        self.assertEqual(body_of(self.call("GET", "/jobs/j_1"))["state"], "dead")


class QueuesTest(QueueCase):
    """`GET /queues`: every queue holding a job, by name, with its counts per state."""

    def counts(self) -> list[dict[str, object]]:
        response = self.call("GET", "/queues")
        self.assertEqual(response.status, 200, response.body)
        queues = body_of(response)["queues"]
        assert isinstance(queues, list)
        return [dict(queue) for queue in queues]

    def test_an_empty_folder_lists_no_queue(self) -> None:
        self.assertEqual(self.counts(), [])

    def test_every_queue_is_listed_by_name_with_its_states(self) -> None:
        self.create("reports")
        self.create("emails")
        self.create("emails", delay_ms=1000)
        self.create("audit", max_tries=1)
        self.call("POST", "/queues/audit/lease", token="w1")
        self.assertEqual(
            self.counts(),
            [
                {"name": "audit", "queued": 0, "scheduled": 0, "leased": 1, "done": 0, "dead": 0},
                {"name": "emails", "queued": 1, "scheduled": 1, "leased": 0, "done": 0, "dead": 0},
                {"name": "reports", "queued": 1, "scheduled": 0, "leased": 0, "done": 0, "dead": 0},
            ],
        )

    def test_a_queue_whose_last_job_is_deleted_disappears(self) -> None:
        self.create("emails")
        self.create("reports")
        self.assertEqual([queue["name"] for queue in self.counts()], ["emails", "reports"])
        self.assertEqual(self.call("DELETE", "/jobs/j_2").status, 204)
        self.assertEqual([queue["name"] for queue in self.counts()], ["emails"])

    def test_health_totals_are_the_sums_of_the_queues(self) -> None:
        self.create("emails", max_tries=1)
        self.create("reports", delay_ms=1000)
        self.create("reports")
        self.call("POST", "/queues/emails/lease", token="w1")
        self.call("POST", "/jobs/j_1/fail", {"reason": "boom"}, token="w1")
        health = body_of(self.call("GET", "/health"))
        for state in ("queued", "scheduled", "leased", "done", "dead"):
            total = sum(int(str(queue[state])) for queue in self.counts())
            self.assertEqual(health[state], total, state)

    def test_queues_takes_a_token_and_only_get(self) -> None:
        self.assertEqual(self.call("GET", "/queues", token=None).status, 401)
        response = self.call("POST", "/queues")
        self.assertEqual((response.status, response.allow), (405, "GET"))

    def test_a_look_the_store_refuses_makes_queues_a_503(self) -> None:
        self.create("emails", delay_ms=100)
        self.clock.advance(100)
        self.ops.failing = True
        self.assertEqual(self.call("GET", "/queues").status, 503)
        self.ops.failing = False
        self.assertEqual(self.counts()[0]["queued"], 1)


class UnwritableFolderTest(QueueCase):
    """The spec's test: read-only folder, a write is 503, a read is 200, writable again, 2xx.

    A folder made read-only while the log is open does not stop a write on POSIX: the mode is
    read when a file is opened, not when it is written. So the folder is really made read-only
    and the store's refusal is injected at the `FileOps` boundary the simulation uses.
    """

    BODY: ClassVar[dict[str, object]] = {
        "queue": "emails",
        "payload": "while read-only",
        "max_tries": 1,
    }

    def test_writes_are_503_reads_are_200_and_writes_resume_by_themselves(self) -> None:
        job_id = self.create()
        before = replay(self.dir)
        health = body_of(self.call("GET", "/health"))
        mode = self.dir.stat().st_mode
        self.dir.chmod(0o500)
        self.ops.failing = True
        try:
            for _ in range(3):
                self.assertEqual(self.call("POST", "/jobs", self.BODY).status, 503)
            self.assertEqual(self.call("GET", f"/jobs/{job_id}").status, 200)
            self.assertEqual(body_of(self.call("GET", "/health")), health)
            self.assertEqual(replay(self.dir), before)
        finally:
            self.ops.failing = False
            self.dir.chmod(mode)
        created = self.call("POST", "/jobs", self.BODY)
        self.assertEqual(created.status, 201)
        self.assertEqual(list(replay(self.dir).jobs), [1, 2])
        self.assertEqual(body_of(self.call("GET", "/health"))["queued"], 2)


class RequestFailureTest(QueueCase):
    """A failure inside one request costs that request and nothing else."""

    def test_a_store_that_cannot_be_written_refuses_writes_and_still_answers_reads(self) -> None:
        job_id = self.create()
        before = replay(self.dir)
        self.ops.failing = True
        for method, path, body in (
            ("POST", "/jobs", {"queue": "emails", "payload": "p", "max_tries": 1}),
            ("POST", "/queues/emails/lease", None),
            ("DELETE", f"/jobs/{job_id}", None),
        ):
            self.assertEqual(self.call(method, path, body).status, 503, path)
        for path in ("/health", "/queues", "/jobs", f"/jobs/{job_id}"):
            self.assertEqual(self.call("GET", path).status, 200, path)
        self.assertEqual(replay(self.dir), before)
        self.ops.failing = False
        again = self.call("POST", "/jobs", {"queue": "e", "payload": "p", "max_tries": 1})
        self.assertEqual(again.status, 201)
        self.assertEqual(body_of(self.call("GET", f"/jobs/{job_id}"))["state"], "queued")

    def test_a_bad_request_is_still_a_400_while_the_store_cannot_be_written(self) -> None:
        self.ops.failing = True
        self.assertEqual(self.call("POST", "/jobs", {"queue": "e"}).status, 400)
        self.assertEqual(self.call("GET", "/jobs/j_9").status, 404)

    def test_a_broken_contract_is_a_503_and_the_next_request_is_answered(self) -> None:
        job_id = self.create()
        broken = mock.patch.object(Queue, "get", side_effect=ContractError("invariant a bug"))
        with broken:
            response = self.call("GET", f"/jobs/{job_id}")
        refused = {"error": "the request could not be completed"}
        self.assertEqual((response.status, response.json()), (503, refused))
        self.assertEqual(body_of(self.call("GET", f"/jobs/{job_id}"))["state"], "queued")

    def test_anything_unexpected_is_a_503_that_leaves_the_job_alone(self) -> None:
        job_id = self.create()
        before = replay(self.dir)
        surprise = mock.patch.object(Queue, "lease", side_effect=ZeroDivisionError("surprise"))
        with surprise:
            self.assertEqual(self.call("POST", "/queues/emails/lease").status, 503)
        self.assertEqual(replay(self.dir), before)
        leased = body_of(self.call("POST", "/queues/emails/lease"))
        self.assertEqual((leased["id"], leased["state"]), (job_id, "leased"))


if __name__ == "__main__":
    unittest.main()
