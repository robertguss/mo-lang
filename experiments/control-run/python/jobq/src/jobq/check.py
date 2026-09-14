"""`jobq check`: play a script of requests through the client against a served queue.

A line is `<token> <method> <path> [<json>]`; `-` as the token sends no authorization.
`advance <ms>` moves the check's clock, blank lines and `#` comments are skipped."""

from collections.abc import Iterable
from typing import TextIO

from jobq.client import format_reply, request
from jobq.clock import ManualClock
from jobq.server import HOST

CHECK_EPOCH_MS = 1_767_225_600_000
NO_TOKEN = "-"


class ScriptError(Exception):
    pass


def play(lines: Iterable[str], port: int, clock: ManualClock, out: TextIO) -> None:
    for number, line in enumerate(lines, start=1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        fields = line.split(maxsplit=3)
        if fields[0] == "advance":
            if len(fields) != 2 or not (fields[1].isascii() and fields[1].isdigit()):
                raise ScriptError(f"line {number}: expected advance <ms>")
            clock.advance(int(fields[1]))
            out.write(f"> {line}\n")
            continue
        if len(fields) < 3:
            raise ScriptError(f"line {number}: expected <token> <method> <path> [<json>]")
        token, method, path = fields[:3]
        body = fields[3] if len(fields) == 4 else None
        status, reply = request(
            HOST, port, None if token == NO_TOKEN else token, method, path, body
        )
        out.write(f"> {line}\n< {format_reply(status, reply)}\n")
