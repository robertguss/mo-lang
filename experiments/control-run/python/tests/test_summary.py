import random
import unittest
from fractions import Fraction

from logstat.contracts import ContractError
from logstat.record import Record
from logstat.summary import (
    PathCount,
    Summary,
    Tally,
    busy_key,
    error_rate,
    per_minute,
    slow_key,
    summarize,
)
from tests.support import BASE, rec, random_record


def summary(**changes: object) -> Summary:
    fields: dict[str, object] = {
        "requests": 2,
        "errors": 1,
        "successes": 1,
        "malformed": 0,
        "first_epoch": BASE,
        "last_epoch": BASE + 60,
        "slowest": (),
        "busiest": (),
    }
    fields.update(changes)
    return Summary(**fields)  # type: ignore[arg-type]


class CountsTest(unittest.TestCase):
    def test_counts_requests_errors_successes_malformed(self) -> None:
        records = [rec(status=s) for s in [200, 404, 499, 500, 503, 599, 100]]
        result = summarize(records, malformed=2)
        self.assertEqual(
            (result.requests, result.errors, result.successes, result.malformed), (7, 3, 4, 2)
        )

    def test_empty(self) -> None:
        result = summarize([])
        self.assertEqual((result.requests, result.first_epoch, result.slowest), (0, None, ()))
        self.assertEqual((per_minute(result), error_rate(result)), (0, 0))

    def test_error_rate(self) -> None:
        records = [rec(status=500)] * 3 + [rec()] * 13
        self.assertEqual(error_rate(summarize(records)), Fraction(3, 16))


class PerMinuteTest(unittest.TestCase):
    def test_requests_over_first_to_last_span(self) -> None:
        records = [rec(offset=210), rec(offset=1), rec(offset=100), rec(offset=211)]
        result = summarize(records)
        self.assertEqual((result.first_epoch, result.last_epoch), (BASE + 1, BASE + 211))
        self.assertEqual(per_minute(result), Fraction(4 * 60, 210))

    def test_single_request_is_zero(self) -> None:
        self.assertEqual(per_minute(summarize([rec()])), 0)

    def test_zero_span_is_zero(self) -> None:
        self.assertEqual(per_minute(summarize([rec(offset=5), rec(offset=5)])), 0)


class SlowestTest(unittest.TestCase):
    def test_duration_descending_then_timestamp_ascending(self) -> None:
        records = [rec(offset=9, ms=340), rec(offset=1, ms=12), rec(offset=2, ms=340), rec(offset=0, ms=1204)]
        result = summarize(records, top=3)
        self.assertEqual(
            [(r.duration_ms, r.epoch - BASE) for r in result.slowest], [(1204, 0), (340, 2), (340, 9)]
        )

    def test_full_ties_keep_input_order(self) -> None:
        records = [rec(path=p, ms=7) for p in ["/z", "/a", "/m"]]
        self.assertEqual([r.path for r in summarize(records).slowest], ["/z", "/a", "/m"])

    def test_keeps_the_top_across_trims(self) -> None:
        records = [rec(offset=i % 7, ms=(i * 37) % 101) for i in range(500)]
        expected = sorted(records, key=slow_key)[:4]
        self.assertEqual(list(summarize(records, top=4).slowest), expected)


class BusiestTest(unittest.TestCase):
    def test_count_descending_then_path_then_method(self) -> None:
        records = [
            rec(path="/users"), rec(path="/users"), rec(path="/health"), rec(path="/cards"),
            rec(method="POST", path="/cards"), rec(path="/orders"),
        ]  # fmt: skip
        self.assertEqual(
            summarize(records, top=4).busiest,
            (
                PathCount(2, "GET", "/users"),
                PathCount(1, "GET", "/cards"),
                PathCount(1, "POST", "/cards"),
                PathCount(1, "GET", "/health"),
            ),
        )


class TopContractTest(unittest.TestCase):
    def test_accepts_1_and_100(self) -> None:
        for top in [1, 100]:
            with self.subTest(top=top):
                self.assertEqual(len(summarize([rec(offset=i) for i in range(150)], top=top).slowest), top)

    def test_rejects_top_outside_1_to_100(self) -> None:
        for top in [0, 101, -5]:
            with self.subTest(top=top), self.assertRaises(ContractError):
                Tally(top)


class SummaryContractTest(unittest.TestCase):
    def test_a_valid_summary_builds(self) -> None:
        self.assertEqual(summary().requests, 2)

    def test_rejects_requests_not_errors_plus_successes(self) -> None:
        with self.assertRaises(ContractError):
            summary(successes=2)

    def test_rejects_errors_above_requests(self) -> None:
        with self.assertRaises(ContractError):
            summary(requests=2, errors=3, successes=-1)

    def test_rejects_negative_counts(self) -> None:
        for changes in [{"malformed": -1}, {"requests": 0, "errors": 1, "successes": -1}]:
            with self.subTest(changes=changes), self.assertRaises(ContractError):
                summary(**changes)

    def test_rejects_span_without_requests(self) -> None:
        with self.assertRaises(ContractError):
            summary(requests=0, errors=0, successes=0)

    def test_rejects_first_after_last(self) -> None:
        with self.assertRaises(ContractError):
            summary(first_epoch=BASE + 61)

    def test_rejects_more_slowest_than_requests(self) -> None:
        with self.assertRaises(ContractError):
            summary(slowest=(rec(), rec(), rec()))

    def test_rejects_unsorted_slowest(self) -> None:
        with self.assertRaises(ContractError):
            summary(slowest=(rec(ms=1), rec(ms=2)))

    def test_rejects_unsorted_busiest(self) -> None:
        with self.assertRaises(ContractError):
            summary(busiest=(PathCount(1, "GET", "/a"), PathCount(2, "GET", "/b")))


class PropertyTest(unittest.TestCase):
    """For any list of records: errors <= requests, and the lists match a naive sort."""

    def test_errors_never_exceed_requests(self) -> None:
        rng = random.Random(20260912)
        for trial in range(400):
            records = [random_record(rng) for _ in range(rng.randrange(0, 120))]
            top = rng.randrange(1, 101)
            malformed = rng.randrange(0, 5)
            with self.subTest(trial=trial):
                result = summarize(records, top=top, malformed=malformed)
                self.assertLessEqual(result.errors, result.requests)
                self.assertEqual(result.requests, result.errors + result.successes)
                self.assertEqual(result.requests, len(records))
                self.assertEqual(list(result.slowest), sorted(records, key=slow_key)[:top])
                self.assertEqual(list(result.busiest), naive_busiest(records)[:top])


def naive_busiest(records: list[Record]) -> list[PathCount]:
    keys = sorted({(r.method, r.path) for r in records})
    counts = [PathCount(sum((r.method, r.path) == k for r in records), *k) for k in keys]
    return sorted(counts, key=busy_key)


if __name__ == "__main__":
    unittest.main()
