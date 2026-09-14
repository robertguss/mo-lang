import json
import unittest

from pydantic import ValidationError

from jobq.api import CreateJob, FailJob, JobView, LeaseJob, ListJobs, bearer_token
from jobq.model import (
    MAX_PAYLOAD_BYTES,
    Job,
    JobState,
    is_job_id,
    is_queue_name,
    is_worker,
    iso_ms,
    payload_problem,
)

START_MS = 1_767_225_600_000


def job(**changes: object) -> Job:
    fields: dict[str, object] = {
        "id": "j_1",
        "queue": "emails",
        "state": JobState.QUEUED,
        "payload": "hi",
        "attempts": 0,
        "max_attempts": 3,
        "created_at": START_MS,
        "updated_at": START_MS,
    }
    fields.update(changes)
    return Job.model_validate(fields)


class JobShapeTest(unittest.TestCase):
    def test_a_queued_job_has_the_eight_fields_in_order(self) -> None:
        shape = json.loads(JobView.of(job()).model_dump_json(exclude_none=True))
        self.assertEqual(
            list(shape),
            [
                "id",
                "queue",
                "state",
                "payload",
                "attempts",
                "max_attempts",
                "created_at",
                "updated_at",
            ],
        )
        self.assertEqual(shape["created_at"], "2026-01-01T00:00:00.000Z")
        self.assertEqual(shape["state"], "queued")

    def test_a_leased_job_adds_worker_and_lease_until(self) -> None:
        leased = job(state=JobState.LEASED, attempts=1, worker="w1", lease_until=START_MS + 30_000)
        shape = json.loads(JobView.of(leased).model_dump_json(exclude_none=True))
        self.assertEqual(shape["worker"], "w1")
        self.assertEqual(shape["lease_until"], "2026-01-01T00:00:30.000Z")
        self.assertNotIn("reason", shape)

    def test_a_failed_job_adds_reason(self) -> None:
        failed = job(attempts=1, reason="smtp down")
        shape = json.loads(JobView.of(failed).model_dump_json(exclude_none=True))
        self.assertEqual(shape["reason"], "smtp down")
        self.assertNotIn("worker", shape)

    def test_iso_ms_is_utc_with_milliseconds(self) -> None:
        self.assertEqual(iso_ms(START_MS + 1_234), "2026-01-01T00:00:01.234Z")
        self.assertEqual(iso_ms(0), "1970-01-01T00:00:00.000Z")


class CreateJobShapeTest(unittest.TestCase):
    def parse(self, text: str) -> CreateJob:
        return CreateJob.model_validate_json(text)

    def test_accepts_the_spec_example(self) -> None:
        created = self.parse('{"queue": "emails", "payload": "...", "max_attempts": 3}')
        self.assertEqual(
            (created.queue, created.payload, created.max_attempts), ("emails", "...", 3)
        )

    def test_rejects(self) -> None:
        cases = [
            "",
            "not json",
            "[]",
            '{"payload": "x", "max_attempts": 3}',
            '{"queue": "q", "max_attempts": 3}',
            '{"queue": "q", "payload": "x"}',
            '{"queue": "q", "payload": "x", "max_attempts": "3"}',
            '{"queue": "q", "payload": "x", "max_attempts": 3.0}',
            '{"queue": "q", "payload": "x", "max_attempts": true}',
            '{"queue": "q", "payload": 7, "max_attempts": 3}',
            '{"queue": "q", "payload": "x", "max_attempts": 3, "priority": 1}',
            '{"queue": "", "payload": "x", "max_attempts": 3}',
            '{"queue": "q", "payload": "x", "max_attempts": 0}',
            '{"queue": "q", "payload": "x", "max_attempts": 101}',
            '{"queue": "q", "payload": "a\\u0000b", "max_attempts": 3}',
        ]
        for text in cases:
            with self.subTest(text=text), self.assertRaises(ValidationError):
                self.parse(text)


class OtherInputShapesTest(unittest.TestCase):
    def test_lease_ms_defaults_to_30000(self) -> None:
        self.assertEqual(LeaseJob.model_validate_json("{}").lease_ms, 30_000)

    def test_lease_ms_bounds(self) -> None:
        self.assertEqual(LeaseJob.model_validate_json('{"lease_ms": 100}').lease_ms, 100)
        self.assertEqual(LeaseJob.model_validate_json('{"lease_ms": 3600000}').lease_ms, 3_600_000)
        for text in ('{"lease_ms": 99}', '{"lease_ms": 3600001}', '{"lease_ms": "1000"}'):
            with self.subTest(text=text), self.assertRaises(ValidationError):
                LeaseJob.model_validate_json(text)

    def test_fail_requires_a_reason(self) -> None:
        self.assertEqual(FailJob.model_validate_json('{"reason": "boom"}').reason, "boom")
        for text in ("{}", '{"reason": 1}', '{"reason": "a\\tb"}'):
            with self.subTest(text=text), self.assertRaises(ValidationError):
                FailJob.model_validate_json(text)

    def test_list_filters(self) -> None:
        self.assertEqual(ListJobs.model_validate_json('{"state": "dead"}').state, JobState.DEAD)
        for text in ('{"state": "gone"}', '{"queue": "a b"}', '{"limit": "5"}'):
            with self.subTest(text=text), self.assertRaises(ValidationError):
                ListJobs.model_validate_json(text)


class RulesTest(unittest.TestCase):
    def test_queue_names(self) -> None:
        for name in ("a", "emails", "A-z_0-9", "q" * 64):
            self.assertTrue(is_queue_name(name), name)
        for name in ("", "q" * 65, "a b", "é", "a/b", "a.b"):
            self.assertFalse(is_queue_name(name), name)

    def test_payload_is_at_most_60_kib_of_utf8(self) -> None:
        self.assertIsNone(payload_problem(""))
        self.assertIsNone(payload_problem("x" * MAX_PAYLOAD_BYTES))
        self.assertIsNotNone(payload_problem("x" * (MAX_PAYLOAD_BYTES + 1)))
        self.assertIsNotNone(payload_problem("é" * (MAX_PAYLOAD_BYTES // 2 + 1)))

    def test_payload_allows_newline_and_no_other_control(self) -> None:
        self.assertIsNone(payload_problem("line one\nline two ünïcode 🚀"))
        for control in ("\x00", "\t", "\r", "\x1b", "\x7f", "\x85"):
            self.assertIsNotNone(payload_problem(f"a{control}b"), repr(control))

    def test_payload_must_encode_as_utf8(self) -> None:
        self.assertIsNotNone(payload_problem("\ud800"))

    def test_job_ids(self) -> None:
        self.assertTrue(is_job_id("j_1"))
        self.assertTrue(is_job_id("j_123456789"))
        for text in ("j_0", "j_01", "j_", "1", "j_1a", "J_1", "j_" + "9" * 19):
            self.assertFalse(is_job_id(text), text)

    def test_workers_and_bearer_tokens(self) -> None:
        self.assertTrue(is_worker("worker-7"))
        self.assertFalse(is_worker(""))
        self.assertFalse(is_worker("a b"))
        self.assertEqual(bearer_token("Bearer w1"), "w1")
        self.assertEqual(bearer_token("bearer w1"), "w1")
        for header in (None, "", "Bearer", "Bearer ", "Basic w1", "Bearer a b", "Bearer  w1"):
            self.assertIsNone(bearer_token(header), header)


if __name__ == "__main__":
    unittest.main()
