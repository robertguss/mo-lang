"""The listener: HTTP/1.1 over asyncio streams, one queue, one worker thread.

The queue is only touched from one thread (`QueueRunner`), so its operations never
interleave. Every wait on a socket carries a timeout, and so does every queue touch: one
that does not answer in five seconds is a 503 and the listener goes on to the next request.
"""

import asyncio
import contextlib
import re
import sys
import threading
from collections import deque
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import cast

from jobq.api import Api, Request, Response, error
from jobq.clock import Clock, SystemClock
from jobq.jobs import token_problem
from jobq.queue import Queue
from jobq.store import FileOps, Store

HOST = "127.0.0.1"
# within: an accepted connection must finish sending a request head in this long, or it
# is closed. This is what frees connections that send nothing (chosen: 5 s).
IDLE_TIMEOUT_S = 5.0
# within: once the head is in, the body must arrive and the response be written (chosen: 10 s).
REQUEST_TIMEOUT_S = 10.0
# within: closing a connection waits at most this long for the peer (chosen: 1 s).
CLOSE_TIMEOUT_S = 1.0
# The listener's Idle: how often run-out leases are returned and due scheduled jobs are
# queued without a request.
SWEEP_INTERVAL_S = 1.0
# within: a queue touch that has not answered in this long is a 503 for that request alone,
# and the listener is free again (the spec's five seconds).
QUEUE_TIMEOUT_S = 5.0
BACKLOG = 4096
MAX_HEAD_BYTES = 16 * 1024
MAX_BODY_BYTES = 1024 * 1024

_REASONS = {
    100: "Continue",
    200: "OK",
    201: "Created",
    204: "No Content",
    400: "Bad Request",
    401: "Unauthorized",
    404: "Not Found",
    405: "Method Not Allowed",
    409: "Conflict",
    413: "Content Too Large",
    500: "Internal Server Error",
    503: "Service Unavailable",
}
_CONTENT_LENGTH = re.compile(r"[0-9]{1,10}")


class BadRequest(Exception):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status


@dataclass(frozen=True)
class Head:
    method: str
    path: str
    query: str
    version: str
    headers: dict[str, str]

    @property
    def keep_alive(self) -> bool:
        return self.version == "HTTP/1.1" and self.headers.get("connection", "").lower() != "close"


def parse_head(raw: bytes) -> Head:
    """The request line and headers, up to and including the blank line."""
    try:
        text = raw.decode("ascii")
    except UnicodeDecodeError as undecodable:
        raise BadRequest(400, "request head is not ASCII") from undecodable
    request_line, *header_lines = text.removesuffix("\r\n\r\n").split("\r\n")
    parts = request_line.split(" ")
    if len(parts) != 3 or parts[2] not in {"HTTP/1.0", "HTTP/1.1"}:
        raise BadRequest(400, "malformed request line")
    method, target, version = parts
    headers: dict[str, str] = {}
    for line in header_lines:
        name, colon, value = line.partition(":")
        if not colon or not name or name != name.strip():
            raise BadRequest(400, "malformed header")
        key = name.lower()
        if key in headers and key in {"content-length", "authorization", "host"}:
            raise BadRequest(400, f"repeated {key} header")
        headers[key] = value.strip()
    path, _, query = target.partition("?")
    return Head(method, path, query, version, headers)


def bearer_token(value: str | None) -> str | None:
    """The token in `authorization: Bearer <token>`, or None if missing, empty, or malformed."""
    if value is None:
        return None
    scheme, _, token = value.partition(" ")
    if scheme.lower() != "bearer" or token_problem(token) is not None:
        return None
    return token


def body_length(head: Head) -> int:
    if "transfer-encoding" in head.headers:
        raise BadRequest(400, "chunked bodies are not supported; send content-length")
    text = head.headers.get("content-length", "0")
    if _CONTENT_LENGTH.fullmatch(text) is None:
        raise BadRequest(400, "malformed content-length")
    length = int(text)
    if length > MAX_BODY_BYTES:
        raise BadRequest(413, f"body is over {MAX_BODY_BYTES} bytes")
    return length


