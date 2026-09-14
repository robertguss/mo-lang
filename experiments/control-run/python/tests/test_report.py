import json
import unittest
from fractions import Fraction

from logstat.contracts import ContractError
from logstat.report import busiest_lines, fixed, group, overview_lines, render_json, render_text, slowest_lines
from logstat.summary import PathCount, summarize
from tests.support import rec

SMALL = [
    rec(offset=1, method="GET", path="/api/users", status=200, ms=12),
    rec(offset=2, method="POST", path="/api/orders", status=500, ms=340),
    rec(offset=61, method="GET", path="/api/users", status=200, ms=1204),
]


class GroupTest(unittest.TestCase):
    def test_underscore_thousands(self) -> None:
        cases = {0: "0", 999: "999", 1000: "1_000", 1204: "1_204", 1234567: "1_234_567"}
        for value, text in cases.items():
            with self.subTest(value=value):
                self.assertEqual(group(value), text)

    def test_rejects_negative(self) -> None:
        with self.assertRaises(ContractError):
            group(-1)


class FixedTest(unittest.TestCase):
    def test_rounds_half_up(self) -> None:
        cases = [
            (Fraction(1, 4), 1, "0.3"),
            (Fraction(1875, 100), 1, "18.8"),
            (Fraction(3, 16), 3, "0.188"),
            (Fraction(37, 1204), 3, "0.031"),
            (Fraction(0), 1, "0.0"),
            (Fraction(32, 7), 1, "4.6"),
        ]
        for value, places, text in cases:
            with self.subTest(value=value):
                self.assertEqual(fixed(value, places), text)

    def test_groups_the_whole_part(self) -> None:
        self.assertEqual(fixed(Fraction(24690, 20), 1, grouped=True), "1_234.5")

    def test_rejects_negative(self) -> None:
        with self.assertRaises(ContractError):
            fixed(Fraction(-1, 2), 1)

    def test_rejects_zero_places(self) -> None:
        with self.assertRaises(ContractError):
            fixed(Fraction(1, 2), 0)


class TextSectionsTest(unittest.TestCase):
    def test_overview(self) -> None:
        self.assertEqual(
            overview_lines(summarize(SMALL, malformed=2)),
            ["requests     3", "errors       1  (33.3%)", "malformed    2", "per minute 3.0"],
        )

    def test_overview_of_the_spec_example(self) -> None:
        records = [rec(offset=i % 1800, status=500 if i < 37 else 200) for i in range(1204)]
        lines = overview_lines(summarize(records, malformed=2))
        self.assertEqual(lines[:3], ["requests   1_204", "errors        37  (3.1%)", "malformed      2"])

    def test_slowest(self) -> None:
        self.assertEqual(
            slowest_lines(summarize(SMALL).slowest),
            [
                "  1_204 ms  GET  /api/users    2026-09-12T10:01:01Z",
                "    340 ms  POST /api/orders   2026-09-12T10:00:02Z",
                "     12 ms  GET  /api/users    2026-09-12T10:00:01Z",
            ],
        )

    def test_busiest(self) -> None:
        self.assertEqual(
            busiest_lines(summarize(SMALL).busiest), ["  2  GET  /api/users", "  1  POST /api/orders"]
        )

    def test_busiest_groups_large_counts(self) -> None:
        entries = (PathCount(1204, "GET", "/a"), PathCount(9, "DELETE", "/b"))
        self.assertEqual(busiest_lines(entries), ["  1_204  GET    /a", "      9  DELETE /b"])

    def test_empty_report_keeps_every_heading(self) -> None:
        self.assertEqual(
            render_text(summarize([])),
            "requests     0\nerrors       0  (0.0%)\nmalformed    0\nper minute 0.0\n\nslowest\n\nbusiest\n",
        )

    def test_sections_in_order(self) -> None:
        text = render_text(summarize(SMALL))
        self.assertEqual([block.split("\n")[0] for block in text.split("\n\n")], ["requests     3", "slowest", "busiest"])


class JsonTest(unittest.TestCase):
    def test_one_object_with_every_field_in_order(self) -> None:
        text = render_json(summarize(SMALL, top=1, malformed=2))
        self.assertEqual(text.count("\n"), 1)
        document = json.loads(text)
        self.assertEqual(
            list(document), ["requests", "errors", "error_rate", "malformed", "per_minute", "slowest", "busiest"]
        )
        self.assertEqual(
            document,
            {
                "requests": 3,
                "errors": 1,
                "error_rate": 0.333,
                "malformed": 2,
                "per_minute": 3.0,
                "slowest": [{"ms": 1204, "method": "GET", "path": "/api/users", "at": "2026-09-12T10:01:01Z"}],
                "busiest": [{"count": 2, "method": "GET", "path": "/api/users"}],
            },
        )


if __name__ == "__main__":
    unittest.main()
