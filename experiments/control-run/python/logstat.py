"""logstat: summarize request logs in a directory.

Usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]

Reads every *.log file directly inside <dir>, in name order, one file at a
time, and prints request and error counts, requests per minute, the slowest
requests, and the busiest paths. A malformed line is counted and skipped.
Exit 0 on success, 2 on a usage error, 1 if no .log file was found or one
could not be read.
"""

from __future__ import annotations

import heapq
import json
import os
import re
import stat
import sys
from collections.abc import Callable, Iterable, Iterator, Sequence
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, BinaryIO, TextIO, TypeVar

UINT32_MAX = 4_294_967_295
TOP_DEFAULT = 5
TOP_MIN = 1
TOP_MAX = 100
T = TypeVar("T")
USAGE = "usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"

EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)
ONE_MICROSECOND = timedelta(microseconds=1)
MICROS_PER_MINUTE = 60_000_000

_TIMESTAMP = re.compile(
    r"([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})"
    r"(?:\.([0-9]{1,6}))?(Z|[+-][0-9]{2}:[0-9]{2})"
)
_METHOD = re.compile(r"[A-Z]+")
_DIGITS = re.compile(r"[0-9]{1,20}")
_CARD = re.compile(r"[0-9]{16,}")


class ContractViolation(Exception):
    """A requires or ensures check failed: a bug in the caller, never bad input."""


class UsageError(Exception):
    """The command line was wrong. Exit 2."""


