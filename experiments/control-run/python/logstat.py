"""logstat <dir> [--top N] [--since <ISO-8601>] [--json]: summarize the `*.log` files in a directory."""

import io
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime
from typing import TextIO

from files import OutsideDirectory, list_log_files, read_lines, resolve_directory
from parse import MalformedLine, decode_line, parse_line, parse_timestamp
from render import render_json, render_text
from summary import TOP_MAX, TOP_MIN, Accumulator, Summary

USAGE = "usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"
EXIT_OK = 0
EXIT_NO_LOGS = 1
EXIT_USAGE = 2


class UsageError(ValueError):
    """Bad command-line arguments; reported on one stderr line with exit code 2."""


@dataclass(frozen=True)
class Options:
    directory: str
    top: int = 5
    since: datetime | None = None
    json: bool = False


def parse_top(text: str) -> int:
    if not text.isascii() or not text.isdigit():
        raise UsageError(f"--top expects a whole number from {TOP_MIN} to {TOP_MAX}, got {text!r}")
    top = int(text)
    if not TOP_MIN <= top <= TOP_MAX:
        raise UsageError(f"--top must be from {TOP_MIN} to {TOP_MAX}, got {top}")
    return top


def parse_since(text: str) -> datetime:
    try:
        return parse_timestamp(text)
    except MalformedLine as error:
        raise UsageError(f"--since: {error}") from error


def take_value(args: list[str], flag: str) -> str:
    if not args:
        raise UsageError(f"{flag} needs a value")
    return args.pop(0)


def parse_args(argv: Sequence[str]) -> Options:
    args = list(argv)
    seen: set[str] = set()
    directories: list[str] = []
    top, since, as_json = 5, None, False
    while args:
        arg = args.pop(0)
        if arg in seen:
            raise UsageError(f"{arg} given twice")
        if arg == "--top":
            top = parse_top(take_value(args, arg))
        elif arg == "--since":
            since = parse_since(take_value(args, arg))
        elif arg == "--json":
            as_json = True
        elif arg.startswith("-"):
            raise UsageError(f"unknown option {arg}")
        else:
            directories.append(arg)
            continue
        seen.add(arg)
    if len(directories) != 1:
        raise UsageError(f"expected one directory, got {len(directories)}")
    return Options(directories[0], top, since, as_json)


def summarize_directory(options: Options, stderr: TextIO) -> Summary | None:
    """Stream every log file into one Summary; None when there is no `.log` file."""
    try:
        root = resolve_directory(options.directory)
        paths = list_log_files(root)
    except OSError as error:
        raise UsageError(f"{options.directory} is not a readable directory ({error.strerror or error})") from error
    if not paths:
        print(f"logstat: no .log file in {options.directory}", file=stderr)
        return None
    accumulator = Accumulator(options.top)
    for path in paths:
        for raw in read_lines(root, path):
            try:
                record = parse_line(decode_line(raw))
            except MalformedLine:
                accumulator.add_malformed()
                continue
            if options.since is None or record.at >= options.since:
                accumulator.add(record)
    return accumulator.finish()


def main(argv: Sequence[str], stdout: TextIO, stderr: TextIO) -> int:
    try:
        options = parse_args(argv)
        summary = summarize_directory(options, stderr)
    except UsageError as error:
        print(f"logstat: {error}; {USAGE}", file=stderr)
        return EXIT_USAGE
    except (OSError, OutsideDirectory) as error:
        print(f"logstat: {error}", file=stderr)
        return EXIT_NO_LOGS
    if summary is None:
        return EXIT_NO_LOGS
    stdout.write(render_json(summary) if options.json else render_text(summary))
    return EXIT_OK


if __name__ == "__main__":
    if isinstance(sys.stdout, io.TextIOWrapper):
        sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main(sys.argv[1:], sys.stdout, sys.stderr))
