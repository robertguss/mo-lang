import random
import unittest
from datetime import UTC, datetime, timedelta

from logstat.contract import ContractError
from logstat.record import LogRecord
from logstat.summary import Summary, Tally, per_minute

T0 = datetime(2026, 9, 12, 10, 0, 0, tzinfo=UTC)


def record(
    seconds: float, method: str = "GET", path: str = "/a", status: int = 200, ms: int = 1
) -> LogRecord:
    return LogRecord(
        at=T0 + timedelta(seconds=seconds),
        method=method,
        path=path,
        status=status,
        duration_ms=ms,
    )


def summarize(records: list[LogRecord], top: int = 5, since: datetime | None = None) -> Summary:
    tally = Tally(top, since)
    for each in records:
        tally.add(each)
    return tally.summary()


class TotalsTest(unittest.TestCase):
    def test_counts_requests_errors_and_malformed(self) -> None:
        tally = Tally(5)
        for status in (200, 404, 500, 599, 301):
            tally.add(record(0, status=status))
        tally.add_malformed()
        summary = tally.summary()
        self.assertEqual((summary.requests, summary.errors, summary.malformed), (5, 2, 1))
        self.assertEqual(summary.error_rate, 0.4)

    def test_no_requests_is_all_zero(self) -> None:
        summary = summarize([])
        self.assertEqual((summary.requests, summary.errors), (0, 0))
        self.assertEqual((summary.error_rate, summary.per_minute), (0.0, 0.0))

    def test_error_rate_is_rounded_to_three_places(self) -> None:
        records = [record(0, status=500)] * 37 + [record(0)] * (1204 - 37)
        self.assertEqual(summarize(records).error_rate, 0.031)

    def test_since_ignores_earlier_lines(self) -> None:
        summary = summarize([record(0), record(10, status=500), record(20)], since=T0 + timedelta(seconds=10))
        self.assertEqual((summary.requests, summary.errors), (2, 1))


class PerMinuteTest(unittest.TestCase):
    def test_requests_over_the_span_in_minutes(self) -> None:
        self.assertEqual(per_minute(16, T0, T0 + timedelta(seconds=210)), 4.6)

    def test_a_single_request_is_zero(self) -> None:
        self.assertEqual(per_minute(1, T0, T0), 0.0)

    def test_an_empty_span_is_zero(self) -> None:
        self.assertEqual(per_minute(3, T0, T0), 0.0)

    def test_the_span_is_first_to_last_not_file_order(self) -> None:
        summary = summarize([record(60), record(0), record(30)])
        self.assertEqual(summary.per_minute, 3.0)


class SlowestTest(unittest.TestCase):
    def test_duration_descending_then_timestamp_ascending(self) -> None:
        summary = summarize(
            [record(3, path="/c", ms=340), record(1, path="/a", ms=12), record(2, path="/b", ms=340)],
            top=3,
        )
        self.assertEqual([(e.ms, e.path) for e in summary.slowest], [(340, "/b"), (340, "/c"), (12, "/a")])

    def test_keeps_only_the_top_n(self) -> None:
        summary = summarize([record(i, ms=i) for i in range(50)], top=3)
        self.assertEqual([e.ms for e in summary.slowest], [49, 48, 47])

    def test_a_full_tie_keeps_input_order(self) -> None:
        summary = summarize([record(0, path=f"/{i}", ms=5) for i in range(4)], top=2)
        self.assertEqual([e.path for e in summary.slowest], ["/0", "/1"])

    def test_at_is_printed_in_utc(self) -> None:
        self.assertEqual(summarize([record(2)]).slowest[0].at, "2026-09-12T10:00:02Z")


class BusiestTest(unittest.TestCase):
    def test_count_descending_then_path_ascending(self) -> None:
        records = [record(0, path="/z")] * 2 + [record(0, path="/b"), record(0, path="/a")] + [record(0, path="/m")] * 3
        summary = summarize(records)
        self.assertEqual(
            [(e.count, e.path) for e in summary.busiest], [(3, "/m"), (2, "/z"), (1, "/a"), (1, "/b")]
        )

    def test_method_and_path_are_counted_apart(self) -> None:
        summary = summarize([record(0, method="POST"), record(0, method="GET"), record(0, method="GET")])
        self.assertEqual([(e.count, e.method) for e in summary.busiest], [(2, "GET"), (1, "POST")])

    def test_same_count_and_path_orders_by_method(self) -> None:
        summary = summarize([record(0, method="POST"), record(0, method="DELETE")])
        self.assertEqual([e.method for e in summary.busiest], ["DELETE", "POST"])

    def test_keeps_only_the_top_n(self) -> None:
        summary = summarize([record(0, path=f"/{i:03d}") for i in range(10)], top=2)
        self.assertEqual([e.path for e in summary.busiest], ["/000", "/001"])


class ContractTest(unittest.TestCase):
    def test_rejects_top_below_1(self) -> None:
        with self.assertRaises(ContractError):
            Tally(0)

    def test_rejects_top_above_100(self) -> None:
        with self.assertRaises(ContractError):
            Tally(101)

    def test_rejects_since_without_a_zone(self) -> None:
        with self.assertRaises(ContractError):
            Tally(5, datetime(2026, 9, 12))

    def test_ensures_requests_equals_errors_plus_successes(self) -> None:
        tally = Tally(5)
        tally.add(record(0))
        tally.successes += 1
        with self.assertRaisesRegex(ContractError, "requests == errors \\+ successes"):
            tally.summary()

    def test_ensures_errors_at_most_requests(self) -> None:
        tally = Tally(5)
        tally.errors, tally.successes = 2, -1
        tally.requests = 1
        with self.assertRaisesRegex(ContractError, "errors <= requests"):
            tally.summary()


class PropertyTest(unittest.TestCase):
    """For any list of records: errors <= requests, and requests == errors + successes."""

    def test_errors_never_exceed_requests(self) -> None:
        for seed in range(500):
            rng = random.Random(seed)
            records = [
                record(
                    rng.uniform(-1e6, 1e6),
                    method=rng.choice(["GET", "POST", "PUT"]),
                    path=rng.choice(["/", "/a", "/b/c"]),
                    status=rng.randint(100, 599),
                    ms=rng.randint(0, 4_294_967_295),
                )
                for _ in range(rng.randint(0, 60))
            ]
            top = rng.randint(1, 100)
            summary = summarize(records, top=top)
            with self.subTest(seed=seed):
                self.assertLessEqual(summary.errors, summary.requests)
                self.assertEqual(summary.requests, len(records))
                self.assertEqual(summary.errors, sum(1 for r in records if r.status >= 500))
                self.assertLessEqual(len(summary.slowest), top)
                self.assertEqual(sum(e.count for e in summary.busiest) <= summary.requests, True)
                durations = [e.ms for e in summary.slowest]
                self.assertEqual(durations, sorted(durations, reverse=True))
                self.assertEqual(durations, sorted((r.duration_ms for r in records), reverse=True)[:top])


if __name__ == "__main__":
    unittest.main()
