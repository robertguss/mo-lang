"""logstat <dir> [--top N] [--since <ISO-8601>] [--json]: summarise the *.log files directly inside <dir>."""

from __future__ import annotations

import os
import stat
import sys
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from typing import BinaryIO

from contracts import require
from parse import Malformed, mask_cards, parse_raw, parse_timestamp
from report import render_json, render_text
from stats import TOP_MAX, TOP_MIN, Tally

USAGE = "usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"
EXIT_OK = 0
EXIT_FAILURE = 1
EXIT_USAGE = 2
DEFAULT_TOP = 5
_OPTIONS = ("--top", "--since", "--json")
_OPEN_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK


class UsageError(Exception):
    """A bad command line: one line on stderr, exit code 2."""


class ReadFailure(Exception):
    """No .log file, or a directory or file that could not be read: one line on stderr, exit code 1."""


@dataclass(frozen=True, slots=True)
class Options:
    directory: str
    top: int = DEFAULT_TOP
    since: int | None = None
    json: bool = False


def shown(text: str) -> str:
    """A user-supplied name as it may appear in a message: quoted, escaped, card numbers masked."""
    return mask_cards(repr(text))


def parse_args(argv: Sequence[str]) -> Options:
    positional, options = split_args(argv)
    if len(positional) != 1:
        raise UsageError(f"expected one <dir>, got {len(positional)}")
    since = options.get("--since")
    return Options(
        directory=positional[0],
        top=parse_top(options.get("--top", str(DEFAULT_TOP))),
        since=None if since is None else parse_since(since),
        json="--json" in options,
    )


def split_args(argv: Sequence[str]) -> tuple[list[str], dict[str, str]]:
    """Positionals, and each option given at most once with its value (`""` for `--json`)."""
    positional: list[str] = []
    options: dict[str, str] = {}
    args = iter(argv)
    for arg in args:
        if arg not in _OPTIONS:
            if arg.startswith("-"):
                raise UsageError(f"unknown option {shown(arg)}")
            positional.append(arg)
        elif arg in options:
            raise UsageError(f"{arg} given twice")
        else:
            options[arg] = "" if arg == "--json" else option_value(arg, next(args, None))
    return positional, options


def option_value(option: str, value: str | None) -> str:
    if value is None:
        raise UsageError(f"{option} needs a value")
    return value


def parse_top(text: str) -> int:
    """`--top N` outside 1 to 100 is a usage error, not a clamp."""
    if not (text.isascii() and text.isdigit()) or len(text.lstrip("0")) > 3:
        raise UsageError(f"--top needs a whole number 1 to 100, got {shown(text)}")
    top = int(text)
    if not TOP_MIN <= top <= TOP_MAX:
        raise UsageError(f"--top must be 1 to 100, got {top}")
    return top


def parse_since(text: str) -> int:
    try:
        return parse_timestamp(text)
    except Malformed as exc:
        raise UsageError(f"--since needs a timestamp like 2026-09-12T10:00:00Z, got {shown(text)}") from exc


def list_logs(directory: str) -> list[str]:
    """Names of the regular, non-hidden `*.log` files directly inside the directory, in code-point order."""
    try:
        with os.scandir(directory) as entries:
            return sorted(entry.name for entry in entries if is_log(entry))
    except OSError as exc:
        raise ReadFailure(f"cannot list {shown(directory)}: {exc.strerror}") from exc


def is_log(entry: os.DirEntry[str]) -> bool:
    name = entry.name
    return name.endswith(".log") and not name.startswith(".") and entry.is_file(follow_symlinks=False)


def open_log(directory: str, name: str) -> BinaryIO:
    """Open a regular file directly inside the directory for reading, never through a symlink."""
    require(name not in ("", ".", "..") and os.path.basename(name) == name, "name is a direct child of <dir>")
    path = os.path.join(directory, name)
    if os.path.dirname(os.path.realpath(path)) != os.path.realpath(directory):
        raise ReadFailure(f"{shown(name)} resolves outside {shown(directory)}")
    try:
        stream = os.fdopen(os.open(path, _OPEN_FLAGS), "rb")
    except OSError as exc:
        raise ReadFailure(f"cannot open {shown(name)}: {exc.strerror}") from exc
    if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
        stream.close()
        raise ReadFailure(f"{shown(name)} is not a regular file")
    return stream


def tally_log(tally: Tally, directory: str, name: str, since: int | None) -> None:
    with open_log(directory, name) as stream:
        try:
            tally_lines(tally, stream, since)
        except OSError as exc:
            raise ReadFailure(f"cannot read {shown(name)}: {exc.strerror}") from exc


def tally_lines(tally: Tally, lines: Iterable[bytes], since: int | None) -> None:
    """A malformed line is counted and skipped; a line before `since` is skipped uncounted."""
    for raw in lines:
        try:
            record = parse_raw(raw)
        except Malformed:
            tally.add_malformed()
            continue
        if since is None or record.instant >= since:
            tally.add(record)


def run(options: Options) -> str:
    """The rendered report; raises UsageError or ReadFailure."""
    if not os.path.isdir(options.directory):
        raise UsageError(f"{shown(options.directory)} is not a directory")
    names = list_logs(options.directory)
    if not names:
        raise ReadFailure(f"no .log file in {shown(options.directory)}")
    tally = Tally(options.top)
    for name in names:
        tally_log(tally, options.directory, name, options.since)
    summary = tally.summary()
    return render_json(summary) if options.json else render_text(summary)


def main(argv: Sequence[str], stdout: BinaryIO, stderr: BinaryIO) -> int:
    try:
        report = run(parse_args(argv))
    except UsageError as exc:
        return fail(stderr, f"logstat: {exc}; {USAGE}", EXIT_USAGE)
    except ReadFailure as exc:
        return fail(stderr, f"logstat: {exc}", EXIT_FAILURE)
    try:
        stdout.write(report.encode("utf-8"))
        stdout.flush()
    except BrokenPipeError:
        silence(stdout)
        return EXIT_FAILURE
    return EXIT_OK


def fail(stderr: BinaryIO, message: str, code: int) -> int:
    stderr.write((message + "\n").encode("utf-8", "backslashreplace"))
    stderr.flush()
    return code


def silence(stream: BinaryIO) -> None:
    """After the reader closed the pipe, point the descriptor at /dev/null so the exit-time flush stays quiet."""
    os.dup2(os.open(os.devnull, os.O_WRONLY), stream.fileno())


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:], sys.stdout.buffer, sys.stderr.buffer))
