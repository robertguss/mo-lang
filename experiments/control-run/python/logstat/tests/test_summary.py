import random
import unittest
from datetime import UTC, datetime, timedelta

from logstat.contract import ContractError
from logstat.records import Record
from logstat.summary import Accumulator, BusyPath, analyze, is_busiest_order, is_slowest_order

BASE = datetime(2026, 9, 12, 10, 0, 0, tzinfo=UTC)


def line(seconds: int, method: str, path: str, status: int, ms: int) -> bytes:
    stamp = (BASE + timedelta(seconds=seconds)).strftime("%Y-%m-%dT%H:%M:%SZ")
    return f"{stamp} {method} {path} {status} {ms}\n".encode()


def record(seconds: int, method: str, path: str, status: int, ms: int) -> Record:
    at = BASE + timedelta(seconds=seconds)
    return Record(
        at=at,
        at_text=at.isoformat(),
        method=method,
        path=path,
        status=status,
        duration_ms=ms,
    )


class CountsTest(unittest.TestCase):
    def test_counts_errors_malformed_and_rate(self) -> None:
        lines = [
            line(0, "GET", "/a", 200, 1),
            line(1, "GET", "/a", 500, 1),
            line(2, "GET", "/a", 599, 1),
            line(3, "GET", "/a", 404, 1),
            b"garbage\n",
            b"\n",
        ]
        summary = analyze(lines, 5, None)
        self.assertEqual((summary.requests, summary.errors, summary.malformed), (4, 2, 1))
        self.assertEqual(summary.error_rate, 0.5)

    def test_error_rate_rounds_to_three_places(self) -> None:
        lines = [line(i, "GET", "/a", 500 if i == 0 else 200, 1) for i in range(3)]
        self.assertEqual(analyze(lines, 5, None).error_rate, 0.333)

    def test_no_records_gives_zeros(self) -> None:
        summary = analyze([b"bad\n"], 5, None)
        self.assertEqual((summary.requests, summary.error_rate, summary.per_minute), (0, 0.0, 0.0))
        self.assertEqual((summary.slowest, summary.busiest), ([], []))


class PerMinuteTest(unittest.TestCase):
    def test_a_single_request_is_zero(self) -> None:
        self.assertEqual(analyze([line(0, "GET", "/a", 200, 1)], 5, None).per_minute, 0.0)

    def test_requests_at_one_instant_are_zero(self) -> None:
        lines = [line(0, "GET", "/a", 200, 1)] * 3
        self.assertEqual(analyze(lines, 5, None).per_minute, 0.0)

    def test_divides_by_the_span_between_first_and_last(self) -> None:
        lines = [line(120, "GET", "/a", 200, 1), line(0, "GET", "/a", 200, 1)]
        lines.append(line(60, "GET", "/a", 200, 1))
        self.assertEqual(analyze(lines, 5, None).per_minute, 1.5)


class SinceTest(unittest.TestCase):
    def test_ignores_lines_before_since_but_counts_malformed(self) -> None:
        lines = [line(0, "GET", "/old", 500, 1), b"bad\n", line(60, "GET", "/new", 200, 1)]
        summary = analyze(lines, 5, BASE + timedelta(seconds=60))
        self.assertEqual((summary.requests, summary.errors, summary.malformed), (1, 0, 1))
        self.assertEqual([b.path for b in summary.busiest], ["/new"])


class SlowestTest(unittest.TestCase):
    def test_duration_desc_then_timestamp_asc(self) -> None:
        lines = [
            line(30, "GET", "/c", 200, 50),
            line(10, "GET", "/b", 200, 50),
            line(0, "GET", "/a", 200, 10),
            line(5, "GET", "/d", 200, 90),
        ]
        summary = analyze(lines, 3, None)
        slowest = [(s.ms, s.path) for s in summary.slowest]
        self.assertEqual(slowest, [(90, "/d"), (50, "/b"), (50, "/c")])

    def test_ties_on_both_keep_input_order(self) -> None:
        lines = [line(0, "GET", "/first", 200, 5), line(0, "GET", "/second", 200, 5)]
        self.assertEqual([s.path for s in analyze(lines, 5, None).slowest], ["/first", "/second"])


