"""The listener: HTTP/1.1 on asyncio, one thread for the queue, a deadline on every wait."""

import asyncio
import signal
import sys
import threading
import time
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from contextlib import suppress
from dataclasses import dataclass
from http import HTTPStatus

from jobq.api import Request, Response, error, respond
from jobq.contract import ContractError
from jobq.deadlines import (
    CLOSE_TIMEOUT_S,
    IDLE_TIMEOUT_S,
    REQUEST_TIMEOUT_S,
    START_TIMEOUT_S,
    STOP_TIMEOUT_S,
    SWEEP_INTERVAL_S,
    SWEEP_TIMEOUT_S,
)
from jobq.queue import Queue
from jobq.store import StoreUnavailable

HOST = "127.0.0.1"
MAX_HEAD_BYTES = 16 * 1024
MAX_BODY_BYTES = 1024 * 1024
LISTEN_BACKLOG = 2048


class HeadError(Exception):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status


@dataclass(frozen=True)
class Head:
    method: str
    target: str
    headers: dict[str, str]
    content_length: int
    keep_alive: bool


def parse_head(data: bytes) -> Head:
    lines = data.removesuffix(b"\r\n\r\n").split(b"\r\n")
    try:
        method, target, version = lines[0].decode("ascii").split(" ")
    except (UnicodeDecodeError, ValueError) as err:
        raise HeadError(HTTPStatus.BAD_REQUEST, "malformed request line") from err
    if version not in ("HTTP/1.1", "HTTP/1.0"):
        raise HeadError(HTTPStatus.HTTP_VERSION_NOT_SUPPORTED, "HTTP/1.1 only")
    if not (method.isascii() and method.isalpha() and method.isupper()):
        raise HeadError(HTTPStatus.BAD_REQUEST, "malformed method")
    if not target.startswith("/"):
        raise HeadError(HTTPStatus.BAD_REQUEST, "malformed request target")
    headers = _parse_headers(lines[1:])
    if "transfer-encoding" in headers:
        raise HeadError(HTTPStatus.NOT_IMPLEMENTED, "transfer-encoding is not supported")
    length = headers.get("content-length", "0")
    if not (length.isascii() and length.isdigit() and len(length) <= 12):
        raise HeadError(HTTPStatus.BAD_REQUEST, "malformed content-length")
    if int(length) > MAX_BODY_BYTES:
        raise HeadError(HTTPStatus.CONTENT_TOO_LARGE, f"body over {MAX_BODY_BYTES} bytes")
    connection = headers.get("connection", "").lower()
    keep_alive = "close" not in connection if version == "HTTP/1.1" else "keep-alive" in connection
    return Head(method, target, headers, int(length), keep_alive)


def _parse_headers(lines: list[bytes]) -> dict[str, str]:
    headers: dict[str, str] = {}
    for line in lines:
        name, colon, value = line.partition(b":")
        if not colon or not name or name != name.strip():
            raise HeadError(HTTPStatus.BAD_REQUEST, "malformed header")
        key = name.decode("latin-1").lower()
        text = value.strip().decode("latin-1")
        if key in headers:
            if key in ("content-length", "authorization", "transfer-encoding"):
                raise HeadError(HTTPStatus.BAD_REQUEST, f"repeated {key} header")
            text = f"{headers[key]}, {text}"
        headers[key] = text
    return headers


def encode_response(response: Response, keep_alive: bool) -> bytes:
    status = HTTPStatus(response.status)
    lines = [f"HTTP/1.1 {status.value} {status.phrase}"]
    lines += [f"{name}: {value}" for name, value in response.headers]
    if status is not HTTPStatus.NO_CONTENT:
        lines.append(f"content-length: {len(response.body)}")
    lines.append("connection: keep-alive" if keep_alive else "connection: close")
    return ("\r\n".join(lines) + "\r\n\r\n").encode("latin-1") + response.body


def _left(deadline: float) -> float:
    return max(0.0, deadline - time.monotonic())


