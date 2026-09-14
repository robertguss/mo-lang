"""The summary, built one record at a time so only one file is ever in memory."""

import heapq
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field

from logstat.contract import ensure, require
from logstat.record import LogRecord, format_timestamp

MIN_TOP = 1
MAX_TOP = 100
_EPOCH = datetime(1970, 1, 1, tzinfo=UTC)
_MICROSECOND = timedelta(microseconds=1)


class SlowEntry(BaseModel):
    model_config = ConfigDict(frozen=True)

    ms: Annotated[int, Field(ge=0)]
    method: str
    path: str
    at: str


class BusyEntry(BaseModel):
    model_config = ConfigDict(frozen=True)

    count: Annotated[int, Field(ge=1)]
    method: str
    path: str


class Summary(BaseModel):
    """Field order is the JSON key order."""

    model_config = ConfigDict(frozen=True)

    requests: Annotated[int, Field(ge=0)]
    errors: Annotated[int, Field(ge=0)]
    error_rate: Annotated[float, Field(ge=0.0, le=1.0)]
    malformed: Annotated[int, Field(ge=0)]
    per_minute: Annotated[float, Field(ge=0.0)]
    slowest: list[SlowEntry]
    busiest: list[BusyEntry]


@dataclass(frozen=True, order=True)
class _Slow:
    """Ordered worst first, so the heap's root is the one to drop."""

    ms: int
    minus_micros: int
    minus_seq: int
    record: LogRecord = field(compare=False)


class Tally:
    def __init__(self, top: int, since: datetime | None = None) -> None:
        require(MIN_TOP <= top <= MAX_TOP, f"{MIN_TOP} <= top <= {MAX_TOP}")
        require(since is None or since.utcoffset() is not None, "since names its zone")
        self._top = top
        self._since = since
        self.requests = 0
        self.errors = 0
        self.successes = 0
        self.malformed = 0
        self._first: datetime | None = None
        self._last: datetime | None = None
        self._counts: dict[tuple[str, str], int] = {}
        self._slow: list[_Slow] = []
        self._seq = 0

    def add_malformed(self) -> None:
        self.malformed += 1

    def add(self, record: LogRecord) -> None:
        if self._since is not None and record.at < self._since:
            return
        self.requests += 1
        if record.is_error:
            self.errors += 1
        else:
            self.successes += 1
        self._first = record.at if self._first is None else min(self._first, record.at)
        self._last = record.at if self._last is None else max(self._last, record.at)
        key = (record.method, record.path)
        self._counts[key] = self._counts.get(key, 0) + 1
        self._keep_if_slow(record)

    def summary(self) -> Summary:
        ensure(self.requests == self.errors + self.successes, "requests == errors + successes")
        ensure(self.errors <= self.requests, "errors <= requests")
        slowest = [
            SlowEntry(
                ms=slow.record.duration_ms,
                method=slow.record.method,
                path=slow.record.path,
                at=format_timestamp(slow.record.at),
            )
            for slow in sorted(self._slow, reverse=True)
        ]
        ranked = sorted(self._counts.items(), key=lambda item: (-item[1], item[0][1], item[0][0]))
        busiest = [
            BusyEntry(count=count, method=method, path=path)
            for (method, path), count in ranked[: self._top]
        ]
        ensure(len(slowest) <= self._top and len(busiest) <= self._top, "lists hold at most top")
        return Summary(
            requests=self.requests,
            errors=self.errors,
            error_rate=round(self.errors / self.requests, 3) if self.requests else 0.0,
            malformed=self.malformed,
            per_minute=per_minute(self.requests, self._first, self._last),
            slowest=slowest,
            busiest=busiest,
        )

    def _keep_if_slow(self, record: LogRecord) -> None:
        self._seq += 1
        micros = (record.at - _EPOCH) // _MICROSECOND
        candidate = _Slow(record.duration_ms, -micros, -self._seq, record)
        if len(self._slow) < self._top:
            heapq.heappush(self._slow, candidate)
        elif candidate > self._slow[0]:
            heapq.heapreplace(self._slow, candidate)


def per_minute(requests: int, first: datetime | None, last: datetime | None) -> float:
    """Requests over the span from first to last timestamp; 0.0 when that span is empty."""
    if requests < 2 or first is None or last is None:
        return 0.0
    minutes = (last - first) / timedelta(minutes=1)
    return round(requests / minutes, 1) if minutes > 0 else 0.0
