import unittest

from support import QueueCase, body_of

from jobq.store import replay


class CreateAndGetTest(QueueCase):
    def test_create_is_201_with_the_job(self) -> None:
        response = self.call("POST", "/jobs", {"queue": "emails", "payload": "hi", "max_attempts": 3})
        self.assertEqual(response.status, 201)
        job = body_of(response)
        self.assertEqual(
            list(job),
            ["id", "queue", "state", "payload", "attempts", "max_attempts", "created_at", "updated_at"],
        )
        self.assertEqual((job["id"], job["state"], job["attempts"]), ("j_1", "queued", 0))

    def test_create_rejects_bad_bodies_with_400(self) -> None:
        for raw in (
            b"not json",
            b"[]",
            b"",
            b'{"queue": "emails", "payload": "hi"}',
            b'{"queue": "emails", "payload": 5, "max_attempts": 3}',
            b'{"queue": "no way", "payload": "hi", "max_attempts": 3}',
            b'{"queue": "emails", "payload": "hi", "max_attempts": 0}',
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
        self.assertEqual((job["state"], job["worker"], job["attempts"]), ("leased", "w7", 1))
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
        self.create(max_attempts=1)
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
            self.create(max_attempts=1)
        self.call("POST", "/queues/emails/lease")
        self.call("POST", "/jobs/j_1/ack")
        self.call("POST", "/queues/emails/lease")
        self.call("POST", "/jobs/j_2/fail", {"reason": "x"})
        self.clock.advance(250)
        self.call("POST", "/queues/emails/lease")
        health = body_of(self.call("GET", "/health", token=None))
        self.assertEqual(
            health, {"queued": 0, "leased": 1, "done": 1, "dead": 1, "uptime_ms": 250}
        )

    def test_a_store_failure_is_503_with_the_store_unchanged(self) -> None:
        self.create()
        before = replay(self.dir)
        self.ops.failing = True
        for method, path, body in (
            ("POST", "/jobs", {"queue": "emails", "payload": "b", "max_attempts": 1}),
            ("POST", "/queues/emails/lease", None),
            ("DELETE", "/jobs/j_1", None),
        ):
            response = self.call(method, path, body)
            self.assertEqual(response.status, 503, path)
            self.assertIn("store unavailable", str(body_of(response)["error"]))
        self.assertEqual(replay(self.dir), before)
        self.ops.failing = False
        self.assertEqual(self.call("GET", "/jobs/j_1").status, 200)


if __name__ == "__main__":
    unittest.main()
