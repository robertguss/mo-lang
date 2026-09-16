"""Jobs: the states, the validated inputs, and every JSON shape."""

import re
from collections.abc import Callable
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, Field

from jobq.clock import iso_utc

type JobState = Literal["queued", "scheduled", "leased", "done", "dead"]
STATES: tuple[JobState, ...] = ("queued", "scheduled", "leased", "done", "dead")

MAX_PAYLOAD_BYTES = 60 * 1024
MAX_REASON_BYTES = 4 * 1024
MIN_TRIES, MAX_TRIES = 1, 100
MIN_LEASE_MS, MAX_LEASE_MS, DEFAULT_LEASE_MS = 100, 3_600_000, 30_000
MAX_DELAY_MS = 86_400_000
MAX_BACKOFF_MS = 3_600_000
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
    """The body of `POST /jobs`; `delay_ms` and `backoff_ms` default to 0."""

    model_config = _STRICT

    queue: QueueName
    payload: Payload
    max_tries: int = Field(ge=MIN_TRIES, le=MAX_TRIES)
    delay_ms: int = Field(default=0, ge=0, le=MAX_DELAY_MS)
    backoff_ms: int = Field(default=0, ge=0, le=MAX_BACKOFF_MS)


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
    tries: int = Field(ge=0, le=MAX_TRIES)
    max_tries: int = Field(ge=MIN_TRIES, le=MAX_TRIES)
    backoff_ms: int = Field(ge=0, le=MAX_BACKOFF_MS)
    created_ms: int = Field(ge=0)
    updated_ms: int = Field(ge=0)
    run_at_ms: int | None = None
    worker: Token | None = None
    lease_until_ms: int | None = None
    reason: Reason | None = None

    @property
    def id(self) -> str:
        return f"j_{self.number}"


# The fields a job carries in some states and never in others, by the name a record shows.
_OPTIONAL = {"run_at": "run_at_ms", "worker": "worker", "lease_until": "lease_until_ms"}
_PRESENT: dict[JobState, frozenset[str]] = {
    "queued": frozenset(),
    "scheduled": frozenset({"run_at"}),
    "leased": frozenset({"worker", "lease_until"}),
    "done": frozenset(),
    "dead": frozenset(),
}
_WAITING: frozenset[JobState] = frozenset({"queued", "scheduled"})


def job_problem(job: Job) -> str | None:
    """The rule this job breaks, or None when it is well-formed. Every state's tries range
    and the fields it carries; no preconditions, so any decoded job may be handed to it."""
    if job.state in _WAITING:
        if job.tries >= job.max_tries:
            return f"a {job.state} job has tries below max_tries"
    elif not MIN_TRIES <= job.tries <= job.max_tries:
        return f"a {job.state} job has 1 to max_tries tries"
    for shown, field in _OPTIONAL.items():
        present = getattr(job, field) is not None
        if present and shown not in _PRESENT[job.state]:
            return f"a {job.state} job has no {shown}"
        if not present and shown in _PRESENT[job.state]:
            return f"a {job.state} job has a {shown}"
    return None


class JobOut(BaseModel):
    """The `{job}` JSON shape: `run_at` while scheduled, `worker` and `lease_until` while
    leased, `reason` after a fail."""

    model_config = _STRICT

    id: str
    queue: str
    state: JobState
    payload: str
    tries: int
    max_tries: int
    backoff_ms: int
    created_at: str
    updated_at: str
    run_at: str | None = None
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
            tries=job.tries,
            max_tries=job.max_tries,
            backoff_ms=job.backoff_ms,
            created_at=iso_utc(job.created_ms),
            updated_at=iso_utc(job.updated_ms),
            run_at=None if job.run_at_ms is None else iso_utc(job.run_at_ms),
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
    scheduled: int = Field(ge=0)
    leased: int = Field(ge=0)
    done: int = Field(ge=0)
    dead: int = Field(ge=0)
    uptime_ms: int = Field(ge=0)
    restarts: int = Field(ge=0)


class QueueCounts(BaseModel):
    """One queue's jobs by state, as `GET /queues` shows them."""

    model_config = _STRICT

    name: str
    queued: int = Field(ge=0)
    scheduled: int = Field(ge=0)
    leased: int = Field(ge=0)
    done: int = Field(ge=0)
    dead: int = Field(ge=0)


class QueueList(BaseModel):
    model_config = _STRICT

    queues: list[QueueCounts]


class ErrorBody(BaseModel):
    model_config = _STRICT

    error: str