class BusiestTest(unittest.TestCase):
    def test_count_desc_then_path_asc(self) -> None:
        lines = [
            line(0, "GET", "/z", 200, 1),
            line(1, "GET", "/z", 200, 1),
            line(2, "POST", "/b", 200, 1),
            line(3, "GET", "/a", 200, 1),
        ]
        summary = analyze(lines, 2, None)
        self.assertEqual([(b.count, b.path) for b in summary.busiest], [(2, "/z"), (1, "/a")])

    def test_method_and_path_are_counted_together(self) -> None:
        lines = [line(0, "GET", "/a", 200, 1), line(1, "POST", "/a", 200, 1)]
        busiest = analyze(lines, 5, None).busiest
        self.assertEqual([(b.method, b.count) for b in busiest], [("GET", 1), ("POST", 1)])


class ContractsTest(unittest.TestCase):
    def test_rejects_top_outside_1_to_100(self) -> None:
        for top in (0, 101):
            with self.assertRaisesRegex(ContractError, "requires top is 1 to 100"):
                Accumulator(top)

    def test_rejects_since_without_offset(self) -> None:
        with self.assertRaisesRegex(ContractError, "requires since carries a UTC offset"):
            analyze([], 5, datetime(2026, 9, 12))

    def test_the_invariant_catches_a_broken_count(self) -> None:
        accumulator = Accumulator(5)
        accumulator.errors = 1
        with self.assertRaisesRegex(ContractError, "invariant requests = errors \\+ successes"):
            accumulator.add(record(0, "GET", "/a", 200, 1))

    def test_the_ensure_catches_errors_past_requests(self) -> None:
        accumulator = Accumulator(5)
        accumulator.errors = 1
        accumulator.successes = -1
        with self.assertRaisesRegex(ContractError, "ensures"):
            accumulator.finish()

    def test_order_checks_reject_a_wrong_order(self) -> None:
        self.assertFalse(is_slowest_order([(1, 0, -1), (2, 0, -2)]))
        self.assertFalse(is_slowest_order([(1, -5, -1), (1, -1, -2)]))
        self.assertTrue(is_slowest_order([(2, -1, -1), (1, -5, -2)]))
        wrong = [BusyPath(count=1, method="GET", path=p) for p in ("/b", "/a")]
        self.assertFalse(is_busiest_order(wrong))
        self.assertTrue(is_busiest_order(wrong[::-1]))


class PropertyTest(unittest.TestCase):
    """For any list of records: errors <= requests, and both lists match a full sort."""

    def test_errors_never_exceed_requests(self) -> None:
        for seed in range(200):
            rng = random.Random(seed)
            records = [
                record(
                    rng.randrange(0, 600),
                    rng.choice(["GET", "POST", "DELETE"]),
                    rng.choice(["/a", "/b", "/c", "/d"]),
                    rng.randrange(100, 600),
                    rng.randrange(0, 20),
                )
                for _ in range(rng.randrange(0, 60))
            ]
            top = rng.randrange(1, 8)
            accumulator = Accumulator(top)
            for r in records:
                accumulator.add(r)
            summary = accumulator.finish()
            errors = sum(1 for r in records if 500 <= r.status <= 599)
            self.assertLessEqual(summary.errors, summary.requests, seed)
            self.assertEqual((summary.requests, summary.errors), (len(records), errors), seed)
            indexed = sorted(enumerate(records), key=lambda p: (-p[1].duration_ms, p[1].at, p[0]))
            expected_slowest = [(r.duration_ms, r.path, r.at_text) for _, r in indexed[:top]]
            actual_slowest = [(s.ms, s.path, s.at) for s in summary.slowest]
            self.assertEqual(actual_slowest, expected_slowest, seed)
            counts: dict[tuple[str, str], int] = {}
            for r in records:
                counts[(r.method, r.path)] = counts.get((r.method, r.path), 0) + 1
            ranked = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0][1], kv[0][0]))[:top]
            actual_busiest = [((b.method, b.path), b.count) for b in summary.busiest]
            self.assertEqual(actual_busiest, ranked, seed)


if __name__ == "__main__":
    unittest.main()
