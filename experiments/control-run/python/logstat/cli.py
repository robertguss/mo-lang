"""`logstat <dir> [--top N] [--since <ISO-8601>] [--json]`: arguments, files, exit codes."""

from __future__ import annotations

import os
import re
import stat
from collections.abc import Sequence
from dataclasses import dataclass
from typing import BinaryIO, TextIO

from logstat.record import Malformed, decode_line, parse_timestamp
from logstat.report import render_json, render_text
from logstat.summary import DEFAULT_TOP, MAX_TOP, MIN_TOP, Summary, Tally

USAGE = "usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"
EXIT_OK = 0
EXIT_NO_LOGS = 1
EXIT_USAGE = 2

_OPEN_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
_TOP = re.compile(r"\d{1,3}", re.ASCII)


class UsageError(Exception):
    """Bad arguments: exit 2 with one line on stderr."""


class RunError(Exception):
    """No log file, or one could not be read: exit 1 with one line on stderr."""


@dataclass(frozen=True, slots=True)
class Options:
    directory: str
    top: int = DEFAULT_TOP
    since: int | None = None
    as_json: bool = False


def parse_top(text: str) -> int:
    top = int(text) if _TOP.fullmatch(text) else 0
    if not MIN_TOP <= top <= MAX_TOP:
        raise UsageError(f"--top must be a whole number from 1 to 100, got {text!r}")
    return top


def parse_since(text: str) -> int:
    since = parse_timestamp(text)
    if since is None:
        raise UsageError(f"--since must look like 2026-09-12T10:00:01Z, got {text!r}")
    return since


def parse_args(argv: Sequence[str]) -> Options:
    positional: list[str] = []
    valued: dict[str, str] = {}
    as_json = False
    rest = iter(argv)
    for arg in rest:
        if arg == "--json":
            if as_json:
                raise UsageError("--json given twice")
            as_json = True
        elif arg in ("--top", "--since"):
            value = next(rest, None)
            if value is None or arg in valued:
                raise UsageError(f"{arg} needs exactly one value")
            valued[arg] = value
        elif arg.startswith("-") and arg != "-":
            raise UsageError(f"unknown option {arg}")
        else:
            positional.append(arg)
    if len(positional) != 1:
        raise UsageError("expected exactly one <dir>")
    top = parse_top(valued["--top"]) if "--top" in valued else DEFAULT_TOP
    since = parse_since(valued["--since"]) if "--since" in valued else None
    return Options(positional[0], top, since, as_json)


def open_directory(path: str) -> int:
    try:
        return os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    except OSError as error:
        raise UsageError(f"{path} is not a readable directory ({error.strerror})") from error


def log_names(dir_fd: int) -> list[str]:
    """Regular `*.log` files directly inside the directory, in name order; no symlinks."""
    with os.scandir(dir_fd) as entries:
        return sorted(
            entry.name
            for entry in entries
            if entry.name.endswith(".log") and entry.is_file(follow_symlinks=False)
        )


def scan_file(dir_fd: int, name: str, since: int | None, tally: Tally) -> None:
    """Fold one file into the tally, a line at a time; the name is relative to dir_fd."""
    try:
        fd = os.open(name, _OPEN_FLAGS, dir_fd=dir_fd)
        with os.fdopen(fd, "rb") as handle:
            if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
                return
            for raw in handle:
                parsed = decode_line(raw)
                if isinstance(parsed, Malformed):
                    tally.add_malformed()
                elif since is None or parsed.epoch >= since:
                    tally.add(parsed)
    except OSError as error:
        raise RunError(f"cannot read {name} ({error.strerror})") from error


def analyze(options: Options) -> Summary:
    dir_fd = open_directory(options.directory)
    try:
        names = log_names(dir_fd)
        if not names:
            raise RunError(f"no .log file in {options.directory}")
        tally = Tally(options.top)
        for name in names:
            scan_file(dir_fd, name, options.since, tally)
        return tally.summary()
    finally:
        os.close(dir_fd)


def main(argv: Sequence[str], stdout: BinaryIO, stderr: TextIO) -> int:
    try:
        options = parse_args(argv)
        summary = analyze(options)
    except UsageError as error:
        stderr.write(f"logstat: {error} ({USAGE})\n")
        return EXIT_USAGE
    except RunError as error:
        stderr.write(f"logstat: {error}\n")
        return EXIT_NO_LOGS
    report = render_json(summary) if options.as_json else render_text(summary)
    stdout.write(report.encode("utf-8"))
    return EXIT_OK
