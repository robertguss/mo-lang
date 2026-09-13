"""Streaming summary of records: counts, span, slowest and busiest."""

from __future__ import annotations

import heapq
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from records import ContractError, Malformed, Record, require

TOP_MIN = 1
TOP_MAX = 100
_EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)
_MICROSECOND = timedelta(microseconds=1)


@dataclass(frozen=True)
class PathCount:
    count: int
    method: str
    path: str


@dataclass(frozen=True)
class Summary:
    requests: int
    errors: int
    successes: int
    malformed: int
    per_minute: float
    slowest: tuple[Record, ...]
    busiest: tuple[PathCount, ...]

    def __post_init__(self) -> None:
        require(min(self.errors, self.successes, self.malformed) >= 0, "counts are not negative")
        require(self.requests == self.errors + self.successes, "requests == errors + successes")
        require(self.errors <= self.requests, "errors <= requests")
        require(self.per_minute >= 0.0, "per_minute is not negative")
        require(len(self.slowest) <= self.requests, "slowest holds only counted requests")
        require(sum(p.count for p in self.busiest) <= self.requests, "busiest counts only requests")
        require(list(self.slowest) == sorted(self.slowest, key=slowest_order), "slowest is sorted")
        require(list(self.busiest) == sorted(self.busiest, key=busiest_order), "busiest is sorted")

    @property
    def error_rate(self) -> float:
        return self.errors / self.requests if self.requests else 0.0


def slowest_order(record: Record) -> tuple[int, datetime]:
    return (-record.duration_ms, record.at)


def busiest_order(entry: PathCount) -> tuple[int, str, str]:
    return (-entry.count, entry.path, entry.method)


def require_top(top: int) -> None:
    if not TOP_MIN <= top <= TOP_MAX:
        raise ContractError(f"top {top} is outside {TOP_MIN} to {TOP_MAX}")


class Tally:
    def __init__(self, top: int) -> None:
        require_top(top)
        self._top = top
        self._requests = 0
        self._errors = 0
        self._malformed = 0
        self._first: datetime | None = None
        self._last: datetime | None = None
        # Min-heap whose smallest entry is the least slow kept record.
        self._slowest: list[tuple[int, int, int, Record]] = []
        self._counts: dict[tuple[str, str], int] = {}

    def add(self, record: Record) -> None:
        self._requests += 1
        self._errors += record.is_error
        self._widen_span(record.at)
        self._keep_if_slow(record)
        key = (record.method, record.path)
        self._counts[key] = self._counts.get(key, 0) + 1

    def add_malformed(self) -> None:
        self._malformed += 1

    def _widen_span(self, at: datetime) -> None:
        if self._first is None or at < self._first:
            self._first = at
        if self._last is None or at > self._last:
            self._last = at

    def _keep_if_slow(self, record: Record) -> None:
        # The arrival number is unique, so the Record itself is never compared.
        micros = (record.at - _EPOCH) // _MICROSECOND
        entry = (record.duration_ms, -micros, -self._requests, record)
        if len(self._slowest) < self._top:
            heapq.heappush(self._slowest, entry)
        else:
            heapq.heappushpop(self._slowest, entry)

    def finish(self) -> Summary:
        slowest = tuple(entry[3] for entry in sorted(self._slowest, reverse=True))
        counts = (PathCount(n, method, path) for (method, path), n in self._counts.items())
        busiest = tuple(heapq.nsmallest(self._top, counts, key=busiest_order))
        return Summary(
            requests=self._requests,
            errors=self._errors,
            successes=self._requests - self._errors,
            malformed=self._malformed,
            per_minute=per_minute(self._requests, self._first, self._last),
            slowest=slowest,
            busiest=busiest,
        )


def per_minute(requests: int, first: datetime | None, last: datetime | None) -> float:
    if first is None or last is None:
        return 0.0
    minutes = (last - first).total_seconds() / 60
    return requests / minutes if minutes > 0 else 0.0


def summarize(parsed: Iterable[Record | Malformed], top: int) -> Summary:
    tally = Tally(top)
    for item in parsed:
        if isinstance(item, Malformed):
            tally.add_malformed()
        else:
            tally.add(item)
    return tally.finish()
