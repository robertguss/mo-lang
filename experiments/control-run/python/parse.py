"""One log line to one Record, or Malformed. Card numbers are masked here, before a path is stored."""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from contracts import require

FIELD_COUNT = 5
STATUS_DIGITS = 3
STATUS_MIN = 100
STATUS_MAX = 599
UINT32_MAX = 4_294_967_295
UINT32_DIGITS = len(str(UINT32_MAX))

_TIMESTAMP = re.compile(
    r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,6})?(?:Z|[+-][0-9]{2}:[0-9]{2})"
)
_METHOD = re.compile(r"[A-Z]+")
_CARD = re.compile(r"[0-9]{16,}")
_EPOCH = datetime(1970, 1, 1, tzinfo=UTC)
_MICROSECOND = timedelta(microseconds=1)


class Malformed(ValueError):
    """A line that does not fit `<timestamp> <method> <path> <status> <duration_ms>`."""


@dataclass(frozen=True, slots=True)
class Record:
    """A well-formed request line."""

    at: str  # the timestamp as written in the log
    instant: int  # microseconds since 1970-01-01T00:00:00Z
    method: str
    path: str  # card numbers already replaced by `*`
    status: int
    duration_ms: int

    def __post_init__(self) -> None:
        require(STATUS_MIN <= self.status <= STATUS_MAX, "status is 100 to 599")
        require(0 <= self.duration_ms <= UINT32_MAX, "duration_ms fits UInt32")
        require(not contains_card(self.path), "path holds no card number")


def contains_card(text: str) -> bool:
    """True when the text holds a run of 16 or more ASCII digits."""
    return _CARD.search(text) is not None


def mask_cards(text: str) -> str:
    """Replace every digit of every run of 16 or more ASCII digits with `*`."""
    return _CARD.sub(lambda match: "*" * len(match.group()), text)


def decode_line(raw: bytes) -> str:
    """Strip one trailing LF, then one CR, and decode strict UTF-8."""
    line = raw.removesuffix(b"\n").removesuffix(b"\r")
    try:
        return line.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise Malformed("line is not UTF-8") from exc


def parse_line(line: str) -> Record:
    """Parse one line, already stripped of its line ending."""
    fields = line.split(" ")
    if len(fields) != FIELD_COUNT:
        raise Malformed(f"expected {FIELD_COUNT} space-separated fields, found {len(fields)}")
    at, method, path, status, duration = fields
    return Record(
        at=at,
        instant=parse_timestamp(at),
        method=parse_method(method),
        path=mask_cards(parse_path(path)),
        status=parse_status(status),
        duration_ms=parse_duration(duration),
    )


def parse_raw(raw: bytes) -> Record:
    """Parse one line as read from a file, line ending included."""
    return parse_line(decode_line(raw))


def parse_timestamp(text: str) -> int:
    """`YYYY-MM-DDTHH:MM:SS[.ffffff](Z|+HH:MM|-HH:MM)` to microseconds since the epoch."""
    if _TIMESTAMP.fullmatch(text) is None:
        raise Malformed("timestamp is not YYYY-MM-DDTHH:MM:SS with a zone")
    try:
        moment = datetime.fromisoformat(text)
    except ValueError as exc:
        raise Malformed("timestamp is not a real instant") from exc
    return (moment - _EPOCH) // _MICROSECOND


def parse_method(text: str) -> str:
    if _METHOD.fullmatch(text) is None:
        raise Malformed("method is not upper-case ASCII letters")
    return text


def parse_path(text: str) -> str:
    if not text.startswith("/") or not text.isprintable():
        raise Malformed("path does not start with / or holds a control character")
    return text


def parse_status(text: str) -> int:
    if len(text) != STATUS_DIGITS or not is_ascii_digits(text):
        raise Malformed("status is not three digits")
    status = int(text)
    if not STATUS_MIN <= status <= STATUS_MAX:
        raise Malformed("status is outside 100 to 599")
    return status


def parse_duration(text: str) -> int:
    if not is_ascii_digits(text) or len(text.lstrip("0")) > UINT32_DIGITS:
        raise Malformed("duration_ms is not a decimal of at most 10 digits")
    duration = int(text)
    if duration > UINT32_MAX:
        raise Malformed("duration_ms does not fit UInt32")
    return duration


def is_ascii_digits(text: str) -> bool:
    """`str.isdigit` alone accepts other scripts' digits, and `int` accepts `_` and spaces."""
    return text.isascii() and text.isdigit()
