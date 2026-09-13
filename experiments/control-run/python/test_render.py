import json
import unittest
from datetime import datetime, timedelta, timezone

from parse import parse_line
from render import render_json, render_text
from summary import Summary, summarize

LINES = [
    "2026-09-12T10:00:00Z GET /api/users 200 12",
    "2026-09-12T10:00:30Z POST /api/orders 500 1340",
    "2026-09-12T10:01:00Z GET /api/users 200 15",
    "2026-09-12T10:02:00Z GET /api/cards/4111111111111111/charge 404 340",
]


def small() -> Summary:
    return summarize([parse_line(line) for line in LINES], 2, malformed=1)


class TextTest(unittest.TestCase):
    def test_counts_section(self) -> None:
        head = render_text(small()).split("\n\n")[0]
        self.assertEqual(
            head, "requests       4\nerrors         1  (25.0%)\nmalformed      1\nper minute   2.0"
        )

    def test_slowest_section(self) -> None:
        section = render_text(small()).split("\n\n")[1]
        self.assertEqual(
            section,
            "slowest\n"
            "  1_340 ms  POST /api/orders                         2026-09-12T10:00:30Z\n"
            "    340 ms  GET /api/cards/****************/charge   2026-09-12T10:02:00Z",
        )

    def test_busiest_section(self) -> None:
        section = render_text(small()).split("\n\n")[2]
        self.assertEqual(section, "busiest\n  2  GET /api/users\n  1  GET /api/cards/****************/charge\n")

    def test_thousands_separators_widen_the_column(self) -> None:
        base = datetime(2026, 9, 12, tzinfo=timezone.utc)
        records = [parse_line(f"{(base + timedelta(seconds=i // 100)).isoformat()[:19]}Z GET / 503 1") for i in range(12_000)]
        head = render_text(summarize(records, 1)).split("\n\n")[0]
        self.assertEqual(
            head,
            "requests    12_000\nerrors      12_000  (100.0%)\nmalformed        0\nper minute  6_050.4",
        )

    def test_empty_summary_has_empty_lists(self) -> None:
        self.assertEqual(
            render_text(summarize([], 5)),
            "requests       0\nerrors         0  (0.0%)\nmalformed      0\nper minute   0.0\n\nslowest\n\nbusiest\n",
        )


class JsonTest(unittest.TestCase):
    def test_document(self) -> None:
        text = render_json(small())
        self.assertEqual(text.count("\n"), 1)
        self.assertEqual(
            json.loads(text),
            {
                "requests": 4,
                "errors": 1,
                "error_rate": 0.25,
                "malformed": 1,
                "per_minute": 2.0,
                "slowest": [
                    {"ms": 1340, "method": "POST", "path": "/api/orders", "at": "2026-09-12T10:00:30Z"},
                    {"ms": 340, "method": "GET", "path": "/api/cards/****************/charge", "at": "2026-09-12T10:02:00Z"},
                ],
                "busiest": [
                    {"count": 2, "method": "GET", "path": "/api/users"},
                    {"count": 1, "method": "GET", "path": "/api/cards/****************/charge"},
                ],
            },
        )

    def test_key_order_and_rounding(self) -> None:
        records = [parse_line(line) for line in LINES[:3]]
        text = render_json(summarize(records, 5))
        self.assertTrue(text.startswith('{"requests": 3, "errors": 1, "error_rate": 0.333, "malformed": 0, "per_minute": 3.0, '))

    def test_no_card_number_in_any_output(self) -> None:
        for output in (render_text(small()), render_json(small())):
            self.assertNotIn("4111111111111111", output)


if __name__ == "__main__":
    unittest.main()
