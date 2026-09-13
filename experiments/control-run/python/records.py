"""One log line becomes a Record or a Malformed marker, never an exception."""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime

UINT32_MAX = 4_294_967_295
STATUS_MIN = 100
STATUS_MAX = 599

_TIMESTAMP = re.compile(
    r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}"
    r"(\.[0-9]{1,6})?(Z|[+-][0-9]{2}:[0-9]{2})"
)
_METHOD = re.compile(r"[A-Z]+")
_UINT = re.compile(r"[0-9]{1,10}")
# Any Unicode decimal digit counts, so a card written in other scripts is masked too.
_CARD = re.compile(r"\d{16,}")


class ContractError(ValueError):
    """A requires or ensures check failed: a bug in the caller, not bad input."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


@dataclass(frozen=True)
class Malformed:
    reason: str


@dataclass(frozen=True)
class Record:
    at: datetime
    at_text: str
    method: str
    path: str
    status: int
    duration_ms: int

    def __post_init__(self) -> None:
        require(STATUS_MIN <= self.status <= STATUS_MAX, "status is 100 to 599")
        require(0 <= self.duration_ms <= UINT32_MAX, "duration_ms fits UInt32")
        require(self.at.tzinfo is not None, "timestamp has a time zone")
        require(not has_card(self.path), "path holds no card number")

    @property
    def is_error(self) -> bool:
        return 500 <= self.status <= 599


def has_card(text: str) -> bool:
    return _CARD.search(text) is not None


def mask_cards(text: str) -> str:
    return _CARD.sub(lambda match: "*" * len(match.group()), text)


def parse_timestamp(text: str) -> datetime | None:
    if _TIMESTAMP.fullmatch(text) is None:
        return None
    try:
        return datetime.fromisoformat(text)
    except ValueError:
        return None


def parse_uint(text: str) -> int | None:
    # int() alone would accept "+5", " 5", "5_0" and non-ASCII digits.
    return int(text) if _UINT.fullmatch(text) else None


def parse_raw_line(raw: bytes) -> Record | Malformed:
    line = raw.removesuffix(b"\n").removesuffix(b"\r")
    try:
        return parse_line(line.decode("utf-8"))
    except UnicodeDecodeError:
        return Malformed("not UTF-8")


def parse_line(line: str) -> Record | Malformed:
    fields = line.split(" ")
    if len(fields) != 5:
        return Malformed("expected 5 space-separated fields")
    at_text, method, path, status_text, duration_text = fields
    at = parse_timestamp(at_text)
    if at is None:
        return Malformed("bad timestamp")
    if _METHOD.fullmatch(method) is None:
        return Malformed("bad method")
    if not path.startswith("/") or not path.isprintable():
        return Malformed("bad path")
    status = parse_uint(status_text)
    if status is None or not STATUS_MIN <= status <= STATUS_MAX:
        return Malformed("status outside 100 to 599")
    duration = parse_uint(duration_text)
    if duration is None or duration > UINT32_MAX:
        return Malformed("duration_ms does not fit UInt32")
    return Record(at, at_text, method, mask_cards(path), status, duration)
