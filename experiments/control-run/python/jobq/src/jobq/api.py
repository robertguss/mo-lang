"""The HTTP API as a function from request to response; the server and the simulation call it."""

import json
from collections.abc import Callable
from dataclasses import dataclass, field
from http import HTTPStatus
from urllib.parse import parse_qsl, urlsplit

from pydantic import BaseModel, ConfigDict, ValidationError

from jobq.model import (
    DEFAULT_LEASE_MS,
    Job,
    JobState,
    LeaseMs,
    MaxAttempts,
    Payload,
    QueueName,
    Reason,
    is_job_id,
    is_queue_name,
    is_worker,
    iso_ms,
)
from jobq.queue import Queue, Refusal
from jobq.store import StoreUnavailable

type Headers = tuple[tuple[str, str], ...]


@dataclass(frozen=True)
class Request:
    method: str
    target: str
    headers: dict[str, str] = field(default_factory=dict)
    body: bytes = b""


@dataclass(frozen=True)
class Response:
    status: int
    body: bytes = b""
    headers: Headers = ()


class _Input(BaseModel):
    model_config = ConfigDict(frozen=True, strict=True, extra="forbid")


class CreateJob(_Input):
    queue: QueueName
    payload: Payload
    max_attempts: MaxAttempts


class LeaseJob(_Input):
    lease_ms: LeaseMs = DEFAULT_LEASE_MS


class AckJob(_Input):
    pass


class FailJob(_Input):
    reason: Reason


class ListJobs(_Input):
    queue: QueueName | None = None
    state: JobState | None = None


class JobView(BaseModel):
    """`{job}`: `worker` and `lease_until` only while leased, `reason` only after a fail."""

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
    def of(cls, job: Job) -> JobView:
        return cls(
            id=job.id,
            queue=job.queue,
            state=job.state,
            payload=job.payload,
            attempts=job.attempts,
            max_attempts=job.max_attempts,
            created_at=iso_ms(job.created_at),
            updated_at=iso_ms(job.updated_at),
            worker=job.worker,
            lease_until=None if job.lease_until is None else iso_ms(job.lease_until),
            reason=job.reason,
        )


class JobList(BaseModel):
    jobs: list[JobView]


class HealthView(BaseModel):
    queued: int
    leased: int
    done: int
    dead: int
    uptime_ms: int


class ErrorView(BaseModel):
    error: str


def respond(queue: Queue, request: Request) -> Response:
    try:
        return _dispatch(queue, request)
    except StoreUnavailable:
        return error(HTTPStatus.SERVICE_UNAVAILABLE, "the store is unavailable; nothing changed")


def error(status: int, message: str, headers: Headers = ()) -> Response:
    return _json(status, ErrorView(error=message), headers)


def bearer_token(value: str | None) -> str | None:
    """The token of `Bearer <token>`; None when missing, empty, or not visible ASCII."""
    if value is None:
        return None
    scheme, _, token = value.partition(" ")
    return token if scheme.lower() == "bearer" and is_worker(token) else None


def _dispatch(queue: Queue, request: Request) -> Response:
    target = urlsplit(request.target)
    segments = target.path.split("/")[1:] if target.path.startswith("/") else []
    handlers: dict[str, Callable[[str], Response]]
    match segments:
        case ["health"]:
            if request.method != "GET":
                return _not_allowed(["GET"])
            health = queue.health()
            return _json(HTTPStatus.OK, HealthView(**health.__dict__))
        case ["jobs"]:
            handlers = {
                "POST": lambda worker: _create(queue, request),
                "GET": lambda worker: _list(queue, target.query),
            }
        case ["jobs", job_id]:
            handlers = {
                "GET": lambda worker: _get(queue, job_id),
                "DELETE": lambda worker: _delete(queue, job_id),
            }
        case ["jobs", job_id, "ack"]:
            handlers = {"POST": lambda worker: _ack(queue, request, job_id, worker)}
        case ["jobs", job_id, "fail"]:
            handlers = {"POST": lambda worker: _fail(queue, request, job_id, worker)}
        case ["queues", name, "lease"]:
            handlers = {"POST": lambda worker: _lease(queue, request, name, worker)}
        case _:
            return error(HTTPStatus.NOT_FOUND, "no such route")
    handler = handlers.get(request.method)
    if handler is None:
        return _not_allowed(list(handlers))
    worker = bearer_token(request.headers.get("authorization"))
    if worker is None:
        return error(
            HTTPStatus.UNAUTHORIZED,
            "authorization: Bearer <token> is required",
            (("www-authenticate", "Bearer"),),
        )
    return handler(worker)


