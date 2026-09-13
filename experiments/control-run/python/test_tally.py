from __future__ import annotations

import random
import unittest
from datetime import datetime, timedelta, timezone

from records import UINT32_MAX, ContractError, Malformed, Record
from tally import PathCount, Summary, Tally, per_minute, summarize

START = datetime(2026, 9, 12, 10, 0, 0, tzinfo=timezone.utc)


def rec(second: int, ms: int, status: int = 200, path: str = "/a", method: str = "GET") -> Record:
    at = START + timedelta(seconds=second)
    return Record(at, at.strftime("%Y-%m-%dT%H:%M:%SZ"), method, path, status, ms)


class CountsTest(unittest.TestCase):
    def test_requests_errors_and_malformed(self) -> None:
        parsed: list[Record | Malformed] = [rec(0, 1, 200), rec(1, 1, 500), rec(2, 1, 599), rec(3, 1, 404), Malformed("x")]
        summary = summarize(parsed, 5)
        self.assertEqual((summary.requests, summary.errors, summary.malformed), (4, 2, 1))
        self.assertEqual(summary.successes, 2)
        self.assertEqual(summary.error_rate, 0.5)

    def test_empty_input(self) -> None:
        summary = summarize([], 5)
        self.assertEqual((summary.requests, summary.error_rate, summary.per_minute), (0, 0.0, 0.0))
        self.assertEqual((summary.slowest, summary.busiest), ((), ()))


class PerMinuteTest(unittest.TestCase):
    def test_divides_by_span_in_minutes(self) -> None:
        summary = summarize([rec(0, 1), rec(90, 1), rec(30, 1)], 5)
        self.assertEqual(summary.per_minute, 2.0)

    def test_single_request_and_zero_span_are_zero(self) -> None:
        self.assertEqual(summarize([rec(0, 1)], 5).per_minute, 0.0)
        self.assertEqual(per_minute(3, START, START), 0.0)
        self.assertEqual(per_minute(0, None, None), 0.0)


class SlowestTest(unittest.TestCase):
    def test_duration_descending_then_timestamp_ascending(self) -> None:
        parsed = [rec(5, 340), rec(1, 12), rec(2, 340), rec(3, 1204), rec(4, 340)]
        slowest = summarize(parsed, 4).slowest
        self.assertEqual([(r.duration_ms, r.at.second) for r in slowest], [(1204, 3), (340, 2), (340, 4), (340, 5)])

    def test_equal_duration_and_time_keeps_arrival_order(self) -> None:
        parsed = [rec(1, 9, path="/first"), rec(1, 9, path="/second"), rec(1, 9, path="/third")]
        self.assertEqual([r.path for r in summarize(parsed, 2).slowest], ["/first", "/second"])


class BusiestTest(unittest.TestCase):
    def test_count_descending_then_path_ascending(self) -> None:
        paths = ["/b", "/a", "/c", "/b", "/c", "/d", "/c"]
        busiest = summarize([rec(i, 1, path=p) for i, p in enumerate(paths)], 3).busiest
        self.assertEqual(busiest, (PathCount(3, "GET", "/c"), PathCount(2, "GET", "/b"), PathCount(1, "GET", "/a")))

    def test_method_is_part_of_the_key(self) -> None:
        parsed = [rec(0, 1, method="POST"), rec(1, 1, method="GET"), rec(2, 1, method="POST")]
        self.assertEqual(summarize(parsed, 5).busiest, (PathCount(2, "POST", "/a"), PathCount(1, "GET", "/a")))


class ContractTest(unittest.TestCase):
    def test_rejects_top_outside_1_to_100(self) -> None:
        for top in (0, 101, -1):
            with self.assertRaises(ContractError):
                Tally(top)

    def test_rejects_requests_not_errors_plus_successes(self) -> None:
        with self.assertRaises(ContractError):
            Summary(3, 1, 1, 0, 0.0, (), ())

    def test_rejects_errors_above_requests(self) -> None:
        with self.assertRaises(ContractError):
            Summary(1, 2, -1, 0, 0.0, (), ())

    def test_rejects_negative_per_minute(self) -> None:
        with self.assertRaises(ContractError):
            Summary(0, 0, 0, 0, -1.0, (), ())

    def test_rejects_unsorted_sections(self) -> None:
        with self.assertRaises(ContractError):
            Summary(2, 0, 2, 0, 0.0, (rec(0, 1), rec(1, 2)), ())
        with self.assertRaises(ContractError):
            Summary(2, 0, 2, 0, 0.0, (), (PathCount(1, "GET", "/b"), PathCount(1, "GET", "/a")))

    def test_rejects_more_rows_than_requests(self) -> None:
        with self.assertRaises(ContractError):
            Summary(1, 0, 1, 0, 0.0, (), (PathCount(2, "GET", "/a"),))


class PropertyTest(unittest.TestCase):
    def test_errors_never_exceed_requests(self) -> None:
        rng = random.Random(20260912)
        for _ in range(500):
            parsed = [self._generate(rng) for _ in range(rng.randrange(0, 60))]
            summary = summarize(parsed, rng.randint(1, 100))
            self.assertLessEqual(summary.errors, summary.requests)
            self.assertEqual(summary.requests, summary.errors + summary.successes)
            self.assertEqual(summary.requests + summary.malformed, len(parsed))

    @staticmethod
    def _generate(rng: random.Random) -> Record | Malformed:
        if rng.random() < 0.1:
            return Malformed("generated")
        return rec(rng.randrange(0, 10_000), rng.randint(0, UINT32_MAX), rng.randint(100, 599), rng.choice("/a /b /c".split()))


if __name__ == "__main__":
    unittest.main()
