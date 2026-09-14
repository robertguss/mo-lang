"""The clock `main` hands to the queue: wall time for timestamps, monotonic time for uptime."""

import threading
import time
from typing import Protocol


class Clock(Protocol):
    def now_ms(self) -> int: ...

    def uptime_ms(self) -> int: ...


class SystemClock:
    def __init__(self) -> None:
        self._started = time.monotonic_ns()

    def now_ms(self) -> int:
        return time.time_ns() // 1_000_000

    def uptime_ms(self) -> int:
        return (time.monotonic_ns() - self._started) // 1_000_000


class ManualClock:
    """A clock that moves only when told to: for `jobq check` and the tests."""

    def __init__(self, start_ms: int) -> None:
        self._lock = threading.Lock()
        self._start = start_ms
        self._now = start_ms

    def now_ms(self) -> int:
        with self._lock:
            return self._now

    def uptime_ms(self) -> int:
        with self._lock:
            return self._now - self._start

    def advance(self, ms: int) -> None:
        with self._lock:
            self._now += ms
