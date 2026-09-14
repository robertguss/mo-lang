import json
import unittest

from logstat.render import render_json, render_text
from logstat.summary import BusyPath, SlowRequest, Summary

SUMMARY = Summary(
    requests=1204,
    errors=37,
    error_rate=0.031,
    malformed=2,
    per_minute=40.1,
    slowest=[
        SlowRequest(ms=1340, method="POST", path="/api/orders", at="2026-09-12T10:00:02Z"),
        SlowRequest(ms=12, method="GET", path="/", at="2026-09-12T10:00:01Z"),
    ],
    busiest=[
        BusyPath(count=611, method="GET", path="/api/users"),
        BusyPath(count=9, method="DELETE", path="/x"),
    ],
)


class TextTest(unittest.TestCase):
    def test_counts_section(self) -> None:
        head = render_text(SUMMARY).splitlines()[:4]
        self.assertEqual(
            head,
            [
                "requests   1_204",
                "errors        37  (3.1%)",
                "malformed      2",
                "per minute  40.1",
            ],
        )

    def test_slowest_section(self) -> None:
        lines = render_text(SUMMARY).splitlines()
        start = lines.index("slowest")
        self.assertEqual(
            lines[start + 1 : start + 3],
            [
                "  1_340 ms  POST /api/orders   2026-09-12T10:00:02Z",
                "     12 ms  GET /              2026-09-12T10:00:01Z",
            ],
        )

    def test_busiest_section(self) -> None:
        lines = render_text(SUMMARY).splitlines()
        start = lines.index("busiest")
        self.assertEqual(lines[start + 1 :], ["  611  GET /api/users", "    9  DELETE /x"])

    def test_sections_are_separated_by_a_blank_line(self) -> None:
        lines = render_text(SUMMARY).splitlines()
        self.assertEqual(lines[4:6], ["", "slowest"])
        self.assertEqual(lines[lines.index("busiest") - 1], "")

    def test_an_empty_summary_prints_empty_sections(self) -> None:
        empty = Summary(
            requests=0,
            errors=0,
            error_rate=0.0,
            malformed=0,
            per_minute=0.0,
            slowest=[],
            busiest=[],
        )
        self.assertEqual(
            render_text(empty),
            "requests     0\nerrors       0  (0.0%)\nmalformed    0\nper minute 0.0\n"
            "\nslowest\n\nbusiest\n",
        )


class JsonTest(unittest.TestCase):
    def test_one_object_with_the_spec_shape(self) -> None:
        out = render_json(SUMMARY)
        self.assertEqual(out.count("\n"), 1)
        doc = json.loads(out)
        self.assertEqual(
            list(doc),
            ["requests", "errors", "error_rate", "malformed", "per_minute", "slowest", "busiest"],
        )
        self.assertEqual(doc["error_rate"], 0.031)
        self.assertEqual(
            doc["slowest"][0],
            {"ms": 1340, "method": "POST", "path": "/api/orders", "at": "2026-09-12T10:00:02Z"},
        )
        self.assertEqual(doc["busiest"][0], {"count": 611, "method": "GET", "path": "/api/users"})

    def test_round_trips_through_the_model(self) -> None:
        self.assertEqual(Summary.model_validate_json(render_json(SUMMARY)), SUMMARY)


if __name__ == "__main__":
    unittest.main()
