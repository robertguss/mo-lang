"""One log line: `<ISO-8601 timestamp> <method> <path> <status> <duration_ms>`."""

import re
from datetime import UTC, datetime
from typing import Annotated

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, ValidationError

UINT32_MAX = 4_294_967_295
CARD_NUMBER = re.compile(r"[0-9]{16,}")
_DIGITS = re.compile(r"[0-9]+")


class LogRecord(BaseModel):
    """A well-formed line. Its `path` has card numbers already masked."""

    model_config = ConfigDict(frozen=True, strict=True)

    at: AwareDatetime
    method: Annotated[str, Field(pattern=r"^[A-Z]+$")]
    path: Annotated[str, Field(pattern=r"^/\S*$")]
    status: Annotated[int, Field(ge=100, le=599)]
    duration_ms: Annotated[int, Field(ge=0, le=UINT32_MAX)]

    @property
    def is_error(self) -> bool:
        return 500 <= self.status <= 599


class Malformed(BaseModel):
    """A line that does not fit. The reason never quotes the line."""

    model_config = ConfigDict(frozen=True)

    reason: str


def parse_line(line: str) -> LogRecord | Malformed:
    fields = line.split(" ")
    if len(fields) != 5:
        return Malformed(reason=f"expected 5 space-separated fields, found {len(fields)}")
    stamp, method, path, status, duration = fields
    at = parse_timestamp(stamp)
    if at is None:
        return Malformed(reason="timestamp is not ISO-8601 with a zone")
    if not (_is_unsigned(status, 3) and _is_unsigned(duration, 10)):
        return Malformed(reason="status and duration must be unsigned decimal integers")
    try:
        return LogRecord(
            at=at,
            method=method,
            path=mask_cards(path),
            status=int(status),
            duration_ms=int(duration),
        )
    except ValidationError as err:
        return Malformed(reason="; ".join(f"{e['loc'][0]}: {e['msg']}" for e in err.errors()))


def parse_timestamp(text: str) -> datetime | None:
    """An ISO-8601 timestamp that names its zone, in UTC; None if `text` is not one."""
    try:
        at = datetime.fromisoformat(text)
        if at.utcoffset() is None:
            return None
        return at.astimezone(UTC)
    except ValueError, OverflowError:
        return None


def format_timestamp(at: datetime) -> str:
    """UTC as `YYYY-MM-DDTHH:MM:SS[.ffffff]Z`, never the text the line carried."""
    utc = at.astimezone(UTC)
    fraction = f".{utc.microsecond:06d}" if utc.microsecond else ""
    return (
        f"{utc.year:04d}-{utc.month:02d}-{utc.day:02d}"
        f"T{utc.hour:02d}:{utc.minute:02d}:{utc.second:02d}{fraction}Z"
    )


def mask_cards(path: str) -> str:
    """Every run of 16 or more digits becomes as many `*`."""
    return CARD_NUMBER.sub(lambda match: "*" * len(match.group()), path)


def _is_unsigned(text: str, max_digits: int) -> bool:
    return len(text) <= max_digits and _DIGITS.fullmatch(text) is not None