class Server:
    def __init__(self, queue: Queue) -> None:
        self._queue = queue
        self._executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="jobq-queue")
        self._server: asyncio.Server | None = None
        self._sweeper: asyncio.Task[None] | None = None

    async def start(self, host: str, port: int) -> int:
        self._server = await asyncio.start_server(
            self._connection, host, port, limit=MAX_HEAD_BYTES, backlog=LISTEN_BACKLOG
        )
        self._sweeper = asyncio.create_task(self._sweep())
        bound: int = self._server.sockets[0].getsockname()[1]
        return bound

    async def stop(self) -> None:
        if self._sweeper is not None:
            self._sweeper.cancel()
            with suppress(asyncio.CancelledError):
                await self._sweeper
        if self._server is not None:
            self._server.close()
            self._server.close_clients()
            with suppress(TimeoutError):
                await asyncio.wait_for(self._server.wait_closed(), STOP_TIMEOUT_S)
        self._executor.shutdown(wait=True)

    async def _connection(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            await self._requests(reader, writer)
        except TimeoutError, asyncio.IncompleteReadError, ConnectionError:
            pass
        finally:
            writer.close()
            with suppress(TimeoutError, OSError):
                await asyncio.wait_for(writer.wait_closed(), CLOSE_TIMEOUT_S)

    async def _requests(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        loop = asyncio.get_running_loop()
        keep_alive = True
        while keep_alive:
            try:
                data = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), IDLE_TIMEOUT_S)
            except asyncio.LimitOverrunError:
                too_large = error(
                    HTTPStatus.REQUEST_HEADER_FIELDS_TOO_LARGE, "request head too large"
                )
                await self._send(writer, too_large, False, time.monotonic() + CLOSE_TIMEOUT_S)
                return
            deadline = time.monotonic() + REQUEST_TIMEOUT_S
            try:
                head = parse_head(data)
            except HeadError as problem:
                await self._send(writer, error(problem.status, str(problem)), False, deadline)
                return
            body = await asyncio.wait_for(reader.readexactly(head.content_length), _left(deadline))
            request = Request(head.method, head.target, head.headers, body)
            answer = loop.run_in_executor(self._executor, self._respond, request, deadline)
            response = await asyncio.wait_for(answer, _left(deadline))
            keep_alive = head.keep_alive
            await self._send(writer, response, keep_alive, deadline)

    def _respond(self, request: Request, deadline: float) -> Response:
        """On the queue thread, so every look and change is serialized."""
        if time.monotonic() > deadline:
            return error(HTTPStatus.SERVICE_UNAVAILABLE, "timed out waiting for the queue")
        try:
            return respond(self._queue, request)
        except ContractError as err:
            print(f"jobq: {err}", file=sys.stderr, flush=True)
            return error(HTTPStatus.INTERNAL_SERVER_ERROR, "internal error")

    async def _send(
        self, writer: asyncio.StreamWriter, response: Response, keep_alive: bool, deadline: float
    ) -> None:
        writer.write(encode_response(response, keep_alive))
        await asyncio.wait_for(writer.drain(), _left(deadline))

    async def _sweep(self) -> None:
        loop = asyncio.get_running_loop()
        while True:
            await asyncio.sleep(SWEEP_INTERVAL_S)
            try:
                look = loop.run_in_executor(self._executor, self._queue.expire)
                await asyncio.wait_for(look, SWEEP_TIMEOUT_S)
            except (StoreUnavailable, ContractError, TimeoutError) as err:
                print(
                    f"jobq: lease sweep: {err or type(err).__name__}", file=sys.stderr, flush=True
                )


async def serve(queue: Queue, host: str, port: int, announce: Callable[[int], None]) -> None:
    """Serve until SIGINT or SIGTERM. OSError if the port cannot be bound."""
    server = Server(queue)
    announce(await server.start(host, port))
    stopping = asyncio.Event()
    loop = asyncio.get_running_loop()
    for signum in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(signum, stopping.set)
    await stopping.wait()
    await server.stop()


class ServerThread:
    """A server on an event loop of its own thread: for `jobq check` and the tests."""

    def __init__(self, queue: Queue, host: str = HOST, port: int = 0) -> None:
        self._queue = queue
        self._host = host
        self._port = port
        self.port = 0
        self._ready = threading.Event()
        self._failure: OSError | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._stopping: asyncio.Event | None = None
        self._thread = threading.Thread(target=self._run, name="jobq-server", daemon=True)

    def start(self) -> int:
        self._thread.start()
        if not self._ready.wait(START_TIMEOUT_S):
            raise TimeoutError("the server thread did not start")
        if self._failure is not None:
            raise self._failure
        return self.port

    def stop(self) -> None:
        if self._loop is not None and self._stopping is not None:
            self._loop.call_soon_threadsafe(self._stopping.set)
        self._thread.join(STOP_TIMEOUT_S)

    def __enter__(self) -> ServerThread:
        self.start()
        return self

    def __exit__(self, *exc: object) -> None:
        self.stop()

    def _run(self) -> None:
        asyncio.run(self._main())

    async def _main(self) -> None:
        server = Server(self._queue)
        try:
            self.port = await server.start(self._host, self._port)
        except OSError as err:
            self._failure = err
            self._ready.set()
            return
        self._loop = asyncio.get_running_loop()
        self._stopping = asyncio.Event()
        self._ready.set()
        await self._stopping.wait()
        await server.stop()
