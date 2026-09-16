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
    job_problem,
    parse_job_id,
)


def create(**fields: object) -> CreateJob:
    body = {"queue": "emails", "payload": "hi", "max_tries": 3} | fields
    return CreateJob.model_validate_json(json.dumps(body))


class CreateJobTest(unittest.TestCase):
    def test_a_valid_body(self) -> None:
        self.assertEqual(create(), CreateJob(queue="emails", payload="hi", max_tries=3))

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
                b'{"queue": "q", "payload": "\\ud800", "max_tries": 1}'
            )

    def test_max_tries_bounds(self) -> None:
        self.assertEqual(create(max_tries=1).max_tries, 1)
        self.assertEqual(create(max_tries=100).max_tries, 100)

    def test_rejects_max_tries_outside_1_to_100_or_not_an_integer(self) -> None:
        for value in (0, 101, -1, "3", 3.0, True, None):
            with self.assertRaises(ValidationError, msg=repr(value)):
                create(max_tries=value)

    def test_rejects_a_missing_or_extra_field(self) -> None:
        with self.assertRaises(ValidationError):
            CreateJob.model_validate_json('{"queue": "q", "payload": ""}')
        with self.assertRaises(ValidationError):
            create(priority=1)

    def test_delay_ms_and_backoff_ms_default_to_0(self) -> None:
        self.assertEqual((create().delay_ms, create().backoff_ms), (0, 0))

    def test_delay_ms_and_backoff_ms_bounds(self) -> None:
        self.assertEqual(create(delay_ms=86_400_000).delay_ms, 86_400_000)
        self.assertEqual(create(backoff_ms=3_600_000).backoff_ms, 3_600_000)

    def test_rejects_delay_ms_or_backoff_ms_out_of_range_or_not_an_integer(self) -> None:
        for field, top in (("delay_ms", 86_400_000), ("backoff_ms", 3_600_000)):
            for value in (-1, top + 1, "0", 1.5, 0.0, True, None):
                with self.assertRaises(ValidationError, msg=f"{field}={value!r}"):
                    create(**{field: value})

    def test_rejects_the_old_names(self) -> None:
        with self.assertRaises(ValidationError):
            CreateJob.model_validate_json('{"queue": "q", "payload": "", "max_attempts": 3}')
        with self.assertRaises(ValidationError):
            create(attempts=0)


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
        self.assertEqual(ListQuery.model_validate({"state": "scheduled"}).state, "scheduled")
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
        tries=0,
        max_tries=3,
        backoff_ms=0,
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
                "tries": 0,
                "max_tries": 3,
                "backoff_ms": 0,
                "created_at": "1970-01-01T00:00:01.000Z",
                "updated_at": "1970-01-01T00:00:02.000Z",
            },
        )

    def test_a_leased_job_adds_worker_and_lease_until(self) -> None:
        leased = self.BASE.model_copy(
            update={"state": "leased", "tries": 1, "worker": "w1", "lease_until_ms": 5000}
        )
        out = json.loads(JobOut.of(leased).to_json())
        self.assertEqual((out["worker"], out["lease_until"]), ("w1", "1970-01-01T00:00:05.000Z"))
        self.assertNotIn("reason", out)

    def test_a_failed_job_adds_reason(self) -> None:
        failed = self.BASE.model_copy(update={"tries": 1, "reason": "boom"})
        out = json.loads(JobOut.of(failed).to_json())
        self.assertEqual(out["reason"], "boom")
        self.assertNotIn("worker", out)
        self.assertNotIn("lease_until", out)

    def test_a_scheduled_job_adds_run_at_after_the_fixed_fields(self) -> None:
        scheduled = self.BASE.model_copy(
            update={"state": "scheduled", "backoff_ms": 500, "run_at_ms": 9000, "reason": "r"}
        )
        out = json.loads(JobOut.of(scheduled).to_json())
        self.assertEqual(
            list(out),
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
                "run_at",
                "reason",
            ],
        )
        self.assertEqual((out["run_at"], out["backoff_ms"]), ("1970-01-01T00:00:09.000Z", 500))


