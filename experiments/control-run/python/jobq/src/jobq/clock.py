"""The clock the queue reads: whole milliseconds since the Unix epoch, UTC."""

import time
from datetime import UTC, datetime
from typing import Protocol

from jobq.contract import require


class Clock(Protocol):
    def now_ms(self) -> int: ...


class SystemClock:
    def now_ms(self) -> int:
        return time.time_ns() // 1_000_000


class FakeClock:
    """A clock that moves only when told to, for tests and the simulation."""

    def __init__(self, start_ms: int = 1_789_000_000_000) -> None:
        self.ms = start_ms

    def now_ms(self) -> int:
        return self.ms

    def advance(self, ms: int) -> None:
        require(ms >= 0, "the clock never goes back")
        self.ms += ms


def iso_utc(ms: int) -> str:
    """ISO-8601 UTC with milliseconds, such as 2026-09-14T16:40:46.123Z."""
    seconds, millis = divmod(ms, 1000)
    return f"{datetime.fromtimestamp(seconds, UTC):%Y-%m-%dT%H:%M:%S}.{millis:03d}Z"
