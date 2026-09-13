"""Parsing one log line into a Record, or raising MalformedLine."""

import re
from dataclasses import dataclass
from datetime import datetime, timezone

from mask import mask_card_numbers

UINT32_MAX = 4_294_967_295
TIMESTAMP = re.compile(r"([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})Z")
METHOD = re.compile(r"[A-Z]+")
DIGITS = re.compile(r"[0-9]+")


class MalformedLine(ValueError):
    """A line that does not fit `<timestamp> <method> <path> <status> <duration_ms>`."""


@dataclass(frozen=True)
class Record:
    at: datetime
    method: str
    path: str
    status: int
    duration_ms: int

    def __post_init__(self) -> None:
        if not 100 <= self.status <= 599:
            raise ValueError(f"status {self.status} is outside 100 to 599")
        if not 0 <= self.duration_ms <= UINT32_MAX:
            raise ValueError(f"duration_ms {self.duration_ms} does not fit UInt32")
        if self.at.utcoffset() is None:
            raise ValueError("timestamp must be timezone-aware")
        if not METHOD.fullmatch(self.method):
            raise ValueError(f"method {self.method!r} is not uppercase letters")
        if not self.path.startswith("/") or mask_card_numbers(self.path) != self.path:
            raise ValueError("path must start with / and carry no card number")

    @property
    def is_error(self) -> bool:
        return 500 <= self.status <= 599

    @property
    def at_text(self) -> str:
        return format_timestamp(self.at)


def parse_timestamp(text: str) -> datetime:
    """Parse `YYYY-MM-DDTHH:MM:SSZ` as a UTC instant, or raise MalformedLine."""
    match = TIMESTAMP.fullmatch(text)
    if match is None:
        raise MalformedLine(f"timestamp {text!r} is not YYYY-MM-DDTHH:MM:SSZ")
    year, month, day, hour, minute, second = (int(part) for part in match.groups())
    try:
        return datetime(year, month, day, hour, minute, second, tzinfo=timezone.utc)
    except ValueError as error:
        raise MalformedLine(f"timestamp {text!r}: {error}") from error


def format_timestamp(at: datetime) -> str:
    return at.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_number(text: str, low: int, high: int, name: str) -> int:
    """Parse ASCII digits only (no sign, `_`, or spaces) within low..high."""
    if DIGITS.fullmatch(text) is None:
        raise MalformedLine(f"{name} {text!r} is not a number")
    value = int(text)
    if not low <= value <= high:
        raise MalformedLine(f"{name} {value} is outside {low} to {high}")
    return value


def parse_line(line: str) -> Record:
    """Parse one line (without its line ending); raise MalformedLine if it does not fit."""
    fields = line.split(" ")
    if len(fields) != 5:
        raise MalformedLine(f"expected 5 space-separated fields, got {len(fields)}")
    stamp, method, path, status, duration = fields
    if METHOD.fullmatch(method) is None:
        raise MalformedLine(f"method {method!r} is not uppercase letters")
    if not path.startswith("/"):
        raise MalformedLine(f"path {mask_card_numbers(path)!r} does not start with /")
    return Record(
        at=parse_timestamp(stamp),
        method=method,
        path=mask_card_numbers(path),
        status=parse_number(status, 100, 599, "status"),
        duration_ms=parse_number(duration, 0, UINT32_MAX, "duration_ms"),
    )


def decode_line(raw: bytes) -> str:
    """Strip one trailing LF or CRLF and decode UTF-8, or raise MalformedLine."""
    if raw.endswith(b"\n"):
        raw = raw[:-1]
    if raw.endswith(b"\r"):
        raw = raw[:-1]
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise MalformedLine(f"not UTF-8: {error.reason}") from error