WELL_FORMED: dict[str, dict[str, object]] = {
    "queued": {"tries": 0},
    "scheduled": {"tries": 1, "run_at_ms": 9000},
    "leased": {"tries": 1, "worker": "w1", "lease_until_ms": 9000},
    "done": {"tries": 3},
    "dead": {"tries": 3},
}


class WellFormedTest(unittest.TestCase):
    """`job_problem`: the rule a record must meet in each state, one test per state."""

    BASE = Job.model_validate(
        {
            "number": 7,
            "queue": "emails",
            "state": "queued",
            "payload": "hi",
            "tries": 0,
            "max_tries": 3,
            "backoff_ms": 0,
            "created_ms": 1000,
            "updated_ms": 2000,
        }
    )

    def job(self, state: str, **fields: object) -> Job:
        return self.BASE.model_copy(update={"state": state} | WELL_FORMED[state] | fields)

    def assertWellFormed(self, state: str, **fields: object) -> None:
        self.assertIsNone(job_problem(self.job(state, **fields)), (state, fields))

    def assertBreaks(self, rule: str, state: str, **fields: object) -> None:
        self.assertEqual(job_problem(self.job(state, **fields)), rule, (state, fields))

    def test_a_queued_job_has_tries_left_and_none_of_the_three_fields(self) -> None:
        self.assertWellFormed("queued")
        self.assertWellFormed("queued", tries=2)
        self.assertBreaks("a queued job has tries below max_tries", "queued", tries=3)
        self.assertBreaks("a queued job has no run_at", "queued", run_at_ms=9000)
        self.assertBreaks("a queued job has no worker", "queued", worker="w1")
        self.assertBreaks("a queued job has no lease_until", "queued", lease_until_ms=9000)

    def test_a_scheduled_job_has_tries_left_and_a_run_at_alone(self) -> None:
        self.assertWellFormed("scheduled")
        self.assertWellFormed("scheduled", tries=0)
        self.assertBreaks("a scheduled job has tries below max_tries", "scheduled", tries=3)
        self.assertBreaks("a scheduled job has a run_at", "scheduled", run_at_ms=None)
        self.assertBreaks("a scheduled job has no worker", "scheduled", worker="w1")
        self.assertBreaks(
            "a scheduled job has no lease_until", "scheduled", lease_until_ms=9000
        )

    def test_a_leased_job_has_a_try_a_worker_and_a_lease_until(self) -> None:
        self.assertWellFormed("leased")
        self.assertWellFormed("leased", tries=3)
        self.assertBreaks("a leased job has 1 to max_tries tries", "leased", tries=0)
        self.assertBreaks("a leased job has no run_at", "leased", run_at_ms=9000)
        self.assertBreaks("a leased job has a worker", "leased", worker=None)
        self.assertBreaks("a leased job has a lease_until", "leased", lease_until_ms=None)

    def test_a_done_job_has_a_try_and_none_of_the_three_fields(self) -> None:
        self.assertWellFormed("done")
        self.assertWellFormed("done", tries=1)
        self.assertBreaks("a done job has 1 to max_tries tries", "done", tries=0)
        self.assertBreaks("a done job has no run_at", "done", run_at_ms=9000)
        self.assertBreaks("a done job has no worker", "done", worker="w1")
        self.assertBreaks("a done job has no lease_until", "done", lease_until_ms=9000)

    def test_a_dead_job_has_a_try_and_none_of_the_three_fields(self) -> None:
        self.assertWellFormed("dead")
        self.assertWellFormed("dead", tries=1, reason="boom")
        self.assertBreaks("a dead job has 1 to max_tries tries", "dead", tries=0)
        self.assertBreaks("a dead job has no run_at", "dead", run_at_ms=9000)
        self.assertBreaks("a dead job has no worker", "dead", worker="w1")
        self.assertBreaks("a dead job has no lease_until", "dead", lease_until_ms=9000)

    def test_tries_above_max_tries_break_every_state(self) -> None:
        for state in WELL_FORMED:
            self.assertIsNotNone(job_problem(self.job(state, tries=4)), state)


if __name__ == "__main__":
    unittest.main()