def _create(queue: Queue, request: Request) -> Response:
    parsed = _parse(CreateJob, request.body)
    if isinstance(parsed, Response):
        return parsed
    job = queue.create(parsed.queue, parsed.payload, parsed.max_attempts)
    return _json(HTTPStatus.CREATED, JobView.of(job))


def _list(queue: Queue, query: str) -> Response:
    pairs = parse_qsl(query, keep_blank_values=True)
    if len({key for key, _ in pairs}) != len(pairs):
        return error(HTTPStatus.BAD_REQUEST, "a query parameter is repeated")
    parsed = _parse(ListJobs, json.dumps(dict(pairs)).encode())
    if isinstance(parsed, Response):
        return parsed
    jobs = queue.list(parsed.queue, parsed.state)
    return _json(HTTPStatus.OK, JobList(jobs=[JobView.of(job) for job in jobs]))


def _get(queue: Queue, job_id: str) -> Response:
    job = queue.get(job_id) if is_job_id(job_id) else None
    if job is None:
        return error(HTTPStatus.NOT_FOUND, "no such job")
    return _json(HTTPStatus.OK, JobView.of(job))


def _delete(queue: Queue, job_id: str) -> Response:
    if not is_job_id(job_id):
        return error(HTTPStatus.NOT_FOUND, "no such job")
    refusal = queue.delete(job_id)
    if refusal is None:
        return Response(HTTPStatus.NO_CONTENT)
    return _refused(refusal, "the job is leased")


def _lease(queue: Queue, request: Request, name: str, worker: str) -> Response:
    if not is_queue_name(name):
        return error(HTTPStatus.BAD_REQUEST, "queue must be 1 to 64 letters, digits, - or _")
    parsed = _parse(LeaseJob, request.body, empty_is_object=True)
    if isinstance(parsed, Response):
        return parsed
    job = queue.lease(name, worker, parsed.lease_ms)
    if job is None:
        return Response(HTTPStatus.NO_CONTENT)
    return _json(HTTPStatus.OK, JobView.of(job))


def _ack(queue: Queue, request: Request, job_id: str, worker: str) -> Response:
    if not is_job_id(job_id):
        return error(HTTPStatus.NOT_FOUND, "no such job")
    parsed = _parse(AckJob, request.body, empty_is_object=True)
    if isinstance(parsed, Response):
        return parsed
    return _job_or_refusal(queue.ack(job_id, worker))


def _fail(queue: Queue, request: Request, job_id: str, worker: str) -> Response:
    if not is_job_id(job_id):
        return error(HTTPStatus.NOT_FOUND, "no such job")
    parsed = _parse(FailJob, request.body)
    if isinstance(parsed, Response):
        return parsed
    return _job_or_refusal(queue.fail(job_id, worker, parsed.reason))


def _job_or_refusal(result: Job | Refusal) -> Response:
    if isinstance(result, Refusal):
        return _refused(result, "the caller does not hold a live lease on the job")
    return _json(HTTPStatus.OK, JobView.of(result))


def _refused(refusal: Refusal, conflict: str) -> Response:
    if refusal is Refusal.NOT_FOUND:
        return error(HTTPStatus.NOT_FOUND, "no such job")
    return error(HTTPStatus.CONFLICT, conflict)


def _parse[M: BaseModel](
    model: type[M], body: bytes, empty_is_object: bool = False
) -> M | Response:
    if empty_is_object and not body.strip():
        body = b"{}"
    try:
        return model.model_validate_json(body)
    except ValidationError as err:
        problem = err.errors()[0]
        where = ".".join(str(part) for part in problem["loc"])
        message = f"{where}: {problem['msg']}" if where else problem["msg"]
        return error(HTTPStatus.BAD_REQUEST, message)


def _not_allowed(methods: list[str]) -> Response:
    return error(
        HTTPStatus.METHOD_NOT_ALLOWED, "method not allowed", (("allow", ", ".join(methods)),)
    )


def _json(status: int, body: BaseModel, headers: Headers = ()) -> Response:
    content = body.model_dump_json(exclude_none=True).encode()
    return Response(status, content, (("content-type", "application/json"), *headers))
