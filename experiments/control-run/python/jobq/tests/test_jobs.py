import json
import unittest

from pydantic import ValidationError

from jobq.clock import iso_utc
from jobq.jobs import (
    MAX_PAYLOAD_BYTES,
    CreateJob,
    FailRequest,
    Job,
    JobOut,
    LeaseRequest,
    ListQuery,
    parse_job_id,
)


def create(**fields: object) -> CreateJob:
    body = {"queue": "emails", "payload": "hi", "max_attempts": 3} | fields
    return CreateJob.model_validate_json(json.dumps(body))


class CreateJobTest(unittest.TestCase):
    def test_a_valid_body(self) -> None:
        self.assertEqual(create(), CreateJob(queue="emails", payload="hi", max_attempts=3))

    def test_queue_names(self) -> None:
        for name in ("a", "A-z_09", "q" * 64):
            self.assertEqual(create(queue=name).queue, name)

    def test_rejects_a_bad_queue_name(self) -> None:
        for name in ("", "q" * 65, "a b", "a/b", "café", "a.b"):
            with self.assertRaises(ValidationError, msg=name):
                create(queue=name)

    def test_payload_up_to_60_kib_of_utf8(self) -> None:
        self.assertEqual(len(create(payload="x" * MAX_PAYLOAD_BYTES).payload), MAX_PAYLOAD_BYTES)
        self.assertEqual(create(payload="").payload, "")
        self.assertEqual(create(payload="line\nline").payload, "line\nline")

    def test_rejects_a_payload_over_60_kib(self) -> None:
        with self.assertRaises(ValidationError):
            create(payload="x" * (MAX_PAYLOAD_BYTES + 1))
        with self.assertRaises(ValidationError):
            create(payload="é" * (MAX_PAYLOAD_BYTES // 2 + 1))  # counted in bytes

    def test_rejects_control_characters_but_newline(self) -> None:
        for char in ("\t", "\r", "\x00", "\x7f", "\x85"):
            with self.assertRaises(ValidationError, msg=repr(char)):
                create(payload=f"a{char}b")

    def test_rejects_a_payload_that_is_not_utf8(self) -> None:
        with self.assertRaises(ValidationError):
            CreateJob.model_validate_json(
                b'{"queue": "q", "payload": "\\ud800", "max_attempts": 1}'
            )

    def test_max_attempts_bounds(self) -> None:
        self.assertEqual(create(max_attempts=1).max_attempts, 1)
        self.assertEqual(create(max_attempts=100).max_attempts, 100)

    def test_rejects_max_attempts_outside_1_to_100_or_not_an_integer(self) -> None:
        for value in (0, 101, -1, "3", 3.0, True, None):
            with self.assertRaises(ValidationError, msg=repr(value)):
                create(max_attempts=value)

    def test_rejects_a_missing_or_extra_field(self) -> None:
        with self.assertRaises(ValidationError):
            CreateJob.model_validate_json('{"queue": "q", "payload": ""}')
        with self.assertRaises(ValidationError):
            create(priority=1)


class LeaseRequestTest(unittest.TestCase):
    def test_defaults_to_30_seconds(self) -> None:
        self.assertEqual(LeaseRequest.model_validate_json("{}").lease_ms, 30_000)

    def test_bounds(self) -> None:
        for value in (100, 3_600_000):
            self.assertEqual(LeaseRequest.model_validate({"lease_ms": value}).lease_ms, value)

    def test_rejects_lease_ms_outside_bounds(self) -> None:
        for value in (99, 3_600_001, 0, "30000", 1000.5):
            with self.assertRaises(ValidationError, msg=repr(value)):
                LeaseRequest.model_validate_json(json.dumps({"lease_ms": value}))


class OtherShapesTest(unittest.TestCase):
    def test_fail_needs_a_reason(self) -> None:
        self.assertEqual(FailRequest.model_validate_json('{"reason": "x"}').reason, "x")
        with self.assertRaises(ValidationError):
            FailRequest.model_validate_json("{}")

    def test_list_query(self) -> None:
        self.assertEqual(ListQuery.model_validate({"state": "dead"}).state, "dead")
        with self.assertRaises(ValidationError):
            ListQuery.model_validate({"state": "gone"})
        with self.assertRaises(ValidationError):
            ListQuery.model_validate({"limit": "5"})

    def test_parse_job_id(self) -> None:
        self.assertEqual(parse_job_id("j_1"), 1)
        self.assertEqual(parse_job_id("j_120"), 120)
        for text in ("j_0", "j_01", "1", "j_", "J_1", "j_1x", "j_" + "9" * 19):
            self.assertIsNone(parse_job_id(text), text)

    def test_iso_utc(self) -> None:
        self.assertEqual(iso_utc(0), "1970-01-01T00:00:00.000Z")
        self.assertEqual(iso_utc(1_789_000_000_123), "2026-09-10T00:26:40.123Z")


class JobOutTest(unittest.TestCase):
    BASE = Job(
        number=7,
        queue="emails",
        state="queued",
        payload="hi",
        attempts=0,
        max_attempts=3,
        created_ms=1000,
        updated_ms=2000,
    )

    def test_a_queued_job(self) -> None:
        self.assertEqual(
            json.loads(JobOut.of(self.BASE).to_json()),
            {
                "id": "j_7",
                "queue": "emails",
                "state": "queued",
                "payload": "hi",
                "attempts": 0,
                "max_attempts": 3,
                "created_at": "1970-01-01T00:00:01.000Z",
                "updated_at": "1970-01-01T00:00:02.000Z",
            },
        )

    def test_a_leased_job_adds_worker_and_lease_until(self) -> None:
        leased = self.BASE.model_copy(
            update={"state": "leased", "attempts": 1, "worker": "w1", "lease_until_ms": 5000}
        )
        out = json.loads(JobOut.of(leased).to_json())
        self.assertEqual((out["worker"], out["lease_until"]), ("w1", "1970-01-01T00:00:05.000Z"))
        self.assertNotIn("reason", out)

    def test_a_failed_job_adds_reason(self) -> None:
        failed = self.BASE.model_copy(update={"attempts": 1, "reason": "boom"})
        out = json.loads(JobOut.of(failed).to_json())
        self.assertEqual(out["reason"], "boom")
        self.assertNotIn("worker", out)
        self.assertNotIn("lease_until", out)


if __name__ == "__main__":
    unittest.main()
