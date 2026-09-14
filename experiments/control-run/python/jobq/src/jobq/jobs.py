"""Jobs: the states, the validated inputs, and every JSON shape."""

import re
from collections.abc import Callable
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, Field

from jobq.clock import iso_utc

type JobState = Literal["queued", "leased", "done", "dead"]
STATES: tuple[JobState, ...] = ("queued", "leased", "done", "dead")

MAX_PAYLOAD_BYTES = 60 * 1024
MAX_REASON_BYTES = 4 * 1024
MIN_ATTEMPTS, MAX_ATTEMPTS = 1, 100
MIN_LEASE_MS, MAX_LEASE_MS, DEFAULT_LEASE_MS = 100, 3_600_000, 30_000
LIST_LIMIT = 100

_QUEUE_NAME = re.compile(r"[A-Za-z0-9_-]{1,64}")
_JOB_ID = re.compile(r"j_[1-9][0-9]{0,17}")
_TOKEN = re.compile(r"[\x21-\x7e]{1,256}")
# Unicode category Cc is exactly U+0000-U+001F and U+007F-U+009F; `\n` is allowed.
_CONTROL = re.compile(r"[\x00-\x09\x0b-\x1f\x7f-\x9f]")

_STRICT = ConfigDict(strict=True, extra="forbid", frozen=True)


def queue_name_problem(name: str) -> str | None:
    if _QUEUE_NAME.fullmatch(name) is None:
        return "queue must be 1 to 64 bytes of letters, digits, - and _"
    return None


def text_problem(field: str, text: str, max_bytes: int) -> str | None:
    """UTF-8, at most `max_bytes`, and no control characters but `\\n`."""
    try:
        size = len(text.encode("utf-8"))
    except UnicodeEncodeError:
        return f"{field} must be UTF-8"
    if size > max_bytes:
        return f"{field} must be at most {max_bytes} bytes, got {size}"
    if _CONTROL.search(text) is not None:
        return f"{field} must hold no control characters but \\n"
    return None


def payload_problem(payload: str) -> str | None:
    return text_problem("payload", payload, MAX_PAYLOAD_BYTES)


def token_problem(token: str) -> str | None:
    if _TOKEN.fullmatch(token) is None:
        return "token must be 1 to 256 visible ASCII characters"
    return None


def parse_job_id(text: str) -> int | None:
    """The counter inside `j_<n>`, or None if `text` is not a job id."""
    return int(text[2:]) if _JOB_ID.fullmatch(text) else None


def _validated_by(problem_of: Callable[[str], str | None]) -> AfterValidator:
    def check(value: str) -> str:
        problem = problem_of(value)
        if problem is not None:
            raise ValueError(problem)
        return value

    return AfterValidator(check)


def _reason_problem(reason: str) -> str | None:
    return text_problem("reason", reason, MAX_REASON_BYTES)


QueueName = Annotated[str, _validated_by(queue_name_problem)]
Payload = Annotated[str, _validated_by(payload_problem)]
Reason = Annotated[str, _validated_by(_reason_problem)]
Token = Annotated[str, _validated_by(token_problem)]


class CreateJob(BaseModel):
    """The body of `POST /jobs`."""

    model_config = _STRICT

    queue: QueueName
    payload: Payload
    max_attempts: int = Field(ge=MIN_ATTEMPTS, le=MAX_ATTEMPTS)


class LeaseRequest(BaseModel):
    """The body of `POST /queues/{queue}/lease`; an empty body takes the default."""

    model_config = _STRICT

    lease_ms: int = Field(default=DEFAULT_LEASE_MS, ge=MIN_LEASE_MS, le=MAX_LEASE_MS)


class FailRequest(BaseModel):
    """The body of `POST /jobs/{id}/fail`."""

    model_config = _STRICT

    reason: Reason


class ListQuery(BaseModel):
    """The query of `GET /jobs`; either filter is optional."""

    model_config = _STRICT

    queue: QueueName | None = None
    state: JobState | None = None


class Job(BaseModel):
    """A job as the queue and the store hold it."""

    model_config = _STRICT

    number: int = Field(ge=1)
    queue: QueueName
    state: JobState
    payload: Payload
    attempts: int = Field(ge=0, le=MAX_ATTEMPTS)
    max_attempts: int = Field(ge=MIN_ATTEMPTS, le=MAX_ATTEMPTS)
    created_ms: int = Field(ge=0)
    updated_ms: int = Field(ge=0)
    worker: Token | None = None
    lease_until_ms: int | None = None
    reason: Reason | None = None

    @property
    def id(self) -> str:
        return f"j_{self.number}"


class JobOut(BaseModel):
    """The `{job}` JSON shape: `worker` and `lease_until` while leased, `reason` after a fail."""

    model_config = _STRICT

    id: str
    queue: str
    state: JobState
    payload: str
    attempts: int
    max_attempts: int
    created_at: str
    updated_at: str
    worker: str | None = None
    lease_until: str | None = None
    reason: str | None = None

    @classmethod
    def of(cls, job: Job) -> JobOut:
        return cls(
            id=job.id,
            queue=job.queue,
            state=job.state,
            payload=job.payload,
            attempts=job.attempts,
            max_attempts=job.max_attempts,
            created_at=iso_utc(job.created_ms),
            updated_at=iso_utc(job.updated_ms),
            worker=job.worker,
            lease_until=None if job.lease_until_ms is None else iso_utc(job.lease_until_ms),
            reason=job.reason,
        )

    def to_json(self) -> bytes:
        return self.model_dump_json(exclude_none=True).encode()


class JobList(BaseModel):
    model_config = _STRICT

    jobs: list[JobOut]


class Health(BaseModel):
    model_config = _STRICT

    queued: int = Field(ge=0)
    leased: int = Field(ge=0)
    done: int = Field(ge=0)
    dead: int = Field(ge=0)
    uptime_ms: int = Field(ge=0)


class ErrorBody(BaseModel):
    model_config = _STRICT

    error: str
