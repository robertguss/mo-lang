"""Tallying records into a Summary: counts, rate, the slowest requests and the busiest paths."""

from __future__ import annotations

import heapq
from dataclasses import dataclass, field

from contracts import require
from parse import Record, contains_card

TOP_MIN = 1
TOP_MAX = 100
ERROR_MIN = 500
ERROR_MAX = 599
_MICROSECONDS_PER_MINUTE = 60_000_000


@dataclass(frozen=True, slots=True)
class Busy:
    """How many requests one method and path received."""

    count: int
    method: str
    path: str

    def __post_init__(self) -> None:
        require(self.count >= 1, "count is at least 1")
        require(not contains_card(self.path), "path holds no card number")


@dataclass(frozen=True, slots=True)
class Summary:
    requests: int
    errors: int
    successes: int
    malformed: int
    per_minute: float
    slowest: tuple[Record, ...]
    busiest: tuple[Busy, ...]

    def __post_init__(self) -> None:
        require(self.requests == self.errors + self.successes, "requests equals errors + successes")
        require(0 <= self.errors <= self.requests, "errors <= requests")
        require(self.malformed >= 0 and self.per_minute >= 0.0, "malformed and per_minute are not negative")
        require(_ascending([slow_key(r) for r in self.slowest]), "slowest by duration descending, then timestamp ascending")
        require(_ascending([busy_key(b) for b in self.busiest]), "busiest by count descending, then path ascending")

    @property
    def error_rate(self) -> float:
        """Errors over requests; 0.0 when there are no requests."""
        return self.errors / self.requests if self.requests else 0.0


def is_error(status: int) -> bool:
    return ERROR_MIN <= status <= ERROR_MAX


def slow_key(record: Record) -> tuple[int, int]:
    return (-record.duration_ms, record.instant)


def busy_key(busy: Busy) -> tuple[int, str, str]:
    return (-busy.count, busy.path, busy.method)


def _ascending(keys: list[tuple[int, int]] | list[tuple[int, str, str]]) -> bool:
    return all(earlier <= later for earlier, later in zip(keys, keys[1:], strict=False))


@dataclass(slots=True)
class Tally:
    """Accumulates records one at a time; memory is bounded by `top` plus the distinct method-path pairs."""

    top: int
    requests: int = 0
    errors: int = 0
    successes: int = 0
    malformed: int = 0
    first: int | None = None
    last: int | None = None
    # min-heap whose root is the least slow of the kept records: (ms, -instant, -arrival, record)
    _slowest: list[tuple[int, int, int, Record]] = field(default_factory=list)
    _counts: dict[tuple[str, str], int] = field(default_factory=dict)

    def __post_init__(self) -> None:
        require(TOP_MIN <= self.top <= TOP_MAX, "top is 1 to 100")

    def add(self, record: Record) -> None:
        self.requests += 1
        if is_error(record.status):
            self.errors += 1
        else:
            self.successes += 1
        self.first = record.instant if self.first is None else min(self.first, record.instant)
        self.last = record.instant if self.last is None else max(self.last, record.instant)
        self._offer_slow(record)
        key = (record.method, record.path)
        self._counts[key] = self._counts.get(key, 0) + 1

    def add_malformed(self) -> None:
        self.malformed += 1

    def summary(self) -> Summary:
        return Summary(
            requests=self.requests,
            errors=self.errors,
            successes=self.successes,
            malformed=self.malformed,
            per_minute=self._per_minute(),
            slowest=self._ranked_slowest(),
            busiest=self._ranked_busiest(),
        )

    def _offer_slow(self, record: Record) -> None:
        """Keep the `top` slowest; ties go to the earlier timestamp, then to the earlier arrival."""
        entry = (record.duration_ms, -record.instant, -self.requests, record)
        if len(self._slowest) < self.top:
            heapq.heappush(self._slowest, entry)
        elif entry[:3] > self._slowest[0][:3]:
            heapq.heapreplace(self._slowest, entry)

    def _per_minute(self) -> float:
        if self.first is None or self.last is None or self.first == self.last:
            return 0.0
        return self.requests * _MICROSECONDS_PER_MINUTE / (self.last - self.first)

    def _ranked_slowest(self) -> tuple[Record, ...]:
        ranked = sorted(self._slowest, key=lambda entry: entry[:3], reverse=True)
        return tuple(entry[3] for entry in ranked)

    def _ranked_busiest(self) -> tuple[Busy, ...]:
        ranked = heapq.nsmallest(
            self.top, self._counts.items(), key=lambda item: (-item[1], item[0][1], item[0][0])
        )
        return tuple(Busy(count=count, method=method, path=path) for (method, path), count in ranked)