def encode_response(response: Response, keep_alive: bool) -> bytes:
    lines = [f"HTTP/1.1 {response.status} {_REASONS.get(response.status, 'Unknown')}"]
    if response.status != 204:
        lines.append(f"content-length: {len(response.body)}")
        if response.body:
            lines.append("content-type: application/json")
    if response.allow is not None:
        lines.append(f"allow: {response.allow}")
    lines.append("connection: keep-alive" if keep_alive else "connection: close")
    head = ("\r\n".join(lines) + "\r\n\r\n").encode("ascii")
    return head if response.status == 204 else head + response.body


def _drop[T](future: asyncio.Future[T]) -> None:
    """Take the outcome of a touch nobody waits for any more, so it is never logged as lost."""
    with contextlib.suppress(BaseException):
        future.exception()


def _finish(future: asyncio.Future[object], value: object, failure: BaseException | None) -> None:
    if future.done():
        return
    if failure is not None:
        future.set_exception(failure)
    else:
        future.set_result(value)


class QueueRunner:
    """Every queue touch on one thread of its own: no two ever interleave, and one that does
    not answer within `QUEUE_TIMEOUT_S` raises `TimeoutError` to its caller, leaving the
    listener free for the next request. The touch itself is never abandoned — it runs on, and
    whatever comes after it waits behind it — so a job is never left half changed.

    Touches that are waiting together are taken in one batch, so a busy listener pays one
    handoff for many requests rather than one for each.
    """

    def __init__(self) -> None:
        self._pending: deque[tuple[Callable[[], object], asyncio.Future[object]]] = deque()
        self._wake = threading.Event()
        self._closed = False
        self._loop: asyncio.AbstractEventLoop | None = None
        self._thread = threading.Thread(target=self._work, name="jobq-queue", daemon=True)

    async def run[T](self, work: Callable[[], T]) -> T:
        loop = asyncio.get_running_loop()
        if self._loop is None:
            self._loop = loop
            self._thread.start()
        future: asyncio.Future[object] = loop.create_future()
        self._pending.append((cast(Callable[[], object], work), future))
        self._wake.set()
        done, _ = await asyncio.wait([future], timeout=QUEUE_TIMEOUT_S)
        if not done:
            future.add_done_callback(_drop)
            raise TimeoutError(f"the queue did not answer in {QUEUE_TIMEOUT_S:.0f} s")
        return cast(T, future.result())

    def close(self) -> None:
        self._closed = True
        self._wake.set()

    def _work(self) -> None:
        """Wait, then take everything that is waiting, in the order it was asked for."""
        while True:
            self._wake.wait()
            self._wake.clear()
            if self._closed:
                return
            while self._pending:
                work, future = self._pending.popleft()
                try:
                    self._settle(future, work(), None)
                except BaseException as failure:  # noqa: BLE001 - handed to the request
                    self._settle(future, None, failure)

    def _settle(
        self, future: asyncio.Future[object], value: object, failure: BaseException | None
    ) -> None:
        loop = self._loop
        if loop is None or loop.is_closed():
            return
        with contextlib.suppress(RuntimeError):
            loop.call_soon_threadsafe(_finish, future, value, failure)


