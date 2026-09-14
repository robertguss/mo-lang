"""stats.py: counts, span, rankings, the contracts on Tally, Busy and Summary, and errors <= requests."""

from __future__ import annotations

import random
import unittest
from collections import Counter

from contracts import ContractViolation
from parse import UINT32_MAX, Record
from stats import Busy, Summary, Tally

SECOND = 1_000_000


def rec(ms: int = 10, second: int = 0, method: str = "GET", path: str = "/a", status: int = 200) -> Record:
    return Record(at=f"t+{second}s", instant=second * SECOND, method=method, path=path, status=status, duration_ms=ms)


def summarise(records: list[Record], top: int = 5, malformed: int = 0) -> Summary:
    tally = Tally(top)
    for record in records:
        tally.add(record)
    for _ in range(malformed):
        tally.add_malformed()
    return tally.summary()


class Counts(unittest.TestCase):
    def test_errors_are_statuses_500_to_599(self) -> None:
        statuses = [100, 200, 404, 499, 500, 503, 599]
        summary = summarise([rec(status=status) for status in statuses], malformed=2)
        self.assertEqual(
            (summary.requests, summary.errors, summary.successes, summary.malformed), (7, 3, 4, 2)
        )
        self.assertAlmostEqual(summary.error_rate, 3 / 7)

    def test_no_records(self) -> None:
        summary = summarise([])
        self.assertEqual((summary.requests, summary.per_minute, summary.error_rate), (0, 0.0, 0.0))
        self.assertEqual((summary.slowest, summary.busiest), ((), ()))


class PerMinute(unittest.TestCase):
    def test_a_single_request_is_zero(self) -> None:
        self.assertEqual(summarise([rec(second=5)]).per_minute, 0.0)

    def test_requests_at_one_instant_are_zero(self) -> None:
        self.assertEqual(summarise([rec(second=5)] * 3).per_minute, 0.0)

    def test_requests_over_the_first_to_last_span(self) -> None:
        self.assertEqual(summarise([rec(second=s) for s in (0, 30, 60)]).per_minute, 3.0)
        self.assertAlmostEqual(summarise([rec(second=s) for s in (0, 90)]).per_minute, 2 / 1.5)

    def test_the_span_is_earliest_to_latest_not_first_to_last_read(self) -> None:
        self.assertEqual(summarise([rec(second=s) for s in (60, 0, 30)]).per_minute, 3.0)


