"""report.py: each text section, the JSON object, number formats, and the card check on output."""

from __future__ import annotations

import json
import unittest

from contracts import ContractViolation
from parse import parse_line
from report import (
    busiest_section,
    checked_output,
    counts_section,
    one_decimal,
    render_json,
    render_text,
    slowest_section,
    thousands,
)
from stats import Summary, Tally

SMALL = [
    "2026-09-12T10:00:00Z GET /api/users 200 12",
    "2026-09-12T10:00:30Z POST /api/orders 500 1340",
    "2026-09-12T10:01:00Z GET /api/users 200 9",
]


def small_summary(top: int = 5, lines: list[str] = SMALL) -> Summary:
    tally = Tally(top)
    for text in lines:
        tally.add(parse_line(text))
    tally.add_malformed()
    return tally.summary()


class Numbers(unittest.TestCase):
    def test_thousands_use_underscores(self) -> None:
        for number, expected in ((0, "0"), (999, "999"), (1_000, "1_000"), (1_234_567, "1_234_567")):
            with self.subTest(number=number):
                self.assertEqual(thousands(number), expected)

    def test_one_decimal_with_underscores(self) -> None:
        for number, expected in ((0.0, "0.0"), (16 / 3.5, "4.6"), (1234.56, "1_234.6")):
            with self.subTest(number=number):
                self.assertEqual(one_decimal(number), expected)


class TextSections(unittest.TestCase):
    def test_counts_section(self) -> None:
        self.assertEqual(
            counts_section(small_summary()),
            ["requests     3", "errors       1  (33.3%)", "malformed    1", "per minute 3.0"],
        )

    def test_counts_section_with_the_spec_numbers(self) -> None:
        summary = Summary(
            requests=1_204, errors=37, successes=1_167, malformed=2, per_minute=40.1, slowest=(), busiest=()
        )
        self.assertEqual(
            counts_section(summary),
            ["requests   1_204", "errors        37  (3.1%)", "malformed      2", "per minute  40.1"],
        )

    def test_slowest_section(self) -> None:
        self.assertEqual(
            slowest_section(small_summary().slowest),
            [
                "  1_340 ms  POST /api/orders   2026-09-12T10:00:30Z",
                "     12 ms  GET /api/users     2026-09-12T10:00:00Z",
                "      9 ms  GET /api/users     2026-09-12T10:01:00Z",
            ],
        )

    def test_busiest_section(self) -> None:
        self.assertEqual(busiest_section(small_summary().busiest), ["  2  GET /api/users", "  1  POST /api/orders"])

    def test_top_limits_both_lists(self) -> None:
        summary = small_summary(top=1)
        self.assertEqual(slowest_section(summary.slowest), ["  1_340 ms  POST /api/orders   2026-09-12T10:00:30Z"])
        self.assertEqual(busiest_section(summary.busiest), ["  2  GET /api/users"])

    def test_whole_report(self) -> None:
        self.assertEqual(
            render_text(small_summary()),
            "requests     3\n"
            "errors       1  (33.3%)\n"
            "malformed    1\n"
            "per minute 3.0\n"
            "\n"
            "slowest\n"
            "  1_340 ms  POST /api/orders   2026-09-12T10:00:30Z\n"
            "     12 ms  GET /api/users     2026-09-12T10:00:00Z\n"
            "      9 ms  GET /api/users     2026-09-12T10:01:00Z\n"
            "\n"
            "busiest\n"
            "  2  GET /api/users\n"
            "  1  POST /api/orders\n",
        )

    def test_report_with_no_requests(self) -> None:
        self.assertEqual(
            render_text(Tally(5).summary()),
            "requests     0\nerrors       0  (0.0%)\nmalformed    0\nper minute 0.0\n\nslowest\n\nbusiest\n",
        )


class Json(unittest.TestCase):
    def test_one_object_in_the_spec_key_order(self) -> None:
        self.assertEqual(
            render_json(small_summary()),
            '{"requests": 3, "errors": 1, "error_rate": 0.333, "malformed": 1, "per_minute": 3.0, '
            '"slowest": [{"ms": 1340, "method": "POST", "path": "/api/orders", "at": "2026-09-12T10:00:30Z"}, '
            '{"ms": 12, "method": "GET", "path": "/api/users", "at": "2026-09-12T10:00:00Z"}, '
            '{"ms": 9, "method": "GET", "path": "/api/users", "at": "2026-09-12T10:01:00Z"}], '
            '"busiest": [{"count": 2, "method": "GET", "path": "/api/users"}, '
            '{"count": 1, "method": "POST", "path": "/api/orders"}]}\n',
        )

    def test_parses_back_with_the_same_keys(self) -> None:
        parsed = json.loads(render_json(small_summary()))
        self.assertEqual(
            list(parsed), ["requests", "errors", "error_rate", "malformed", "per_minute", "slowest", "busiest"]
        )

    def test_no_requests(self) -> None:
        parsed = json.loads(render_json(Tally(5).summary()))
        self.assertEqual((parsed["error_rate"], parsed["per_minute"], parsed["slowest"]), (0.0, 0.0, []))

    def test_non_ascii_paths_stay_readable(self) -> None:
        summary = small_summary(lines=["2026-09-12T10:00:00Z GET /café 200 1"])
        self.assertIn('"path": "/café"', render_json(summary))


class CardCheck(unittest.TestCase):
    def test_rejects_output_holding_a_card_number(self) -> None:
        with self.assertRaisesRegex(ContractViolation, "no card number reaches stdout"):
            checked_output("  1 GET /cards/4111111111111111\n")

    def test_masked_paths_pass_through_both_renderings(self) -> None:
        summary = small_summary(lines=["2026-09-12T10:00:00Z GET /cards/4111111111111111 200 1"])
        for rendered in (render_text(summary), render_json(summary)):
            with self.subTest(rendered=rendered):
                self.assertIn("/cards/****************", rendered)
                self.assertNotIn("4111111111111111", rendered)


if __name__ == "__main__":
    unittest.main()
