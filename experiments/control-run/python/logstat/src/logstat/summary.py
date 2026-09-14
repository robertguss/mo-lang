"""The summary: counts, error rate, per minute, slowest requests, busiest paths."""

import heapq
from itertools import pairwise
from collections import Counter
from collections.abc import Iterable
from datetime import UTC, datetime, timedelta

from pydantic import BaseModel, ConfigDict, Field

from logstat.contract import ensure, invariant, require
from logstat.records import Malformed, Record, parse_raw_line

_EPOCH = datetime(1970, 1, 1, tzinfo=UTC)
_MICROSECOND = timedelta(microseconds=1)
_MICROSECONDS_PER_MINUTE = 60_000_000


class SlowRequest(BaseModel):
    model_config = ConfigDict(frozen=True, strict=True, extra="forbid")

    ms: int = Field(ge=0)
    method: str
    path: str
    at: str


class BusyPath(BaseModel):
    model_config = ConfigDict(frozen=True, strict=True, extra="forbid")

    count: int = Field(ge=1)
    method: str
    path: str


class Summary(BaseModel):
    """The JSON shape, field for field and in order."""

    model_config = ConfigDict(frozen=True, strict=True, extra="forbid")

    requests: int = Field(ge=0)
    errors: int = Field(ge=0)
    error_rate: float = Field(ge=0.0, le=1.0)
    malformed: int = Field(ge=0)
    per_minute: float = Field(ge=0.0)
    slowest: list[SlowRequest]
    busiest: list[BusyPath]


class Accumulator:
    """Folds records into a summary, keeping only the top N slowest in memory."""

    def __init__(self, top: int) -> None:
        require(1 <= top <= 100, "top is 1 to 100")
        self.top = top
        self.requests = 0
        self.errors = 0
        self.successes = 0
        self.malformed = 0
        self.first_us: int | None = None
        self.last_us: int | None = None
        # A min-heap whose root is the least slow of the kept: (ms, -at_us, -seq, record).
        self._slowest: list[tuple[int, int, int, Record]] = []
        self._paths: Counter[tuple[str, str]] = Counter()

    def add_malformed(self) -> None:
        self.malformed += 1

    def add(self, record: Record) -> None:
        at_us = (record.at - _EPOCH) // _MICROSECOND
        self.requests += 1
        if record.is_error:
            self.errors += 1
        else:
            self.successes += 1
        self.first_us = at_us if self.first_us is None else min(self.first_us, at_us)
        self.last_us = at_us if self.last_us is None else max(self.last_us, at_us)
        entry = (record.duration_ms, -at_us, -self.requests, record)
        if len(self._slowest) < self.top:
            heapq.heappush(self._slowest, entry)
        else:
            heapq.heappushpop(self._slowest, entry)
        self._paths[(record.method, record.path)] += 1
        invariant(self.requests == self.errors + self.successes, "requests = errors + successes")
        invariant(self.errors <= self.requests, "errors <= requests")

    def finish(self) -> Summary:
        slowest = sorted(self._slowest, reverse=True)
        busiest = sorted(self._paths.items(), key=lambda item: (-item[1], item[0][1], item[0][0]))
        summary = Summary(
            requests=self.requests,
            errors=self.errors,
            error_rate=round(self.errors / self.requests, 3) if self.requests else 0.0,
            malformed=self.malformed,
            per_minute=round(self._per_minute(), 1),
            slowest=[
                SlowRequest(ms=r.duration_ms, method=r.method, path=r.path, at=r.at_text)
                for _, _, _, r in slowest
            ],
            busiest=[
                BusyPath(count=count, method=method, path=path)
                for (method, path), count in busiest[: self.top]
            ],
        )
        ensure(summary.requests == self.errors + self.successes, "requests = errors + successes")
        ensure(summary.errors <= summary.requests, "errors <= requests")
        ensure(is_slowest_order([key[:3] for key in slowest]), "slowest is ms desc, at asc")
        ensure(is_busiest_order(summary.busiest), "busiest is count desc, path asc")
        ensure(max(len(summary.slowest), len(summary.busiest)) <= self.top, "lists hold <= top")
        return summary

    def _per_minute(self) -> float:
        if self.first_us is None or self.last_us is None or self.last_us == self.first_us:
            return 0.0
        return self.requests / ((self.last_us - self.first_us) / _MICROSECONDS_PER_MINUTE)


def is_slowest_order(keys: list[tuple[int, int, int]]) -> bool:
    """Keys (ms, -at_us, -seq) in order: ms desc, then at asc, then input order."""
    return all(a > b for a, b in pairwise(keys))


def is_busiest_order(busiest: list[BusyPath]) -> bool:
    keys = [(-b.count, b.path, b.method) for b in busiest]
    return all(a < b for a, b in pairwise(keys))


def analyze(lines: Iterable[bytes], top: int, since: datetime | None) -> Summary:
    """Summarize raw lines. Malformed lines are counted; lines before `since` are ignored."""
    require(since is None or since.tzinfo is not None, "since carries a UTC offset")
    accumulator = Accumulator(top)
    for raw in lines:
        parsed = parse_raw_line(raw)
        if isinstance(parsed, Malformed):
            accumulator.add_malformed()
        elif isinstance(parsed, Record) and (since is None or parsed.at >= since):
            accumulator.add(parsed)
    return accumulator.finish()
