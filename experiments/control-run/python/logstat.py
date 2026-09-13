#!/usr/bin/env python3
"""logstat <dir> [--top N] [--since <ISO-8601>] [--json]: summarize the *.log files in dir."""

from __future__ import annotations

import io
import re
import sys
from collections.abc import Iterator, Sequence
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import TextIO

from files import list_logs, read_lines
from records import Malformed, Record, parse_raw_line, parse_timestamp
from render import ensure_no_card, render_json, render_text
from tally import TOP_MAX, TOP_MIN, Summary, Tally

USAGE = "usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"
EXIT_OK = 0
EXIT_NO_LOGS = 1
EXIT_USAGE = 2
_SMALL_INT = re.compile(r"-?[0-9]{1,9}")


class UsageError(Exception):
    pass


@dataclass(frozen=True)
class Options:
    directory: Path
    top: int = 5
    since: datetime | None = None
    as_json: bool = False


def parse_top(text: str) -> int:
    if _SMALL_INT.fullmatch(text) is None:
        raise UsageError(f"--top wants a whole number, got {text!r}")
    top = int(text)
    if not TOP_MIN <= top <= TOP_MAX:
        raise UsageError(f"--top must be {TOP_MIN} to {TOP_MAX}, got {top}")
    return top


def parse_since(text: str) -> datetime:
    since = parse_timestamp(text)
    if since is None:
        raise UsageError(f"--since wants a timestamp like 2026-09-12T10:00:00Z, got {text!r}")
    return since


def parse_args(argv: Sequence[str]) -> Options:
    values: dict[str, str] = {}
    positional: list[str] = []
    args = iter(argv)
    for arg in args:
        if arg in values:
            raise UsageError(f"{arg} given twice")
        if arg == "--json":
            values[arg] = ""
        elif arg in ("--top", "--since"):
            values[arg] = next(args, None) or _missing(arg)
        elif arg.startswith("-"):
            raise UsageError(f"unknown option {arg}")
        else:
            positional.append(arg)
    if len(positional) != 1:
        raise UsageError("expected exactly one directory")
    return _options(positional[0], values)


def _missing(option: str) -> str:
    raise UsageError(f"{option} needs a value")


def _options(directory: str, values: dict[str, str]) -> Options:
    return Options(
        directory=Path(directory),
        top=parse_top(values["--top"]) if "--top" in values else 5,
        since=parse_since(values["--since"]) if "--since" in values else None,
        as_json="--json" in values,
    )


def find_logs(directory: Path) -> list[Path]:
    if not directory.is_dir():
        raise UsageError(f"{directory} is not a directory")
    try:
        return list_logs(directory)
    except OSError as error:
        raise UsageError(f"cannot list {directory}: {error.strerror}") from error


def parsed_lines(options: Options, logs: list[Path]) -> Iterator[Record | Malformed]:
    for log in logs:
        for raw in read_lines(options.directory, log):
            parsed = parse_raw_line(raw)
            if isinstance(parsed, Malformed) or options.since is None or parsed.at >= options.since:
                yield parsed


def summarize_logs(options: Options, logs: list[Path]) -> Summary:
    tally = Tally(options.top)
    for parsed in parsed_lines(options, logs):
        if isinstance(parsed, Malformed):
            tally.add_malformed()
        else:
            tally.add(parsed)
    return tally.finish()


def main(argv: Sequence[str], out: TextIO, err: TextIO) -> int:
    try:
        options = parse_args(argv)
        logs = find_logs(options.directory)
    except UsageError as error:
        err.write(f"logstat: {error}; {USAGE}\n")
        return EXIT_USAGE
    if not logs:
        err.write(f"logstat: no .log file in {options.directory}\n")
        return EXIT_NO_LOGS
    try:
        summary = summarize_logs(options, logs)
    except OSError as error:
        err.write(f"logstat: cannot read {error.filename}: {error.strerror}\n")
        return EXIT_NO_LOGS
    report = render_json(summary) if options.as_json else render_text(summary)
    out.write(ensure_no_card(report))
    return EXIT_OK


if __name__ == "__main__":
    stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", newline="\n")
    status = main(sys.argv[1:], stdout, sys.stderr)
    stdout.flush()
    sys.exit(status)
