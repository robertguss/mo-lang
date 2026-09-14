"""One log line: `<ISO-8601 timestamp> <method> <path> <status> <duration_ms>`."""

import re
from datetime import datetime

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, ValidationError

from logstat.contract import ensure, require
from logstat.mask import find_card_number, mask_card_numbers

UINT32_MAX = 4_294_967_295

_METHOD = re.compile(r"[A-Z]+")
_STATUS = re.compile(r"[0-9]{3}")
_DURATION = re.compile(r"[0-9]{1,10}")


class Record(BaseModel):
    """A well-formed line. `path` and `at_text` are already masked."""

    model_config = ConfigDict(frozen=True, strict=True, extra="forbid")

    at: AwareDatetime
    at_text: str = Field(min_length=1)
    method: str = Field(pattern=r"^[A-Z]+$")
    path: str = Field(pattern=r"^/")
    status: int = Field(ge=100, le=599)
    duration_ms: int = Field(ge=0, le=UINT32_MAX)

    @property
    def is_error(self) -> bool:
        return 500 <= self.status <= 599


class Malformed(BaseModel):
    """A line that does not fit the format, and why."""

    model_config = ConfigDict(frozen=True, strict=True, extra="forbid")

    reason: str


def parse_line(line: str) -> Record | Malformed:
    """Parse one line with its line ending already removed."""
    require("\n" not in line, "the line holds no newline")
    fields = line.split(" ")
    if len(fields) != 5:
        return Malformed(reason=f"expected 5 space-separated fields, found {len(fields)}")
    stamp, method, path, status_text, duration_text = fields
    at = _parse_timestamp(stamp)
    if at is None:
        return Malformed(reason="timestamp is not ISO-8601 with a UTC offset")
    if _METHOD.fullmatch(method) is None:
        return Malformed(reason="method is not upper-case letters")
    if _STATUS.fullmatch(status_text) is None or _DURATION.fullmatch(duration_text) is None:
        return Malformed(reason="status or duration_ms is not digits")
    try:
        record = Record(
            at=at,
            at_text=mask_card_numbers(stamp),
            method=method,
            path=mask_card_numbers(path),
            status=int(status_text),
            duration_ms=int(duration_text),
        )
    except ValidationError as error:
        return Malformed(reason=f"out of range: {error.errors()[0]['msg']}")
    ensure(100 <= record.status <= 599, "status is 100 to 599")
    ensure(0 <= record.duration_ms <= UINT32_MAX, "duration_ms fits UInt32")
    ensure(find_card_number(record.path) is None, "the path holds no card number")
    return record


def parse_raw_line(raw: bytes) -> Record | Malformed | None:
    """Parse a line as read from a file. None for an empty line, which is not counted."""
    body = raw.removesuffix(b"\n").removesuffix(b"\r")
    if not body:
        return None
    try:
        text = body.decode("utf-8")
    except UnicodeDecodeError:
        return Malformed(reason="line is not UTF-8")
    if "\n" in text:
        return Malformed(reason="line holds a bare newline")
    return parse_line(text)


def _parse_timestamp(stamp: str) -> datetime | None:
    try:
        at = datetime.fromisoformat(stamp)
    except ValueError:
        return None
    return at if at.tzinfo is not None and at.utcoffset() is not None else None
