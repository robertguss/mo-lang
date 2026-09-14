import json
import random
import unittest

from jobq.model import MAX_PAYLOAD_BYTES
from tests.support import Rig, body_of

CREATE = {"queue": "emails", "payload": "...", "max_attempts": 3}


class RouteTest(unittest.TestCase):
    def setUp(self) -> None:
        self.rig = Rig()

    def test_create_is_201_with_the_job(self) -> None:
        response = self.rig.call("POST", "/jobs", body=CREATE)
        self.assertEqual(response.status, 201)
        self.assertIn(("content-type", "application/json"), response.headers)
        job = body_of(response)
        self.assertEqual((job["id"], job["state"], job["attempts"]), ("j_1", "queued", 0))
        self.assertEqual(job["created_at"], "2026-01-01T00:00:00.000Z")

    def test_get_is_200_or_404(self) -> None:
        job_id = self.rig.create()
        self.assertEqual(body_of(self.rig.call("GET", f"/jobs/{job_id}"))["id"], job_id)
        for path in ("/jobs/j_2", "/jobs/nope", "/jobs/j_0"):
            self.assertEqual(self.rig.call("GET", path).status, 404, path)

    def test_list_is_by_id_with_either_filter_optional(self) -> None:
        for queue in ("a", "b", "a"):
            self.rig.create(queue=queue)
        self.rig.call("POST", "/queues/a/lease")
        cases = {
            "/jobs": ["j_1", "j_2", "j_3"],
            "/jobs?queue=a": ["j_1", "j_3"],
            "/jobs?state=leased": ["j_1"],
            "/jobs?queue=a&state=queued": ["j_3"],
            "/jobs?queue=c": [],
        }
        for path, ids in cases.items():
            response = self.rig.call("GET", path)
            with self.subTest(path=path):
                self.assertEqual(response.status, 200)
                self.assertEqual([job["id"] for job in body_of(response)["jobs"]], ids)

    def test_list_rejects_bad_filters(self) -> None:
        for path in ("/jobs?state=gone", "/jobs?queue=", "/jobs?queue=a&queue=b", "/jobs?page=2"):
            self.assertEqual(self.rig.call("GET", path).status, 400, path)

    def test_delete_is_204_409_or_404(self) -> None:
        first, second = self.rig.create(), self.rig.create()
        self.assertEqual(self.rig.call("POST", "/queues/emails/lease").status, 200)
        self.assertEqual(self.rig.call("DELETE", f"/jobs/{first}").status, 409)
        response = self.rig.call("DELETE", f"/jobs/{second}")
        self.assertEqual((response.status, response.body), (204, b""))
        self.assertEqual(self.rig.call("DELETE", f"/jobs/{second}").status, 404)

    def test_lease_is_200_with_the_default_lease_or_204(self) -> None:
        job_id = self.rig.create()
        response = self.rig.call("POST", "/queues/emails/lease", token="worker-7")
        job = body_of(response)
        self.assertEqual((response.status, job["id"], job["worker"]), (200, job_id, "worker-7"))
        self.assertEqual(job["lease_until"], "2026-01-01T00:00:30.000Z")
        self.assertEqual(self.rig.call("POST", "/queues/emails/lease").status, 204)
        self.assertEqual(self.rig.call("POST", "/queues/unused/lease").status, 204)

    def test_lease_rejects_bad_lease_ms_and_queue_names(self) -> None:
        self.rig.create()
        for body in ({"lease_ms": 99}, {"lease_ms": 3_600_001}, {"lease_ms": "5"}, {"ms": 1}):
            response = self.rig.call("POST", "/queues/emails/lease", body=body)
            self.assertEqual(response.status, 400, body)
        self.assertEqual(self.rig.call("POST", "/queues/bad name/lease").status, 400)
        self.assertEqual(self.rig.queue.snapshot()["j_1"].state, "queued")

    def test_ack_is_200_409_or_404(self) -> None:
        job_id = self.rig.create()
        self.assertEqual(self.rig.call("POST", f"/jobs/{job_id}/ack").status, 409)
        self.rig.call("POST", "/queues/emails/lease", token="w1")
        self.assertEqual(self.rig.call("POST", f"/jobs/{job_id}/ack", token="w2").status, 409)
        response = self.rig.call("POST", f"/jobs/{job_id}/ack", token="w1")
        self.assertEqual((response.status, body_of(response)["state"]), (200, "done"))
        self.assertNotIn("worker", body_of(response))
        self.assertEqual(self.rig.call("POST", "/jobs/j_9/ack").status, 404)

    def test_fail_is_200_409_or_404_and_needs_a_reason(self) -> None:
        job_id = self.rig.create()
        self.rig.call("POST", "/queues/emails/lease")
        self.assertEqual(self.rig.call("POST", f"/jobs/{job_id}/fail").status, 400)
        response = self.rig.call("POST", f"/jobs/{job_id}/fail", body={"reason": "smtp down"})
        job = body_of(response)
        self.assertEqual(
            (response.status, job["state"], job["reason"]), (200, "queued", "smtp down")
        )
        self.assertEqual(
            self.rig.call("POST", f"/jobs/{job_id}/fail", body={"reason": "x"}).status, 409
        )
        self.assertEqual(self.rig.call("POST", "/jobs/j_9/fail", body={"reason": "x"}).status, 404)

    def test_health_needs_no_token(self) -> None:
        self.rig.create()
        response = self.rig.call("GET", "/health", token=None)
        self.assertEqual(response.status, 200)
        self.assertEqual(
            body_of(response), {"queued": 1, "leased": 0, "done": 0, "dead": 0, "uptime_ms": 0}
        )

    def test_every_other_route_needs_a_bearer_token(self) -> None:
        routes = [
            ("POST", "/jobs"),
            ("GET", "/jobs"),
            ("GET", "/jobs/j_1"),
            ("DELETE", "/jobs/j_1"),
            ("POST", "/queues/emails/lease"),
            ("POST", "/jobs/j_1/ack"),
            ("POST", "/jobs/j_1/fail"),
        ]
        for method, path in routes:
            for headers in ({}, {"authorization": ""}, {"authorization": "Bearer "}):
                from jobq.api import Request, respond

                response = respond(self.rig.queue, Request(method, path, headers, b"{}"))
                with self.subTest(method=method, path=path, headers=headers):
                    self.assertEqual(response.status, 401)
        self.assertEqual(self.rig.queue.snapshot(), {})

    def test_a_method_the_route_lacks_is_405_with_allow(self) -> None:
        response = self.rig.call("PUT", "/jobs")
        self.assertEqual(response.status, 405)
        self.assertIn(("allow", "POST, GET"), response.headers)
        self.assertEqual(self.rig.call("POST", "/health").status, 405)
        self.assertEqual(self.rig.call("GET", "/jobs/j_1/ack").status, 405)

    def test_an_unknown_route_is_404(self) -> None:
        for path in ("/", "/nowhere", "/jobs/j_1/retry", "/queues/emails", "jobs"):
            self.assertEqual(self.rig.call("GET", path).status, 404, path)

    def test_a_body_that_is_not_json_or_the_wrong_shape_is_400(self) -> None:
        for raw in (b"", b"not json", b"[1]", b'{"queue": "emails"}', b"\xff\xfe"):
            response = self.rig.call("POST", "/jobs", raw=raw)
            with self.subTest(raw=raw):
                self.assertEqual(response.status, 400)
                self.assertIsInstance(body_of(response)["error"], str)

    def test_a_503_when_the_store_fails_changes_nothing(self) -> None:
        self.rig.create()
        before = (self.rig.queue.snapshot(), self.rig.durable_log())
        self.rig.faults.rate = 1.0
        for method, path, body in (
            ("POST", "/jobs", CREATE),
            ("POST", "/queues/emails/lease", None),
            ("DELETE", "/jobs/j_1", None),
        ):
            response = self.rig.call(method, path, body=body)
            self.assertEqual(response.status, 503, path)
        self.assertEqual(self.rig.call("GET", "/jobs/j_1").status, 200)
        self.assertEqual((self.rig.queue.snapshot(), self.rig.durable_log()), before)


