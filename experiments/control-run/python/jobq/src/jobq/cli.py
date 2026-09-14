"""The entry point: `serve`, `compact`, `client`, and `check`. Exit 2 on a usage error, 1 if
`<dir>` cannot be opened or the port cannot be bound."""

import asyncio
import re
import signal
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import TextIO

from jobq import client
from jobq.server import HOST, HttpServer, ServerThread, serve
from jobq.store import StoreOpenError, compact

USAGE = (
    "usage: jobq serve <dir> [--port N] | jobq compact <dir> | "
    "jobq client <host> <port> <token> <method> <path> [<json>] | jobq check <dir> <script>"
)
DEFAULT_PORT = 7900
EXIT_OK, EXIT_FAILURE, EXIT_USAGE = 0, 1, 2
NO_TOKEN = "-"  # noqa: S105 - the word for "send no authorization header"

_DIGITS = re.compile(r"[0-9]{1,5}")
_METHOD = re.compile(r"[A-Z]{1,16}")


class UsageError(Exception):
    def __init__(self, problem: str) -> None:
        super().__init__(f"jobq: {problem} ({USAGE})")


def run(argv: Sequence[str], stdout: TextIO, stderr: TextIO) -> int:
    try:
        return _dispatch(list(argv), stdout, stderr)
    except UsageError as usage:
        print(usage, file=stderr)
        return EXIT_USAGE


def _dispatch(argv: list[str], stdout: TextIO, stderr: TextIO) -> int:
    match argv:
        case ["serve", directory]:
            return _serve(Path(directory), DEFAULT_PORT, stderr)
        case ["serve", directory, "--port", port]:
            return _serve(Path(directory), parse_port(port, allow_zero=True), stderr)
        case ["compact", directory]:
            return _compact(Path(directory), stdout, stderr)
        case ["client", host, port, *words] if 3 <= len(words) <= 4:
            return _client(host, parse_port(port, allow_zero=False), words, stdout, stderr)
        case ["check", directory, script]:
            return _check(Path(directory), Path(script), stdout, stderr)
        case _:
            raise UsageError("unknown command or wrong arguments")


def parse_port(text: str, allow_zero: bool) -> int:
    port = int(text) if _DIGITS.fullmatch(text) else -1
    if not (0 if allow_zero else 1) <= port <= 65535:
        raise UsageError(f"port must be a number up to 65535, got {text!r}")
    return port


def parse_call(words: Sequence[str]) -> client.Call:
    """`<token> <method> <path> [<json>]`; the token `-` sends no authorization header."""
    token, method, path, *body = words
    if not token:
        raise UsageError("token must not be empty; use - for none")
    if _METHOD.fullmatch(method) is None:
        raise UsageError(f"method must be upper-case letters, got {method!r}")
    if not path.startswith("/"):
        raise UsageError(f"path must start with /, got {path!r}")
    return client.Call(None if token == NO_TOKEN else token, method, path, body[0] if body else None)


def _serve(directory: Path, port: int, stderr: TextIO) -> int:
    async def main() -> None:
        stop = asyncio.Event()
        loop = asyncio.get_running_loop()
        for signum in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(signum, stop.set)

        def ready(server: HttpServer) -> None:
            print(f"jobq: serving {directory} on http://{HOST}:{server.port}", file=stderr)
            stderr.flush()

        await serve(directory, port, ready, stop)

    try:
        asyncio.run(main())
    except StoreOpenError as unopened:
        print(f"jobq: {unopened}", file=stderr)
        return EXIT_FAILURE
    except OSError as unbound:
        print(f"jobq: cannot listen on port {port}: {unbound.strerror}", file=stderr)
        return EXIT_FAILURE
    return EXIT_OK


def _compact(directory: Path, stdout: TextIO, stderr: TextIO) -> int:
    try:
        before, after = compact(directory)
    except StoreOpenError as unopened:
        print(f"jobq: {unopened}", file=stderr)
        return EXIT_FAILURE
    print(f"jobq: compacted {directory}: {before} records to {after}", file=stdout)
    return EXIT_OK


def _client(host: str, port: int, words: Sequence[str], stdout: TextIO, stderr: TextIO) -> int:
    call = parse_call(words)
    try:
        response = client.request(host, port, call)
    except OSError as unreachable:
        print(f"jobq: cannot reach {host}:{port}: {unreachable}", file=stderr)
        return EXIT_FAILURE
    stdout.write(client.render(response))
    return EXIT_OK


def read_script(script: Path) -> list[tuple[str, client.Call]]:
    """The script's calls with their lines; blank lines and `#` comments are skipped."""
    calls = []
    for number, line in enumerate(script.read_text().splitlines(), start=1):
        if not line.strip() or line.startswith("#"):
            continue
        words = line.split(" ", 3)
        if len(words) < 3:
            raise UsageError(f"{script} line {number}: expected <token> <method> <path> [<json>]")
        calls.append((line, parse_call(words)))
    return calls


def _check(directory: Path, script: Path, stdout: TextIO, stderr: TextIO) -> int:
    try:
        calls = read_script(script)
    except OSError as unreadable:
        print(f"jobq: cannot read {script}: {unreadable.strerror}", file=stderr)
        return EXIT_FAILURE
    try:
        with ServerThread(directory) as server:
            for line, call in calls:
                response = client.request(HOST, server.port, call)
                stdout.write(f"> {line}\n{client.render(response)}")
    except StoreOpenError as unopened:
        print(f"jobq: {unopened}", file=stderr)
        return EXIT_FAILURE
    except OSError as failed:
        print(f"jobq: check failed: {failed}", file=stderr)
        return EXIT_FAILURE
    return EXIT_OK


def main() -> None:
    sys.exit(run(sys.argv[1:], sys.stdout, sys.stderr))
