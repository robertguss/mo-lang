"""`jobq serve | compact | client | check`."""

import asyncio
import fcntl
import http.client
import os
import sys
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import TextIO

from jobq.check import CHECK_EPOCH_MS, ScriptError, play
from jobq.client import format_reply, request
from jobq.clock import Clock, ManualClock, SystemClock
from jobq.fs import OsFs
from jobq.queue import Queue
from jobq.server import HOST, ServerThread, serve
from jobq.store import Store, StoreCorrupt

USAGE = (
    "usage: jobq serve <dir> [--port N] | jobq compact <dir> | "
    "jobq client <host> <port> <token> <method> <path> [<json>] | jobq check <dir> <script>"
)
DEFAULT_PORT = 7900
LOCK_NAME = "jobq.lock"
EXIT_OK = 0
EXIT_FAILED = 1
EXIT_USAGE = 2


class UsageError(Exception):
    pass


class Failure(Exception):
    pass


def run(argv: list[str], out: TextIO, err: TextIO) -> int:
    try:
        return _command(argv, out)
    except UsageError as problem:
        print(f"jobq: {problem}; {USAGE}", file=err)
        return EXIT_USAGE
    except Failure as problem:
        print(f"jobq: {problem}", file=err)
        return EXIT_FAILED


def _command(argv: list[str], out: TextIO) -> int:
    match argv:
        case ["serve", directory]:
            return _serve(Path(directory), DEFAULT_PORT, out)
        case ["serve", directory, "--port", port]:
            return _serve(Path(directory), _port(port, lowest=0), out)
        case ["compact", directory]:
            return _compact(Path(directory), out)
        case ["client", host, port, token, method, path, *body] if len(body) <= 1:
            return _client(host, _port(port, lowest=1), token, method, path, body, out)
        case ["check", directory, script]:
            return _check(Path(directory), Path(script), out)
        case _:
            raise UsageError("unknown command or wrong arguments")


def _port(text: str, lowest: int) -> int:
    if not (text.isascii() and text.isdigit() and lowest <= int(text[:6]) <= 65535):
        raise UsageError(f"port must be a number from {lowest} to 65535")
    return int(text)


@contextmanager
def _opened(directory: Path, clock: Clock) -> Iterator[Queue]:
    """The queue replayed from `directory`, which no other jobq may hold meanwhile."""
    if not directory.is_dir():
        raise Failure(f"cannot open {directory}: not a directory")
    try:
        lock = os.open(directory / LOCK_NAME, os.O_RDWR | os.O_CREAT | os.O_CLOEXEC, 0o644)
    except OSError as problem:
        raise Failure(f"cannot open {directory}: {problem.strerror}") from problem
    try:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as problem:
            raise Failure(f"{directory} is held by another jobq") from problem
        store = Store(OsFs(), directory)
        try:
            queue = Queue.open(store, clock)
        except (OSError, StoreCorrupt) as problem:
            raise Failure(f"cannot open {directory}: {problem}") from problem
        try:
            yield queue
        finally:
            store.close()
    finally:
        os.close(lock)


def _serve(directory: Path, port: int, out: TextIO) -> int:
    def announce(bound: int) -> None:
        print(f"jobq: serving {directory} on {HOST}:{bound}", file=out, flush=True)

    with _opened(directory, SystemClock()) as queue:
        try:
            asyncio.run(serve(queue, HOST, port, announce))
        except OSError as problem:
            raise Failure(f"cannot serve on {HOST}:{port}: {problem.strerror}") from problem
    return EXIT_OK


def _compact(directory: Path, out: TextIO) -> int:
    with _opened(directory, SystemClock()) as queue:
        try:
            records = queue.compact()
        except OSError as problem:
            raise Failure(f"cannot compact {directory}: {problem.strerror}") from problem
    print(f"jobq: compacted {directory} to {records} records", file=out)
    return EXIT_OK


def _client(
    host: str, port: int, token: str, method: str, path: str, body: list[str], out: TextIO
) -> int:
    if not (method.isascii() and method.isalpha() and method.isupper()):
        raise UsageError("method must be uppercase letters")
    if not path.startswith("/"):
        raise UsageError("path must start with /")
    try:
        status, reply = request(host, port, token or None, method, path, body[0] if body else None)
    except (OSError, http.client.HTTPException) as problem:
        raise Failure(f"no response from {host}:{port}: {problem}") from problem
    print(format_reply(status, reply), file=out)
    return EXIT_OK


def _check(directory: Path, script: Path, out: TextIO) -> int:
    try:
        lines = script.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError) as problem:
        raise Failure(f"cannot read {script}: {problem}") from problem
    clock = ManualClock(CHECK_EPOCH_MS)
    with _opened(directory, clock) as queue:
        server = ServerThread(queue)
        try:
            port = server.start()
        except OSError as problem:
            raise Failure(f"cannot serve: {problem}") from problem
        try:
            play(lines, port, clock, out)
        except ScriptError as problem:
            raise Failure(str(problem)) from problem
        except (OSError, http.client.HTTPException) as problem:
            raise Failure(f"request failed: {problem}") from problem
        finally:
            server.stop()
    return EXIT_OK


def main() -> None:
    raise SystemExit(run(sys.argv[1:], sys.stdout, sys.stderr))
