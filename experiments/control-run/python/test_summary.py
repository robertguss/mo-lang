import random
import unittest
from datetime import datetime, timedelta, timezone

from parse import Record
from summary import Accumulator, PathCount, Summary, busiest_key, slowest_key, summarize

BASE = datetime(2026, 9, 12, 10, 0, 0, tzinfo=timezone.utc)


def rec(ms: int, second: int, method: str = "GET", path: str = "/a", status: int = 200) -> Record:
    return Record(BASE + timedelta(seconds=second), method, path, status, ms)


def summary_fields(**overrides: object) -> dict[str, object]:
    fields: dict[str, object] = {
        "top": 5,
        "requests": 2,
        "errors": 1,
        "successes": 1,
        "malformed": 0,
        "first_at": BASE,
        "last_at": BASE,
        "slowest": (),
        "busiest": (),
    }
    fields.update(overrides)
    return fields


class CountsTest(unittest.TestCase):
    def test_counts_errors_successes_and_malformed(self) -> None:
        summary = summarize([rec(1, 0, status=200), rec(1, 1, status=500), rec(1, 2, status=404)], 5, malformed=2)
        self.assertEqual((summary.requests, summary.errors, summary.successes, summary.malformed), (3, 1, 2, 2))
        self.assertAlmostEqual(summary.error_rate, 1 / 3)

    def test_per_minute_uses_first_and_last_timestamp_in_any_order(self) -> None:
        summary = summarize([rec(1, 90), rec(1, 0), rec(1, 30), rec(1, 60)], 5)
        self.assertEqual(summary.per_minute, 4 / 1.5)

    def test_single_request_and_zero_span_are_zero_per_minute(self) -> None:
        self.assertEqual(summarize([rec(1, 0)], 5).per_minute, 0.0)
        self.assertEqual(summarize([rec(1, 0), rec(2, 0)], 5).per_minute, 0.0)

    def test_no_requests(self) -> None:
        summary = summarize([], 5, malformed=3)
        self.assertEqual((summary.requests, summary.error_rate, summary.per_minute), (0, 0.0, 0.0))
        self.assertEqual((summary.slowest, summary.busiest), ((), ()))


class OrderingTest(unittest.TestCase):
    def test_slowest_by_duration_descending_then_timestamp_ascending(self) -> None:
        records = [rec(340, 30, path="/c"), rec(1204, 20), rec(340, 2, path="/b"), rec(95, 1), rec(340, 15, "DELETE")]
        slowest = summarize(records, 4).slowest
        self.assertEqual([(r.duration_ms, r.at.second) for r in slowest], [(1204, 20), (340, 2), (340, 15), (340, 30)])

    def test_busiest_by_count_descending_then_path_ascending(self) -> None:
        records = [rec(1, 0, path="/z"), rec(1, 1, path="/health"), rec(1, 2, path="/z"), rec(1, 3, path="/api")]
        records += [rec(1, 4, "POST", "/api"), rec(1, 5, path="/health")]
        busiest = summarize(records, 3).busiest
        self.assertEqual(
            busiest, (PathCount(2, "GET", "/health"), PathCount(2, "GET", "/z"), PathCount(1, "GET", "/api"))
        )

    def test_method_and_path_are_counted_together(self) -> None:
        busiest = summarize([rec(1, 0, "GET", "/a"), rec(1, 1, "POST", "/a")], 5).busiest
        self.assertEqual(busiest, (PathCount(1, "GET", "/a"), PathCount(1, "POST", "/a")))

    def test_bounded_pool_matches_a_full_sort(self) -> None:
        rng = random.Random(7)
        records = [rec(rng.randrange(50), rng.randrange(600), path=f"/{rng.randrange(9)}") for _ in range(2_000)]
        for top in (1, 5, 100):
            with self.subTest(top):
                summary = summarize(records, top)
                self.assertEqual(list(summary.slowest), sorted(records, key=slowest_key)[:top])


class PropertyTest(unittest.TestCase):
    def test_errors_never_exceed_requests_for_any_records(self) -> None:
        for seed in range(300):
            rng = random.Random(seed)
            records = [
                rec(rng.randrange(5_000), rng.randrange(-10**6, 10**6), rng.choice(["GET", "POST"]),
                    f"/{rng.randrange(20)}", rng.randrange(100, 600))
                for _ in range(rng.randrange(0, 200))
            ]
            with self.subTest(seed=seed):
                summary = summarize(records, rng.randrange(1, 101), malformed=rng.randrange(10))
                self.assertLessEqual(summary.errors, summary.requests)
                self.assertEqual(summary.requests, summary.errors + summary.successes)
                self.assertEqual(summary.requests, len(records))
                self.assertEqual(summary.errors, sum(1 for r in records if 500 <= r.status <= 599))


class ContractTest(unittest.TestCase):
    def test_rejects_top_outside_1_to_100(self) -> None:
        for top in (0, 101):
            with self.subTest(top):
                with self.assertRaises(ValueError):
                    Accumulator(top)
                with self.assertRaises(ValueError):
                    Summary(**summary_fields(top=top))  # type: ignore[arg-type]

    def test_rejects_errors_over_requests(self) -> None:
        with self.assertRaises(ValueError):
            Summary(**summary_fields(requests=1, errors=2, successes=-1))  # type: ignore[arg-type]

    def test_rejects_requests_not_errors_plus_successes(self) -> None:
        with self.assertRaises(ValueError):
            Summary(**summary_fields(requests=3))  # type: ignore[arg-type]

    def test_rejects_negative_malformed(self) -> None:
        with self.assertRaises(ValueError):
            Summary(**summary_fields(malformed=-1))  # type: ignore[arg-type]

    def test_rejects_span_that_disagrees_with_requests(self) -> None:
        for fields in (summary_fields(first_at=None), summary_fields(last_at=BASE - timedelta(seconds=1))):
            with self.subTest(fields), self.assertRaises(ValueError):
                Summary(**fields)  # type: ignore[arg-type]

    def test_rejects_unsorted_or_overlong_lists(self) -> None:
        bad = [
            summary_fields(slowest=(rec(1, 0), rec(2, 0))),
            summary_fields(busiest=(PathCount(1, "GET", "/a"), PathCount(2, "GET", "/b"))),
            summary_fields(top=1, slowest=(rec(2, 0), rec(1, 0))),
            summary_fields(busiest=(PathCount(1, "GET", "/a"),) * 3),
        ]
        for fields in bad:
            with self.subTest(fields), self.assertRaises(ValueError):
                Summary(**fields)  # type: ignore[arg-type]

    def test_rejects_zero_path_count(self) -> None:
        with self.assertRaises(ValueError):
            PathCount(0, "GET", "/a")

    def test_keys_are_total_orders_on_the_output_fields(self) -> None:
        self.assertLess(slowest_key(rec(5, 0, "GET")), slowest_key(rec(5, 0, "POST")))
        self.assertLess(busiest_key(PathCount(1, "POST", "/a")), busiest_key(PathCount(1, "GET", "/b")))


if __name__ == "__main__":
    unittest.main()