class Slowest(unittest.TestCase):
    def test_duration_descending_then_timestamp_ascending(self) -> None:
        records = [rec(ms=5, second=0), rec(ms=9, second=3), rec(ms=9, second=1), rec(ms=7, second=2)]
        slowest = summarise(records, top=3).slowest
        self.assertEqual([(r.duration_ms, r.instant // SECOND) for r in slowest], [(9, 1), (9, 3), (7, 2)])

    def test_full_ties_keep_arrival_order(self) -> None:
        records = [rec(ms=9, second=1, path="/first"), rec(ms=9, second=1, path="/second")]
        self.assertEqual([r.path for r in summarise(records, top=2).slowest], ["/first", "/second"])
        self.assertEqual([r.path for r in summarise(records, top=1).slowest], ["/first"])

    def test_late_slow_records_displace_early_fast_ones(self) -> None:
        slowest = summarise([rec(ms=ms, second=ms) for ms in range(1, 11)], top=3).slowest
        self.assertEqual([r.duration_ms for r in slowest], [10, 9, 8])


class Busiest(unittest.TestCase):
    RECORDS = (
        [rec(path="/b")] * 2
        + [rec(path="/a")] * 2
        + [rec(path="/c")] * 3
        + [rec(method="POST", path="/a")] * 2
        + [rec(path="/d")]
    )

    def test_count_descending_then_path_then_method(self) -> None:
        expected = (
            Busy(3, "GET", "/c"),
            Busy(2, "GET", "/a"),
            Busy(2, "POST", "/a"),
            Busy(2, "GET", "/b"),
            Busy(1, "GET", "/d"),
        )
        self.assertEqual(summarise(self.RECORDS, top=5).busiest, expected)

    def test_top_truncates(self) -> None:
        self.assertEqual(summarise(self.RECORDS, top=2).busiest, (Busy(3, "GET", "/c"), Busy(2, "GET", "/a")))


class TallyContracts(unittest.TestCase):
    def test_accepts_top_at_both_bounds(self) -> None:
        self.assertEqual((Tally(1).top, Tally(100).top), (1, 100))

    def test_rejects_top_0(self) -> None:
        with self.assertRaisesRegex(ContractViolation, "top is 1 to 100"):
            Tally(0)

    def test_rejects_top_101(self) -> None:
        with self.assertRaisesRegex(ContractViolation, "top is 1 to 100"):
            Tally(101)


def summary_with(
    requests: int = 2,
    errors: int = 1,
    successes: int = 1,
    malformed: int = 0,
    slowest: tuple[Record, ...] = (),
    busiest: tuple[Busy, ...] = (),
) -> Summary:
    return Summary(
        requests=requests,
        errors=errors,
        successes=successes,
        malformed=malformed,
        per_minute=0.0,
        slowest=slowest,
        busiest=busiest,
    )


class SummaryContracts(unittest.TestCase):
    def test_accepts_a_consistent_summary(self) -> None:
        self.assertEqual(summary_with().requests, 2)

    def test_rejects_requests_other_than_errors_plus_successes(self) -> None:
        with self.assertRaisesRegex(ContractViolation, "requests equals errors \\+ successes"):
            summary_with(requests=3)

    def test_rejects_errors_above_requests(self) -> None:
        with self.assertRaisesRegex(ContractViolation, "errors <= requests"):
            summary_with(requests=1, errors=2, successes=-1)

    def test_rejects_negative_malformed(self) -> None:
        with self.assertRaisesRegex(ContractViolation, "not negative"):
            summary_with(malformed=-1)

    def test_rejects_unsorted_slowest(self) -> None:
        with self.assertRaisesRegex(ContractViolation, "slowest by duration descending"):
            summary_with(slowest=(rec(ms=1), rec(ms=2)))

    def test_rejects_unsorted_busiest(self) -> None:
        with self.assertRaisesRegex(ContractViolation, "busiest by count descending"):
            summary_with(busiest=(Busy(1, "GET", "/a"), Busy(2, "GET", "/b")))

    def test_busy_rejects_a_zero_count(self) -> None:
        with self.assertRaisesRegex(ContractViolation, "count is at least 1"):
            Busy(0, "GET", "/a")

    def test_busy_rejects_a_card_number(self) -> None:
        with self.assertRaisesRegex(ContractViolation, "path holds no card number"):
            Busy(1, "GET", "/4111111111111111")


def random_record(rng: random.Random) -> Record:
    return rec(
        ms=rng.choice([rng.randint(0, 20), rng.randint(0, UINT32_MAX)]),
        second=rng.randint(0, 50),
        method=rng.choice(["GET", "POST"]),
        path=rng.choice(["/a", "/b", "/c", "/d"]),
        status=rng.randint(100, 599),
    )


def reference_slowest(records: list[Record], top: int) -> list[Record]:
    order = sorted(range(len(records)), key=lambda i: (-records[i].duration_ms, records[i].instant, i))
    return [records[i] for i in order[:top]]


def reference_busiest(records: list[Record], top: int) -> list[Busy]:
    counts = Counter((record.method, record.path) for record in records)
    ranked = sorted(counts.items(), key=lambda item: (-item[1], item[0][1], item[0][0]))
    return [Busy(count, method, path) for (method, path), count in ranked[:top]]


class Properties(unittest.TestCase):
    def test_errors_never_exceed_requests_for_any_list_of_records(self) -> None:
        for seed in range(300):
            rng = random.Random(seed)
            records = [random_record(rng) for _ in range(rng.randrange(0, 150))]
            top = rng.randint(1, 100)
            summary = summarise(records, top, malformed=rng.randrange(0, 5))
            with self.subTest(seed=seed):
                self.assertLessEqual(summary.errors, summary.requests)
                self.assertEqual(summary.requests, summary.errors + summary.successes)
                self.assertEqual(summary.requests, len(records))
                self.assertEqual(summary.errors, sum(500 <= record.status <= 599 for record in records))

    def test_rankings_match_a_full_sort_for_any_list_of_records(self) -> None:
        for seed in range(300):
            rng = random.Random(seed)
            records = [random_record(rng) for _ in range(rng.randrange(0, 150))]
            top = rng.randint(1, 20)
            summary = summarise(records, top)
            with self.subTest(seed=seed):
                self.assertEqual(list(summary.slowest), reference_slowest(records, top))
                self.assertEqual(list(summary.busiest), reference_busiest(records, top))


if __name__ == "__main__":
    unittest.main()
