"""Record builders shared by the tests."""

import calendar
import random
import time

from logstat.record import Record

BASE = calendar.timegm((2026, 9, 12, 10, 0, 0))
METHODS = ["GET", "POST", "PUT", "DELETE"]
PATHS = ["/api/users", "/api/orders", "/health", "/a", "/b"]


def stamp(offset: int) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(BASE + offset))


def rec(offset: int = 0, method: str = "GET", path: str = "/a", status: int = 200, ms: int = 1) -> Record:
    return Record(stamp(offset), BASE + offset, method, path, status, ms)


def random_record(rng: random.Random) -> Record:
    return rec(
        offset=rng.randrange(0, 600),
        method=rng.choice(METHODS),
        path=rng.choice(PATHS),
        status=rng.randrange(100, 600),
        ms=rng.choice([0, 1, 5, 340, rng.randrange(0, 4_294_967_296)]),
    )