def random_payload(rng: random.Random) -> str:
    """Any valid payload: code points that are not surrogates or controls, `\\n` allowed."""
    size = rng.choice([0, 1, rng.randint(0, 64), rng.randint(0, 2_000)])
    chars: list[str] = []
    while len(chars) < size:
        point = rng.choice([rng.randint(0x20, 0x7E), rng.randint(0xA0, 0x10FFFF), 0x0A, 0x22, 0x5C])
        if 0xD800 <= point <= 0xDFFF:
            continue
        chars.append(chr(point))
    return "".join(chars)


class RoundTripPropertyTest(unittest.TestCase):
    def test_create_then_get_round_trips_any_valid_payload(self) -> None:
        rig = Rig()
        rng = random.Random(2026)
        payloads = [random_payload(rng) for _ in range(300)]
        payloads += ["x" * MAX_PAYLOAD_BYTES, "é" * (MAX_PAYLOAD_BYTES // 2), "🚀" * 15_360]
        for payload in payloads:
            body = json.dumps(
                {"queue": "q", "payload": payload, "max_attempts": 1},
                ensure_ascii=rng.random() < 0.5,
            )
            created = rig.call("POST", "/jobs", raw=body.encode())
            with self.subTest(size=len(payload)):
                self.assertEqual(created.status, 201)
                fetched = rig.call("GET", f"/jobs/{body_of(created)['id']}")
                self.assertEqual(body_of(fetched)["payload"], payload)
        replayed = rig.restart().snapshot()
        self.assertEqual([job.payload for job in replayed.values()], payloads)


if __name__ == "__main__":
    unittest.main()
