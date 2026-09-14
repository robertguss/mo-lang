import json
import unittest

from logstat.contract import ContractError
from logstat.render import render_json, render_text
from logstat.summary import BusyEntry, SlowEntry, Summary


def small_summary() -> Summary:
    return Summary(
        requests=1204,
        errors=37,
        error_rate=0.031,
        malformed=2,
        per_minute=40.1,
        slowest=[
            SlowEntry(ms=1340, method="POST", path="/api/orders", at="2026-09-12T10:00:02Z"),
            SlowEntry(ms=12, method="GET", path="/api/users", at="2026-09-12T10:00:01Z"),
        ],
        busiest=[
            BusyEntry(count=611, method="GET", path="/api/users"),
            BusyEntry(count=9, method="POST", path="/api/orders"),
        ],
    )


class TextTest(unittest.TestCase):
    def test_totals_section(self) -> None:
        lines = render_text(small_summary()).splitlines()
        self.assertEqual(
            lines[:4],
            [
                "requests   1_204",
                "errors        37  (3.1%)",
                "malformed      2",
                "per minute  40.1",
            ],
        )

    def test_slowest_section(self) -> None:
        text = render_text(small_summary())
        self.assertIn(
            "\nslowest\n"
            "  1_340 ms  POST /api/orders   2026-09-12T10:00:02Z\n"
            "     12 ms  GET /api/users     2026-09-12T10:00:01Z\n\n",
            text,
        )

    def test_busiest_section(self) -> None:
        text = render_text(small_summary())
        self.assertTrue(
            text.endswith("\nbusiest\n  611  GET /api/users\n    9  POST /api/orders\n")
        )

    def test_empty_summary_keeps_the_headers(self) -> None:
        empty = Summary(
            requests=0,
            errors=0,
            error_rate=0.0,
            malformed=3,
            per_minute=0.0,
            slowest=[],
            busiest=[],
        )
        self.assertEqual(
            render_text(empty),
            "requests     0\nerrors       0  (0.0%)\nmalformed    3\nper minute 0.0\n"
            "\nslowest\n\nbusiest\n",
        )

    def test_large_numbers_use_underscores(self) -> None:
        summary = small_summary().model_copy(update={"requests": 12_345_678, "per_minute": 1234.5})
        text = render_text(summary)
        self.assertIn("requests   12_345_678\n", text)
        self.assertIn("per minute    1_234.5\n", text)


class JsonTest(unittest.TestCase):
    def test_one_object_on_one_line_with_the_spec_keys_in_order(self) -> None:
        output = render_json(small_summary())
        self.assertEqual(output.count("\n"), 1)
        data = json.loads(output)
        self.assertEqual(
            list(data),
            ["requests", "errors", "error_rate", "malformed", "per_minute", "slowest", "busiest"],
        )
        self.assertEqual(data["error_rate"], 0.031)
        self.assertEqual(
            data["slowest"][0],
            {"ms": 1340, "method": "POST", "path": "/api/orders", "at": "2026-09-12T10:00:02Z"},
        )
        self.assertEqual(data["busiest"][0], {"count": 611, "method": "GET", "path": "/api/users"})


class CardNumberNeverTest(unittest.TestCase):
    def test_ensures_no_card_number_reaches_text_output(self) -> None:
        leaky = small_summary().model_copy(
            update={"busiest": [BusyEntry(count=1, method="GET", path="/c/4111111111111111")]}
        )
        with self.assertRaises(ContractError):
            render_text(leaky)

    def test_ensures_no_card_number_reaches_json_output(self) -> None:
        leaky = small_summary().model_copy(
            update={"slowest": [SlowEntry(ms=1, method="GET", path="/5500000000000004", at="x")]}
        )
        with self.assertRaises(ContractError):
            render_json(leaky)


if __name__ == "__main__":
    unittest.main()
