"""Fold records into a Summary without holding more than the top N of them."""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from fractions import Fraction

from logstat.contracts import require
from logstat.record import Record

MIN_TOP = 1
MAX_TOP = 100
DEFAULT_TOP = 5


@dataclass(frozen=True, slots=True)
class PathCount:
    count: int
    method: str
    path: str


@dataclass(frozen=True, slots=True)
class Summary:
    requests: int
    errors: int
    successes: int
    malformed: int
    first_epoch: int | None
    last_epoch: int | None
    slowest: tuple[Record, ...]
    busiest: tuple[PathCount, ...]

    def __post_init__(self) -> None:
        require(self.requests == self.errors + self.successes, "requests must be errors + successes")
        require(0 <= self.errors <= self.requests, "errors must be 0 to requests")
        require(self.successes >= 0 and self.malformed >= 0, "counts must not be negative")
        require((self.first_epoch is None) == (self.requests == 0), "a span exactly when requests")
        require(_span(self) >= 0, "first_epoch must not be after last_epoch")
        require(len(self.slowest) <= self.requests, "slowest must not outnumber requests")
        require(_ordered([slow_key(r) for r in self.slowest]), "slowest must be sorted")
        require(_ordered([busy_key(p) for p in self.busiest]), "busiest must be sorted")


def is_error(status: int) -> bool:
    return 500 <= status <= 599


def slow_key(record: Record) -> tuple[int, str]:
    return (-record.duration_ms, record.at)


def busy_key(entry: PathCount) -> tuple[int, str, str]:
    return (-entry.count, entry.path, entry.method)


def _ordered(keys: Sequence[tuple[int, str] | tuple[int, str, str]]) -> bool:
    return all(earlier <= later for earlier, later in zip(keys, keys[1:]))


def _span(summary: Summary) -> int:
    if summary.first_epoch is None or summary.last_epoch is None:
        return 0
    return summary.last_epoch - summary.first_epoch


def per_minute(summary: Summary) -> Fraction:
    """Requests per minute over the first-to-last span; 0 when the span is 0."""
    span = _span(summary)
    return Fraction(summary.requests * 60, span) if span > 0 else Fraction(0)


def error_rate(summary: Summary) -> Fraction:
    return Fraction(summary.errors, summary.requests) if summary.requests > 0 else Fraction(0)


class Tally:
    """Running counts; `slowest` keeps at most 2 * top candidates between trims."""

    def __init__(self, top: int) -> None:
        require(MIN_TOP <= top <= MAX_TOP, "top must be 1 to 100")
        self._top = top
        self._requests = 0
        self._errors = 0
        self._malformed = 0
        self._first: int | None = None
        self._last: int | None = None
        self._slowest: list[tuple[tuple[int, str, int], Record]] = []
        self._counts: dict[tuple[str, str], int] = {}

    def add_malformed(self) -> None:
        self._malformed += 1

    def add(self, record: Record) -> None:
        self._requests += 1
        self._errors += is_error(record.status)
        self._first = record.epoch if self._first is None else min(self._first, record.epoch)
        self._last = record.epoch if self._last is None else max(self._last, record.epoch)
        self._slowest.append(((*slow_key(record), self._requests), record))
        if len(self._slowest) > 2 * self._top:
            self._trim_slowest()
        key = (record.method, record.path)
        self._counts[key] = self._counts.get(key, 0) + 1

    def _trim_slowest(self) -> None:
        self._slowest.sort(key=lambda candidate: candidate[0])
        del self._slowest[self._top :]

    def summary(self) -> Summary:
        self._trim_slowest()
        counts = (PathCount(n, method, path) for (method, path), n in self._counts.items())
        busiest = sorted(counts, key=busy_key)[: self._top]
        return Summary(
            requests=self._requests,
            errors=self._errors,
            successes=self._requests - self._errors,
            malformed=self._malformed,
            first_epoch=self._first,
            last_epoch=self._last,
            slowest=tuple(record for _, record in self._slowest),
            busiest=tuple(busiest),
        )


def summarize(records: Iterable[Record], top: int = DEFAULT_TOP, malformed: int = 0) -> Summary:
    tally = Tally(top)
    for record in records:
        tally.add(record)
    for _ in range(malformed):
        tally.add_malformed()
    return tally.summary()
