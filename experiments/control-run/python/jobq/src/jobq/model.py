"""Jobs: their fields, their states, and the rules on every input a job is made from."""

import re
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from typing import Annotated

from pydantic import AfterValidator, BaseModel, ConfigDict, Field

MAX_PAYLOAD_BYTES = 60 * 1024
MIN_ATTEMPTS = 1
MAX_ATTEMPTS = 100
MIN_LEASE_MS = 100
MAX_LEASE_MS = 3_600_000
DEFAULT_LEASE_MS = 30_000
MAX_REASON_BYTES = 4 * 1024
MAX_WORKER_CHARS = 256

_QUEUE_NAME = re.compile(r"[A-Za-z0-9_-]{1,64}")
_JOB_ID = re.compile(r"j_[1-9][0-9]{0,17}")
_WORKER = re.compile(r"[\x21-\x7e]{1,%d}" % MAX_WORKER_CHARS)
_CONTROL_BUT_NEWLINE = re.compile(r"[\x00-\x09\x0b-\x1f\x7f-\x9f]")
_EPOCH = datetime(1970, 1, 1, tzinfo=UTC)


class JobState(StrEnum):
    QUEUED = "queued"
    LEASED = "leased"
    DONE = "done"
    DEAD = "dead"


def is_queue_name(text: str) -> bool:
    return _QUEUE_NAME.fullmatch(text) is not None


def is_job_id(text: str) -> bool:
    return _JOB_ID.fullmatch(text) is not None


def is_worker(text: str) -> bool:
    return _WORKER.fullmatch(text) is not None


def is_max_attempts(value: int) -> bool:
    return MIN_ATTEMPTS <= value <= MAX_ATTEMPTS


def is_lease_ms(value: int) -> bool:
    return MIN_LEASE_MS <= value <= MAX_LEASE_MS


def text_problem(text: str, what: str, max_bytes: int) -> str | None:
    """Why `text` is not at most `max_bytes` of UTF-8 without control characters but `\\n`."""
    try:
        size = len(text.encode("utf-8"))
    except UnicodeEncodeError:
        return f"{what} is not valid UTF-8"
    if size > max_bytes:
        return f"{what} is {size} bytes, more than {max_bytes}"
    if _CONTROL_BUT_NEWLINE.search(text):
        return f"{what} has a control character other than \\n"
    return None


def payload_problem(text: str) -> str | None:
    return text_problem(text, "payload", MAX_PAYLOAD_BYTES)


def reason_problem(text: str) -> str | None:
    return text_problem(text, "reason", MAX_REASON_BYTES)


def job_number(job_id: str) -> int:
    return int(job_id.removeprefix("j_"))


def job_id_of(number: int) -> str:
    return f"j_{number}"


def iso_ms(epoch_ms: int) -> str:
    """ISO-8601 UTC with milliseconds, e.g. `2026-09-14T14:40:57.123Z`."""
    at = _EPOCH + timedelta(milliseconds=epoch_ms)
    return at.strftime("%Y-%m-%dT%H:%M:%S.") + f"{epoch_ms % 1000:03d}Z"


def _checked(test: bool, message: str) -> None:
    if not test:
        raise ValueError(message)


def _queue_name(text: str) -> str:
    _checked(is_queue_name(text), "queue must be 1 to 64 letters, digits, - or _")
    return text


def _job_id(text: str) -> str:
    _checked(is_job_id(text), "id must be j_ and a number")
    return text


def _worker(text: str) -> str:
    _checked(is_worker(text), f"worker must be 1 to {MAX_WORKER_CHARS} visible ASCII characters")
    return text


def _payload(text: str) -> str:
    problem = payload_problem(text)
    _checked(problem is None, problem or "")
    return text


def _reason(text: str) -> str:
    problem = reason_problem(text)
    _checked(problem is None, problem or "")
    return text


QueueName = Annotated[str, AfterValidator(_queue_name)]
JobId = Annotated[str, AfterValidator(_job_id)]
Worker = Annotated[str, AfterValidator(_worker)]
Payload = Annotated[str, AfterValidator(_payload)]
Reason = Annotated[str, AfterValidator(_reason)]
MaxAttempts = Annotated[int, Field(ge=MIN_ATTEMPTS, le=MAX_ATTEMPTS)]
LeaseMs = Annotated[int, Field(ge=MIN_LEASE_MS, le=MAX_LEASE_MS)]
EpochMs = Annotated[int, Field(ge=0)]


class Job(BaseModel):
    """A job as the store keeps it. Times are milliseconds since the epoch."""

    model_config = ConfigDict(frozen=True, strict=True, extra="forbid")

    id: JobId
    queue: QueueName
    state: JobState
    payload: Payload
    attempts: Annotated[int, Field(ge=0, le=MAX_ATTEMPTS)]
    max_attempts: MaxAttempts
    created_at: EpochMs
    updated_at: EpochMs
    worker: Worker | None = None
    lease_until: EpochMs | None = None
    reason: Reason | None = None