class HttpServer:
    def __init__(self, api: Api, queue: Queue) -> None:
        self._api = api
        self._queue = queue
        self._server: asyncio.Server | None = None
        self._sweeper: asyncio.Task[None] | None = None
        self._runner = QueueRunner()
        self.connections = 0
        self.port = 0

    async def start(self, host: str, port: int) -> int:
        """Bind and listen; the bound port. OSError when the port cannot be bound."""
        self._server = await asyncio.start_server(
            self._connection, host, port, limit=MAX_HEAD_BYTES, backlog=BACKLOG
        )
        self._sweeper = asyncio.create_task(self._sweep())
        bound: int = self._server.sockets[0].getsockname()[1]
        self.port = bound
        return bound

    async def stop(self) -> None:
        if self._sweeper is not None:
            self._sweeper.cancel()
        if self._server is not None:
            self._server.close()
            self._server.close_clients()
        self._runner.close()

    async def _sweep(self) -> None:
        """The idle look, on the queue's own thread. A look that fails costs this round only."""
        while True:
            await asyncio.sleep(SWEEP_INTERVAL_S)
            try:
                await self._runner.run(self._queue.expire_due)
            except Exception as failure:  # noqa: BLE001 - the next look is taken all the same
                print(f"jobq: the idle look failed: {failure}", file=sys.stderr)

    async def _connection(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        self.connections += 1
        try:
            while await self._exchange(reader, writer):
                pass
        except (
            TimeoutError,
            ConnectionError,
            asyncio.IncompleteReadError,
            asyncio.LimitOverrunError,
        ):
            pass
        except Exception as failure:  # noqa: BLE001 - this connection ends, the service does not
            print(f"jobq: a connection failed: {failure!r}", file=sys.stderr)
        finally:
            self.connections -= 1
            writer.close()
            with contextlib.suppress(TimeoutError, ConnectionError):
                await asyncio.wait_for(writer.wait_closed(), CLOSE_TIMEOUT_S)

    async def _exchange(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> bool:
        """One request and its response; whether the connection stays open."""
        try:
            raw = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), IDLE_TIMEOUT_S)
        except asyncio.IncompleteReadError:
            return False
        loop = asyncio.get_running_loop()
        deadline = loop.time() + REQUEST_TIMEOUT_S
        try:
            head = parse_head(raw)
            length = body_length(head)
        except BadRequest as bad:
            await self._send(writer, error(bad.status, str(bad)), False, deadline)
            return False
        if length and head.headers.get("expect", "").lower() == "100-continue":
            writer.write(b"HTTP/1.1 100 Continue\r\n\r\n")
        body = await asyncio.wait_for(reader.readexactly(length), deadline - loop.time())
        request = Request(
            method=head.method,
            path=head.path,
            query=head.query,
            token=bearer_token(head.headers.get("authorization")),
            body=body,
        )
        try:
            response = await self._runner.run(lambda: self._api.handle(request))
        except TimeoutError as slow:
            response = error(503, str(slow))
        await self._send(writer, response, head.keep_alive, deadline)
        return head.keep_alive

    @staticmethod
    async def _send(
        writer: asyncio.StreamWriter, response: Response, keep_alive: bool, deadline: float
    ) -> None:
        writer.write(encode_response(response, keep_alive))
        remaining = deadline - asyncio.get_running_loop().time()
        await asyncio.wait_for(writer.drain(), remaining)


def open_queue(
    directory: Path, clock: Clock | None = None, ops: FileOps | None = None
) -> tuple[Queue, Api]:
    """Open and replay the store under `directory`. StoreOpenError when it cannot."""
    the_clock = clock or SystemClock()
    store, replayed = Store.open(directory, ops)
    queue = Queue(store, the_clock, replayed)
    return queue, Api(queue, the_clock)


async def serve(
    directory: Path, port: int, ready: Callable[[HttpServer], None], stop: asyncio.Event
) -> None:
    """Serve until `stop` is set. StoreOpenError or OSError before `ready` is called."""
    queue, api = open_queue(directory)
    server = HttpServer(api, queue)
    try:
        await server.start(HOST, port)
        ready(server)
        await stop.wait()
    finally:
        await server.stop()
        queue.store.close()


class ServerThread:
    """`serve` on its own thread and event loop, for `jobq check` and the socket tests."""

    START_TIMEOUT_S = 10.0  # within: chosen, covers replaying a large log at start
    STOP_TIMEOUT_S = 10.0  # within: chosen

    def __init__(self, directory: Path, port: int = 0) -> None:
        self._directory = directory
        self._port = port
        self._ready = threading.Event()
        self._loop: asyncio.AbstractEventLoop | None = None
        self._stop: asyncio.Event | None = None
        self._failure: BaseException | None = None
        self._thread = threading.Thread(target=self._run, daemon=True)
        self.http: HttpServer | None = None
        self.port = 0

    def __enter__(self) -> ServerThread:
        self._thread.start()
        if not self._ready.wait(self.START_TIMEOUT_S):
            raise TimeoutError("jobq did not start in time")
        if self._failure is not None:
            raise self._failure
        return self

    def __exit__(self, *_exc: object) -> None:
        if self._loop is not None and self._stop is not None:
            self._loop.call_soon_threadsafe(self._stop.set)
        self._thread.join(self.STOP_TIMEOUT_S)

    def _run(self) -> None:
        async def main() -> None:
            self._loop = asyncio.get_running_loop()
            self._stop = asyncio.Event()
            await serve(self._directory, self._port, self._started, self._stop)

        try:
            asyncio.run(main())
        except Exception as failure:  # noqa: BLE001 - handed to the thread that waits
            self._failure = failure
            self._ready.set()

    def _started(self, server: HttpServer) -> None:
        self.http = server
        self.port = server.port
        self._ready.set()
