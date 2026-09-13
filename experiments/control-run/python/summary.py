"""Folding records into a Summary, one record at a time."""

from dataclasses import dataclass, field
from datetime import datetime

from parse import Record

TOP_MIN = 1
TOP_MAX = 100


def check_top(top: int) -> None:
    if not TOP_MIN <= top <= TOP_MAX:
        raise ValueError(f"top {top} is outside {TOP_MIN} to {TOP_MAX}")


@dataclass(frozen=True)
class PathCount:
    count: int
    method: str
    path: str

    def __post_init__(self) -> None:
        if self.count < 1:
            raise ValueError(f"count {self.count} must be at least 1")


def slowest_key(record: Record) -> tuple[int, datetime, str, str]:
    return (-record.duration_ms, record.at, record.method, record.path)


def busiest_key(entry: PathCount) -> tuple[int, str, str]:
    return (-entry.count, entry.path, entry.method)


@dataclass(frozen=True)
class Summary:
    top: int
    requests: int
    errors: int
    successes: int
    malformed: int
    first_at: datetime | None
    last_at: datetime | None
    slowest: tuple[Record, ...]
    busiest: tuple[PathCount, ...]

    def __post_init__(self) -> None:
        check_top(self.top)
        if min(self.requests, self.errors, self.successes, self.malformed) < 0:
            raise ValueError("counts must not be negative")
        if self.requests != self.errors + self.successes:
            raise ValueError("requests must equal errors + successes")
        if self.errors > self.requests:
            raise ValueError("errors must not exceed requests")
        self.check_span()
        self.check_lists()

    def check_span(self) -> None:
        if (self.first_at is None) != (self.requests == 0) or (self.last_at is None) != (self.requests == 0):
            raise ValueError("first and last timestamps are set exactly when there are requests")
        if self.first_at is not None and self.last_at is not None and self.first_at > self.last_at:
            raise ValueError("first timestamp must not be after the last")

    def check_lists(self) -> None:
        if len(self.slowest) > min(self.top, self.requests) or len(self.busiest) > min(self.top, self.requests):
            raise ValueError("lists must hold at most top entries and at most one per request")
        if list(self.slowest) != sorted(self.slowest, key=slowest_key):
            raise ValueError("slowest must be sorted by duration descending, then timestamp ascending")
        if list(self.busiest) != sorted(self.busiest, key=busiest_key):
            raise ValueError("busiest must be sorted by count descending, then path ascending")

    @property
    def error_rate(self) -> float:
        return self.errors / self.requests if self.requests else 0.0

    @property
    def per_minute(self) -> float:
        if self.first_at is None or self.last_at is None or self.first_at == self.last_at:
            return 0.0
        minutes = (self.last_at - self.first_at).total_seconds() / 60
        return self.requests / minutes


@dataclass
class Accumulator:
    """Streams records in; keeps counts, the time span, a bounded slowest pool, and per-path counts."""

    top: int
    requests: int = 0
    errors: int = 0
    successes: int = 0
    malformed: int = 0
    first_at: datetime | None = None
    last_at: datetime | None = None
    slowest_pool: list[Record] = field(default_factory=list)
    path_counts: dict[tuple[str, str], int] = field(default_factory=dict)

    def __post_init__(self) -> None:
        check_top(self.top)

    def add_malformed(self) -> None:
        self.malformed += 1

    def add(self, record: Record) -> None:
        self.requests += 1
        if record.is_error:
            self.errors += 1
        else:
            self.successes += 1
        if self.first_at is None or record.at < self.first_at:
            self.first_at = record.at
        if self.last_at is None or record.at > self.last_at:
            self.last_at = record.at
        key = (record.method, record.path)
        self.path_counts[key] = self.path_counts.get(key, 0) + 1
        self.slowest_pool.append(record)
        if len(self.slowest_pool) >= 2 * self.top + 64:
            self.slowest_pool = sorted(self.slowest_pool, key=slowest_key)[: self.top]

    def finish(self) -> Summary:
        busiest = (PathCount(count, method, path) for (method, path), count in self.path_counts.items())
        return Summary(
            top=self.top,
            requests=self.requests,
            errors=self.errors,
            successes=self.successes,
            malformed=self.malformed,
            first_at=self.first_at,
            last_at=self.last_at,
            slowest=tuple(sorted(self.slowest_pool, key=slowest_key)[: self.top]),
            busiest=tuple(sorted(busiest, key=busiest_key)[: self.top]),
        )


def summarize(records: list[Record], top: int, malformed: int = 0) -> Summary:
    accumulator = Accumulator(top)
    for record in records:
        accumulator.add(record)
    for _ in range(malformed):
        accumulator.add_malformed()
    return accumulator.finish()
