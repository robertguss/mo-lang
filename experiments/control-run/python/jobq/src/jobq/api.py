"""The HTTP API as a function from a request to a response, apart from any socket."""

import json
import sys
from collections.abc import Callable
from dataclasses import dataclass
from urllib.parse import parse_qsl

from pydantic import BaseModel, ValidationError

from jobq.clock import Clock
from jobq.contract import ContractError
from jobq.jobs import (
    CreateJob,
    ErrorBody,
    FailRequest,
    Health,
    Job,
    JobList,
    JobOut,
    LeaseRequest,
    ListQuery,
    queue_name_problem,
)
from jobq.queue import Conflict, NotFound, Queue
from jobq.store import StoreError


@dataclass(frozen=True)
class Request:
    method: str
    path: str
    query: str = ""
    token: str | None = None
    body: bytes = b""


@dataclass(frozen=True)
class Response:
    status: int
    body: bytes = b""
    allow: str | None = None

    def json(self) -> object:
        return json.loads(self.body)


type Handler = Callable[[Request, str], Response]


def error(status: int, message: str, allow: str | None = None) -> Response:
    return Response(status, ErrorBody(error=message).model_dump_json().encode(), allow)


def _json(status: int, model: BaseModel) -> Response:
    return Response(status, model.model_dump_json(exclude_none=True).encode())


def _problem(validation: ValidationError) -> str:
    first = validation.errors()[0]
    where = ".".join(str(part) for part in first["loc"])
    return f"{where}: {first['msg']}" if where else str(first["msg"])


class Api:
    def __init__(self, queue: Queue, clock: Clock) -> None:
        self._queue = queue
        self._clock = clock
        self._started_ms = clock.now_ms()

    def handle(self, request: Request) -> Response:
        """Route, check the token, and answer; a store failure is a 503 with nothing changed."""
        routes, param = self._match(request.path)
        if routes is None:
            return error(404, "no such route")
        handler = routes.get(request.method)
        if handler is None:
            return error(405, "method not allowed", allow=", ".join(routes))
        if request.path != "/health" and request.token is None:
            return error(401, "missing bearer token")
        try:
            return handler(request, param)
        except StoreError as failure:
            return error(503, f"store unavailable: {failure}")
        except ContractError as bug:
            print(f"jobq: {bug}", file=sys.stderr)
            return error(500, "internal error")

    def _match(self, path: str) -> tuple[dict[str, Handler] | None, str]:
        match path.split("/"):
            case ["", "health"]:
                return {"GET": self._health}, ""
            case ["", "jobs"]:
                return {"POST": self._create, "GET": self._list}, ""
            case ["", "jobs", job_id]:
                return {"GET": self._get, "DELETE": self._delete}, job_id
            case ["", "jobs", job_id, "ack"]:
                return {"POST": self._ack}, job_id
            case ["", "jobs", job_id, "fail"]:
                return {"POST": self._fail}, job_id
            case ["", "jobs", job_id, "retry"]:
                return {"POST": self._retry}, job_id
            case ["", "queues", queue, "lease"]:
                return {"POST": self._lease}, queue
            case _:
                return None, ""

    def _health(self, _request: Request, _param: str) -> Response:
        counts = self._queue.counts()
        uptime = max(0, self._clock.now_ms() - self._started_ms)
        health = Health(
            queued=counts["queued"],
            scheduled=counts["scheduled"],
            leased=counts["leased"],
            done=counts["done"],
            dead=counts["dead"],
            uptime_ms=uptime,
        )
        return _json(200, health)

    def _create(self, request: Request, _param: str) -> Response:
        try:
            body = CreateJob.model_validate_json(request.body)
        except ValidationError as invalid:
            return error(400, _problem(invalid))
        job = self._queue.create(
            body.queue, body.payload, body.max_tries, body.delay_ms, body.backoff_ms
        )
        return _json(201, JobOut.of(job))

    def _list(self, request: Request, _param: str) -> Response:
        pairs = parse_qsl(request.query, keep_blank_values=True)
        fields = dict(pairs)
        if len(fields) != len(pairs):
            return error(400, "a query parameter is repeated")
        try:
            query = ListQuery.model_validate(fields)
        except ValidationError as invalid:
            return error(400, _problem(invalid))
        jobs = self._queue.jobs(query.queue, query.state)
        return _json(200, JobList(jobs=[JobOut.of(job) for job in jobs]))

    def _get(self, _request: Request, job_id: str) -> Response:
        job = self._queue.get(job_id)
        return error(404, "no such job") if job is None else _json(200, JobOut.of(job))

    def _delete(self, _request: Request, job_id: str) -> Response:
        match self._queue.delete(job_id):
            case NotFound():
                return error(404, "no such job")
            case Conflict(reason=reason):
                return error(409, reason)
            case _:
                return Response(204)

    def _lease(self, request: Request, queue: str) -> Response:
        problem = queue_name_problem(queue)
        if problem is not None:
            return error(400, problem)
        try:
            body = LeaseRequest.model_validate_json(request.body or b"{}")
        except ValidationError as invalid:
            return error(400, _problem(invalid))
        assert request.token is not None
        job = self._queue.lease(queue, request.token, body.lease_ms)
        return Response(204) if job is None else _json(200, JobOut.of(job))

    def _ack(self, request: Request, job_id: str) -> Response:
        assert request.token is not None
        return _outcome(self._queue.ack(job_id, request.token))

    def _fail(self, request: Request, job_id: str) -> Response:
        try:
            body = FailRequest.model_validate_json(request.body)
        except ValidationError as invalid:
            return error(400, _problem(invalid))
        assert request.token is not None
        return _outcome(self._queue.fail(job_id, request.token, body.reason))

    def _retry(self, _request: Request, job_id: str) -> Response:
        """Needs no body; one that is sent is ignored, as on `/ack`."""
        return _outcome(self._queue.retry(job_id))


def _outcome(result: Job | NotFound | Conflict) -> Response:
    match result:
        case NotFound():
            return error(404, "no such job")
        case Conflict(reason=reason):
            return error(409, reason)
        case Job():
            return _json(200, JobOut.of(result))
