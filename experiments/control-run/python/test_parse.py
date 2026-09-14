"""parse.py: accepted shapes, a rejects test for every requires, and card masking."""

from __future__ import annotations

import unittest
from datetime import UTC, datetime

from contracts import ContractViolation
from parse import (
    UINT32_MAX,
    Malformed,
    Record,
    contains_card,
    decode_line,
    mask_cards,
    parse_line,
    parse_raw,
)

GOOD_INSTANT = int(datetime(2026, 9, 12, 10, 0, 1, tzinfo=UTC).timestamp()) * 1_000_000


def line(
    at: str = "2026-09-12T10:00:01Z",
    method: str = "GET",
    path: str = "/api/users",
    status: str = "200",
    ms: str = "12",
) -> str:
    return f"{at} {method} {path} {status} {ms}"


GOOD = line()

MALFORMED = {
    "empty line": "",
    "prose": "this line is not a log line",
    "four fields": "2026-09-12T10:00:01Z GET /api/users 200",
    "six fields": GOOD + " extra",
    "trailing space": GOOD + " ",
    "double space": GOOD.replace(" GET", "  GET"),
    "tab separated": GOOD.replace(" ", "\t"),
    "month 13": line(at="2026-13-12T10:00:01Z"),
    "no zone": line(at="2026-09-12T10:00:01"),
    "lower-case t and z": line(at="2026-09-12t10:00:01z"),
    "second 60": line(at="2026-09-12T10:00:60Z"),
    "offset of 24 hours": line(at="2026-09-12T10:00:01+24:00"),
    "date only": line(at="2026-09-12"),
    "seven fraction digits": line(at="2026-09-12T10:00:01.1234567Z"),
    "other-script digits in timestamp": line(at="٢٠٢٦-09-12T10:00:01Z"),
    "lower-case method": line(method="get"),
    "digit in method": line(method="G3T"),
    "relative path": line(path="api/users"),
    "escape character in path": line(path="/api/\x1b[31m"),
    "status 700": line(status="700"),
    "status 099": line(status="099"),
    "status 600": line(status="600"),
    "two-digit status": line(status="20"),
    "four-digit status": line(status="2000"),
    "status not a number": line(status="abc"),
    "status in other-script digits": line(status="٢٠٠"),
    "duration not a number": line(ms="abc"),
    "negative duration": line(ms="-1"),
    "signed duration": line(ms="+1"),
    "underscored duration": line(ms="1_0"),
    "duration in other-script digits": line(ms="٣"),
    "duration past UInt32": line(ms=str(UINT32_MAX + 1)),
    "duration of 11 digits": line(ms="99999999999"),
}


class ParseLineAccepts(unittest.TestCase):
    def test_the_spec_example_line(self) -> None:
        expected = Record(
            at="2026-09-12T10:00:01Z", instant=GOOD_INSTANT, method="GET", path="/api/users", status=200, duration_ms=12
        )
        self.assertEqual(parse_line(GOOD), expected)

    def test_lf_crlf_and_a_last_line_without_an_ending(self) -> None:
        for raw in (GOOD.encode() + b"\n", GOOD.encode() + b"\r\n", GOOD.encode()):
            with self.subTest(raw=raw):
                self.assertEqual(parse_raw(raw), parse_line(GOOD))

    def test_status_at_both_bounds(self) -> None:
        for status in (100, 599):
            with self.subTest(status=status):
                self.assertEqual(parse_line(line(status=str(status))).status, status)

    def test_duration_at_both_bounds_and_with_leading_zeros(self) -> None:
        for text, expected in (("0", 0), (str(UINT32_MAX), UINT32_MAX), ("0000000000012", 12)):
            with self.subTest(text=text):
                self.assertEqual(parse_line(line(ms=text)).duration_ms, expected)

    def test_offsets_name_the_same_instant_and_keep_the_text(self) -> None:
        for at in ("2026-09-12T12:00:01+02:00", "2026-09-12T09:00:01-01:00"):
            with self.subTest(at=at):
                record = parse_line(line(at=at))
                self.assertEqual((record.instant, record.at), (GOOD_INSTANT, at))

    def test_fractional_seconds(self) -> None:
        self.assertEqual(parse_line(line(at="2026-09-12T10:00:01.5Z")).instant, GOOD_INSTANT + 500_000)

    def test_any_upper_case_method_and_a_non_ascii_path(self) -> None:
        record = parse_line(line(method="PATCH", path="/café/ü"))
        self.assertEqual((record.method, record.path), ("PATCH", "/café/ü"))


class ParseLineRejects(unittest.TestCase):
    def test_every_malformed_shape(self) -> None:
        for name, text in MALFORMED.items():
            with self.subTest(name), self.assertRaises(Malformed):
                parse_line(text)

    def test_bytes_that_are_not_utf8(self) -> None:
        with self.assertRaises(Malformed):
            parse_raw(b"\xff" + GOOD.encode())

    def test_only_one_line_ending_is_stripped(self) -> None:
        self.assertEqual(decode_line(b"x\r\r\n"), "x\r")
        with self.assertRaises(Malformed):
            parse_raw(GOOD.encode() + b"\r\r\n")


def record_with(status: int = 200, duration_ms: int = 12, path: str = "/api/users") -> Record:
    return Record(
        at="2026-09-12T10:00:01Z", instant=GOOD_INSTANT, method="GET", path=path, status=status, duration_ms=duration_ms
    )


class RecordRejects(unittest.TestCase):
    def test_rejects_status_below_100(self) -> None:
        with self.assertRaisesRegex(ContractViolation, "status is 100 to 599"):
            record_with(status=99)

    def test_rejects_status_above_599(self) -> None:
        with self.assertRaisesRegex(ContractViolation, "status is 100 to 599"):
            record_with(status=600)

    def test_rejects_negative_duration(self) -> None:
        with self.assertRaisesRegex(ContractViolation, "duration_ms fits UInt32"):
            record_with(duration_ms=-1)

    def test_rejects_duration_past_uint32(self) -> None:
        with self.assertRaisesRegex(ContractViolation, "duration_ms fits UInt32"):
            record_with(duration_ms=UINT32_MAX + 1)

    def test_rejects_a_path_holding_a_card_number(self) -> None:
        with self.assertRaisesRegex(ContractViolation, "path holds no card number"):
            record_with(path="/cards/4111111111111111")


class CardMasking(unittest.TestCase):
    def test_a_parsed_path_never_holds_the_card(self) -> None:
        record = parse_line(line(path="/api/cards/4111111111111111/charge"))
        self.assertEqual(record.path, "/api/cards/****************/charge")

    def test_masks_runs_of_16_or_more_and_leaves_shorter_runs(self) -> None:
        cases = {
            "/a/4111111111111111": "/a/****************",
            "/a/411111111111111": "/a/411111111111111",
            "/a/4111111111111111234": "/a/*******************",
            "x4111111111111111y/5500000000000004": "x****************y/****************",
        }
        for text, expected in cases.items():
            with self.subTest(text=text):
                self.assertEqual(mask_cards(text), expected)
                self.assertFalse(contains_card(mask_cards(text)))

    def test_contains_card(self) -> None:
        self.assertTrue(contains_card("/4111111111111111"))
        self.assertFalse(contains_card("/4111-1111-1111-111"))


if __name__ == "__main__":
    unittest.main()
