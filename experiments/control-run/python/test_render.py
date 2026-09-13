from __future__ import annotations

import json
import unittest

from records import ContractError, parse_line
from render import ensure_no_card, render_json, render_text
from tally import Summary, summarize

SMALL_FIXTURE = """\
2026-09-12T10:00:00Z GET /api/users 200 12
2026-09-12T10:00:30Z POST /api/orders 500 1340
not a line
2026-09-12T10:01:00Z GET /api/cards/4111111111111111/charge 200 340
2026-09-12T10:01:30Z GET /api/users 404 340
2026-09-12T10:02:00Z GET /api/users 200 9
""".splitlines()


def small_summary(top: int = 5) -> Summary:
    return summarize((parse_line(line) for line in SMALL_FIXTURE), top)


class TextTest(unittest.TestCase):
    def section(self, name: str) -> list[str]:
        blocks = render_text(small_summary()).rstrip("\n").split("\n\n")
        return next(block.splitlines() for block in blocks if block.startswith(name))

    def test_counts_section(self) -> None:
        self.assertEqual(
            self.section("requests"),
            ["requests       5", "errors         1  (20.0%)", "malformed      1", "per minute    2.5"],
        )

    def test_slowest_section(self) -> None:
        self.assertEqual(
            self.section("slowest"),
            [
                "slowest",
                "  1_340 ms  POST /api/orders                        2026-09-12T10:00:30Z",
                "    340 ms  GET /api/cards/****************/charge   2026-09-12T10:01:00Z",
                "    340 ms  GET /api/users                          2026-09-12T10:01:30Z",
                "     12 ms  GET /api/users                          2026-09-12T10:00:00Z",
                "      9 ms  GET /api/users                          2026-09-12T10:02:00Z",
            ],
        )

    def test_busiest_section(self) -> None:
        self.assertEqual(
            self.section("busiest"),
            ["busiest", "  3  GET /api/users", "  1  GET /api/cards/****************/charge", "  1  POST /api/orders"],
        )

    def test_thousands_separator_and_top(self) -> None:
        summary = Summary(1_204, 37, 1_167, 2, 40.1, (), ())
        text = render_text(summary)
        self.assertTrue(text.startswith("requests   1_204\nerrors        37  (3.1%)\nmalformed      2\nper minute   40.1\n"))
        self.assertEqual(len(small_summary(top=1).slowest), 1)

    def test_empty_summary_prints_empty_sections(self) -> None:
        text = render_text(summarize([], 5))
        self.assertEqual(text, "requests       0\nerrors         0  (0.0%)\nmalformed      0\nper minute    0.0\n\nslowest\n\nbusiest\n")


class JsonTest(unittest.TestCase):
    def test_counts(self) -> None:
        document = json.loads(render_json(small_summary()))
        self.assertEqual(
            {k: document[k] for k in ("requests", "errors", "error_rate", "malformed", "per_minute")},
            {"requests": 5, "errors": 1, "error_rate": 0.2, "malformed": 1, "per_minute": 2.5},
        )

    def test_slowest(self) -> None:
        first = json.loads(render_json(small_summary()))["slowest"][0]
        self.assertEqual(first, {"ms": 1340, "method": "POST", "path": "/api/orders", "at": "2026-09-12T10:00:30Z"})

    def test_busiest(self) -> None:
        busiest = json.loads(render_json(small_summary()))["busiest"]
        self.assertEqual(busiest[0], {"count": 3, "method": "GET", "path": "/api/users"})
        self.assertEqual(busiest[1]["path"], "/api/cards/****************/charge")

    def test_is_one_line_in_key_order(self) -> None:
        text = render_json(small_summary())
        self.assertEqual(text.count("\n"), 1)
        self.assertTrue(text.startswith('{"requests": 5, "errors": 1, "error_rate": 0.2, "malformed": 1, "per_minute": 2.5, "slowest": ['))


class NoCardTest(unittest.TestCase):
    def test_rendered_output_passes(self) -> None:
        summary = small_summary()
        for output in (render_text(summary), render_json(summary)):
            self.assertEqual(ensure_no_card(output), output)
            self.assertNotIn("4111111111111111", output)

    def test_rejects_output_with_card_number(self) -> None:
        with self.assertRaises(ContractError):
            ensure_no_card("GET /api/cards/4111111111111111/charge")


if __name__ == "__main__":
    unittest.main()
