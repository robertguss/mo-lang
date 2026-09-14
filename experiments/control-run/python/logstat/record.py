"""One log line: `<timestamp> <method> <path> <status> <duration_ms>`."""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from logstat.contracts import require

UINT32_MAX = 4_294_967_295
EPOCH = datetime(1970, 1, 1, tzinfo=UTC)

_TIMESTAMP = re.compile(r"(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z", re.ASCII)
_METHOD = re.compile(r"[A-Z]+", re.ASCII)
_STATUS = re.compile(r"\d{3}", re.ASCII)
_DURATION = re.compile(r"\d{1,10}", re.ASCII)
_CARD = re.compile(r"\d{16,}", re.ASCII)


@dataclass(frozen=True, slots=True)
class Record:
    at: str
    epoch: int
    method: str
    path: str
    status: int
    duration_ms: int

    def __post_init__(self) -> None:
        require(parse_timestamp(self.at) == self.epoch, "at must be a timestamp equal to epoch")
        require(_METHOD.fullmatch(self.method) is not None, "method must be A-Z letters")
        require(self.path.startswith("/"), "path must start with /")
        require(_CARD.search(self.path) is None, "path must not carry a card number")
        require(100 <= self.status <= 599, "status must be 100 to 599")
        require(0 <= self.duration_ms <= UINT32_MAX, "duration_ms must fit UInt32")


@dataclass(frozen=True, slots=True)
class Malformed:
    reason: str


def parse_timestamp(text: str) -> int | None:
    """Seconds since the epoch for `YYYY-MM-DDTHH:MM:SSZ`, or None."""
    match = _TIMESTAMP.fullmatch(text)
    if match is None:
        return None
    year, month, day, hour, minute, second = (int(part) for part in match.groups())
    try:
        moment = datetime(year, month, day, hour, minute, second, tzinfo=UTC)
    except ValueError:
        return None
    return (moment - EPOCH) // timedelta(seconds=1)


def mask_card(path: str) -> str:
    """Replace every digit of a run of 16 or more digits with `*`."""
    return _CARD.sub(lambda match: "*" * len(match.group()), path)


def _bounded_int(pattern: re.Pattern[str], text: str, low: int, high: int) -> int | None:
    if pattern.fullmatch(text) is None:
        return None
    value = int(text)
    return value if low <= value <= high else None


def parse_line(line: str) -> Record | Malformed:
    fields = line.split(" ")
    if len(fields) != 5:
        return Malformed("expected 5 space-separated fields")
    at, method, path, status_text, duration_text = fields
    epoch = parse_timestamp(at)
    if epoch is None:
        return Malformed("bad timestamp")
    if _METHOD.fullmatch(method) is None:
        return Malformed("bad method")
    if not path.startswith("/") or not path.isprintable():
        return Malformed("bad path")
    status = _bounded_int(_STATUS, status_text, 100, 599)
    if status is None:
        return Malformed("status is not 100 to 599")
    duration = _bounded_int(_DURATION, duration_text, 0, UINT32_MAX)
    if duration is None:
        return Malformed("duration_ms does not fit UInt32")
    return Record(at, epoch, method, mask_card(path), status, duration)


def decode_line(raw: bytes) -> Record | Malformed:
    """Parse one raw line; its `\\n` or `\\r\\n` ending is not part of it."""
    body = raw.removesuffix(b"\n").removesuffix(b"\r")
    try:
        text = body.decode("utf-8")
    except UnicodeDecodeError:
        return Malformed("not UTF-8")
    return parse_line(text)