class ReadError(Exception):
    """No .log file was found, or one could not be read. Exit 1."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractViolation(message)


# ---------------------------------------------------------------- parsing


@dataclass(frozen=True)
class Timestamp:
    text: str
    micros: int  # since the Unix epoch, UTC


def _zone(text: str) -> timezone | None:
    if text == "Z":
        return timezone.utc
    hours, minutes = int(text[1:3]), int(text[4:6])
    if hours > 23 or minutes > 59:
        return None
    offset = timedelta(hours=hours, minutes=minutes)
    return timezone(-offset if text[0] == "-" else offset)


def parse_timestamp(text: str) -> Timestamp | None:
    """A date, a time with seconds, optional 1-6 fraction digits, and Z or an offset."""
    match = _TIMESTAMP.fullmatch(text)
    if match is None:
        return None
    zone = _zone(match.group(8))
    if zone is None:
        return None
    year, month, day, hour, minute, second = (int(g) for g in match.groups()[:6])
    micro = int((match.group(7) or "").ljust(6, "0"))
    try:
        moment = datetime(year, month, day, hour, minute, second, micro, tzinfo=zone)
        return Timestamp(text, (moment - EPOCH) // ONE_MICROSECOND)
    except (ValueError, OverflowError):
        return None


def mask_cards(text: str) -> str:
    """Replace every digit of a run of 16 or more digits with '*'."""
    masked = _CARD.sub(lambda m: "*" * len(m.group()), text)
    require(_CARD.search(masked) is None, "ensures: no card number survives masking")
    return masked


def _valid_path(path: str) -> bool:
    return path.startswith("/") and " " not in path and path.isprintable()


@dataclass(frozen=True)
class Record:
    at: Timestamp
    method: str
    path: str
    status: int
    duration_ms: int

    def __post_init__(self) -> None:
        require(100 <= self.status <= 599, f"requires: status 100 to 599, got {self.status}")
        require(
            0 <= self.duration_ms <= UINT32_MAX,
            f"requires: duration_ms fits UInt32, got {self.duration_ms}",
        )
        require(_METHOD.fullmatch(self.method) is not None, "requires: method is A-Z letters")
        require(_valid_path(self.path), "requires: path starts with / and is printable")
        require(_CARD.search(self.path) is None, "requires: path holds no card number")

    @property
    def is_error(self) -> bool:
        return 500 <= self.status <= 599


@dataclass(frozen=True)
class Malformed:
    reason: str


def _number(text: str, limit: int) -> int | None:
    if _DIGITS.fullmatch(text) is None:
        return None
    value = int(text)
    return value if value <= limit else None


def parse_line(line: str) -> Record | Malformed:
    """Total: never raises, for any string."""
    fields = line.split(" ")
    if len(fields) != 5:
        return Malformed("expected 5 fields separated by single spaces")
    at_text, method, path, status_text, duration_text = fields
    at = parse_timestamp(at_text)
    if at is None:
        return Malformed("timestamp")
    if _METHOD.fullmatch(method) is None:
        return Malformed("method")
    if not _valid_path(path):
        return Malformed("path")
    status = _number(status_text, 599)
    if status is None or status < 100:
        return Malformed("status")
    duration = _number(duration_text, UINT32_MAX)
    if duration is None:
        return Malformed("duration_ms")
    return Record(at, method, mask_cards(path), status, duration)


def decode_line(raw: bytes) -> str | None:
    """Strip one \\n or \\r\\n terminator and decode UTF-8; None if not UTF-8."""
    if raw.endswith(b"\n"):
        raw = raw[:-1]
        if raw.endswith(b"\r"):
            raw = raw[:-1]
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return None


# ---------------------------------------------------------------- summary


@dataclass(frozen=True)
class Slow:
    ms: int
    method: str
    path: str
    at: Timestamp


@dataclass(frozen=True)
class Busy:
    count: int
    method: str
    path: str


def slow_key(entry: Slow) -> tuple[int, int]:
    return (-entry.ms, entry.at.micros)


def busy_key(entry: Busy) -> tuple[int, str, str]:
    return (-entry.count, entry.path, entry.method)


@dataclass(frozen=True)
class Summary:
    requests: int
    errors: int
    successes: int
    malformed: int
    per_minute: float
    slowest: tuple[Slow, ...]
    busiest: tuple[Busy, ...]

    def __post_init__(self) -> None:
        require(self.errors >= 0 and self.successes >= 0, "requires: counts are not negative")
        require(self.requests == self.errors + self.successes, "requires: requests == errors + successes")
        require(self.errors <= self.requests, "requires: errors <= requests")
        require(self.malformed >= 0, "requires: malformed is not negative")
        require(self.per_minute >= 0.0, "requires: per_minute is not negative")
        require(len(self.slowest) <= self.requests, "requires: no more slowest than requests")
        require(_sorted_by(self.slowest, slow_key), "requires: slowest by ms desc, then at asc")
        require(_sorted_by(self.busiest, busy_key), "requires: busiest by count desc, then path asc")

    @property
    def error_rate(self) -> float:
        return self.errors / self.requests if self.requests else 0.0


def _sorted_by(items: Sequence[T], key: Callable[[T], Any]) -> bool:
    return list(items) == sorted(items, key=key)


def per_minute(requests: int, first_micros: int, last_micros: int) -> float:
    span = last_micros - first_micros
    if requests < 2 or span <= 0:
        return 0.0
    return requests / (span / MICROS_PER_MINUTE)


class Tally:
    """Accumulates records one at a time; holds at most `top` slow requests."""

    def __init__(self, top: int, since: Timestamp | None = None) -> None:
        require(TOP_MIN <= top <= TOP_MAX, f"requires: top 1 to 100, got {top}")
        self.top = top
        self.since = since
        self.errors = 0
        self.successes = 0
        self.malformed = 0
        self.first: int | None = None
        self.last: int | None = None
        self.counts: dict[tuple[str, str], int] = {}
        self._slow: list[tuple[int, int, int, Record]] = []  # a min-heap, least slow first
        self._seen = 0

    def add_raw(self, raw: bytes) -> None:
        text = decode_line(raw)
        parsed = Malformed("not UTF-8") if text is None else parse_line(text)
        if isinstance(parsed, Malformed):
            self.malformed += 1
        else:
            self.add(parsed)

    def add(self, record: Record) -> None:
        moment = record.at.micros
        if self.since is not None and moment < self.since.micros:
            return
        if record.is_error:
            self.errors += 1
        else:
            self.successes += 1
        self.first = moment if self.first is None else min(self.first, moment)
        self.last = moment if self.last is None else max(self.last, moment)
        key = (record.method, record.path)
        self.counts[key] = self.counts.get(key, 0) + 1
        self._seen += 1
        entry = (record.duration_ms, -moment, -self._seen, record)
        if len(self._slow) < self.top:
            heapq.heappush(self._slow, entry)
        else:
            heapq.heappushpop(self._slow, entry)

    def summary(self) -> Summary:
        requests = self.errors + self.successes
        ranked = sorted(self._slow, reverse=True)
        slowest = tuple(Slow(r.duration_ms, r.method, r.path, r.at) for *_, r in ranked)
        busy = (Busy(count, method, path) for (method, path), count in self.counts.items())
        busiest = tuple(sorted(busy, key=busy_key)[: self.top])
        rate = per_minute(requests, self.first or 0, self.last or 0)
        return Summary(requests, self.errors, self.successes, self.malformed, rate, slowest, busiest)


def summarize(records: Iterable[Record], top: int = TOP_DEFAULT, malformed: int = 0) -> Summary:
    tally = Tally(top)
    for record in records:
        tally.add(record)
    tally.malformed = malformed
    return tally.summary()


# ---------------------------------------------------------------- output


def format_count(n: int) -> str:
    require(n >= 0, f"requires: a count is not negative, got {n}")
    return f"{n:_}"


def _head_line(label: str, value: str) -> str:
    return label + value.rjust(max(16 - len(label), len(value) + 1))


def render_head(s: Summary) -> list[str]:
    return [
        _head_line("requests", format_count(s.requests)),
        _head_line("errors", format_count(s.errors)) + f"  ({s.error_rate * 100:.1f}%)",
        _head_line("malformed", format_count(s.malformed)),
        _head_line("per minute", f"{s.per_minute:_.1f}"),
    ]


def render_slowest(s: Summary) -> list[str]:
    ms = [format_count(e.ms) for e in s.slowest]
    what = [f"{e.method} {e.path}" for e in s.slowest]
    ms_width = max(map(len, ms), default=0)
    what_width = max(map(len, what), default=0)
    rows = [
        f"  {m.rjust(ms_width)} ms  {w.ljust(what_width)}   {e.at.text}"
        for m, w, e in zip(ms, what, s.slowest)
    ]
    return ["slowest", *rows]


def render_busiest(s: Summary) -> list[str]:
    counts = [format_count(e.count) for e in s.busiest]
    width = max(map(len, counts), default=0)
    rows = [f"  {c.rjust(width)}  {e.method} {e.path}" for c, e in zip(counts, s.busiest)]
    return ["busiest", *rows]


def render_text(s: Summary) -> str:
    lines = [*render_head(s), "", *render_slowest(s), "", *render_busiest(s)]
    return "\n".join(lines) + "\n"


def render_json(s: Summary) -> str:
    document = {
        "requests": s.requests,
        "errors": s.errors,
        "error_rate": round(s.error_rate, 3),
        "malformed": s.malformed,
        "per_minute": round(s.per_minute, 1),
        "slowest": [{"ms": e.ms, "method": e.method, "path": e.path, "at": e.at.text} for e in s.slowest],
        "busiest": [{"count": e.count, "method": e.method, "path": e.path} for e in s.busiest],
    }
    return json.dumps(document, ensure_ascii=False) + "\n"


# ---------------------------------------------------------------- command line


@dataclass(frozen=True)
class Options:
    directory: str
    top: int = TOP_DEFAULT
    since: Timestamp | None = None
    as_json: bool = False


def parse_top(text: str) -> int:
    value = _number(text, 10**20)
    if value is None or not TOP_MIN <= value <= TOP_MAX:
        raise UsageError(f"--top must be a whole number from 1 to 100, got {text!r}")
    return value


def parse_since(text: str) -> Timestamp:
    since = parse_timestamp(text)
    if since is None:
        raise UsageError(f"--since must be an ISO-8601 timestamp like 2026-09-12T10:00:00Z, got {text!r}")
    return since


def _value(argv: Sequence[str], i: int) -> str:
    if i + 1 >= len(argv):
        raise UsageError(f"{argv[i]} needs a value")
    return argv[i + 1]


def parse_args(argv: Sequence[str]) -> Options:
    directories: list[str] = []
    flags: dict[str, str] = {}
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in flags:
            raise UsageError(f"{arg} given twice")
        if arg in ("--top", "--since"):
            flags[arg] = _value(argv, i)
            i += 2
            continue
        if arg == "--json":
            flags[arg] = ""
        elif arg.startswith("-"):
            raise UsageError(f"unknown option {arg!r}")
        else:
            directories.append(arg)
        i += 1
    if len(directories) != 1:
        raise UsageError("expected exactly one <dir>")
    top = parse_top(flags["--top"]) if "--top" in flags else TOP_DEFAULT
    since = parse_since(flags["--since"]) if "--since" in flags else None
    return Options(directories[0], top, since, "--json" in flags)


# ---------------------------------------------------------------- files


def open_directory(directory: str) -> int:
    try:
        return os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
    except OSError as error:
        raise UsageError(f"cannot open directory {directory!r}: {error.strerror}") from error


def log_names(dir_fd: int) -> list[str]:
    """Regular files (not symlinks) named *.log directly inside the directory, in name order."""
    with os.scandir(dir_fd) as entries:
        names = [
            e.name
            for e in entries
            if e.name.endswith(".log") and not e.name.startswith(".") and e.is_file(follow_symlinks=False)
        ]
    return sorted(names)


def read_lines(dir_fd: int, name: str) -> Iterator[bytes]:
    """Lines of one file directly inside the directory; never follows a symlink out of it."""
    require("/" not in name and name not in (".", ".."), f"requires: a bare file name, got {name!r}")
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=dir_fd)
    except OSError as error:
        raise ReadError(f"cannot read {name}: {error.strerror}") from error
    with os.fdopen(fd, "rb") as file:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ReadError(f"cannot read {name}: not a regular file")
        try:
            yield from file
        except OSError as error:
            raise ReadError(f"cannot read {name}: {error.strerror}") from error


def analyze(options: Options) -> Summary:
    dir_fd = open_directory(options.directory)
    try:
        names = log_names(dir_fd)
        if not names:
            raise ReadError(f"no .log file in {options.directory}")
        tally = Tally(options.top, options.since)
        for name in names:
            for raw in read_lines(dir_fd, name):
                tally.add_raw(raw)
        return tally.summary()
    finally:
        os.close(dir_fd)


def main(argv: Sequence[str], stdout: BinaryIO, stderr: TextIO) -> int:
    try:
        options = parse_args(argv)
        summary = analyze(options)
    except UsageError as error:
        stderr.write(f"logstat: {error} ({USAGE})\n")
        return 2
    except ReadError as error:
        stderr.write(f"logstat: {error}\n")
        return 1
    report = render_json(summary) if options.as_json else render_text(summary)
    try:
        stdout.write(report.encode("utf-8"))
        stdout.flush()
    except BrokenPipeError:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:], sys.stdout.buffer, sys.stderr))
