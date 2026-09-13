from __future__ import annotations

import unittest
from datetime import datetime, timezone

from records import (
    UINT32_MAX,
    ContractError,
    Malformed,
    Record,
    mask_cards,
    parse_line,
    parse_raw_line,
    parse_timestamp,
)

AT = datetime(2026, 9, 12, 10, 0, 1, tzinfo=timezone.utc)


def line(status: str = "200", duration: str = "12", path: str = "/api/users") -> str:
    return f"2026-09-12T10:00:01Z GET {path} {status} {duration}"


class ParseLineTest(unittest.TestCase):
    def test_parses_a_good_line(self) -> None:
        parsed = parse_line(line())
        self.assertEqual(parsed, Record(AT, "2026-09-12T10:00:01Z", "GET", "/api/users", 200, 12))

    def test_bounds_are_accepted(self) -> None:
        for status in ("100", "599"):
            self.assertIsInstance(parse_line(line(status=status)), Record)
        for duration in ("0", str(UINT32_MAX)):
            self.assertIsInstance(parse_line(line(duration=duration)), Record)

    def test_rejects_status_outside_100_to_599(self) -> None:
        for status in ("99", "600", "700", "0", "-200", "+200", "2O0", ""):
            self.assertIsInstance(parse_line(line(status=status)), Malformed, status)

    def test_rejects_duration_that_does_not_fit_uint32(self) -> None:
        huge = "9" * 5000
        for duration in (str(UINT32_MAX + 1), "-1", "abc", "1e3", "1_0", "١٢", huge, ""):
            self.assertIsInstance(parse_line(line(duration=duration)), Malformed, duration[:12])

    def test_rejects_wrong_field_count_and_spacing(self) -> None:
        for text in ("", "this line is not a log line", line() + " extra", line().replace(" ", "  ", 1)):
            self.assertIsInstance(parse_line(text), Malformed, text)

    def test_rejects_bad_timestamp_method_and_path(self) -> None:
        bad = (
            "2026-13-12T10:00:01Z GET /a 200 1",
            "2026-09-12T10:00:01 GET /a 200 1",
            "2026-09-12 GET /a 200 1",
            "2026-09-12T10:00:01Z get /a 200 1",
            "2026-09-12T10:00:01Z GET api 200 1",
            "2026-09-12T10:00:01Z GET /a\x07 200 1",
        )
        for text in bad:
            self.assertIsInstance(parse_line(text), Malformed, text)

    def test_masks_card_numbers_in_the_path(self) -> None:
        parsed = parse_line(line(path="/api/cards/4111111111111111/charge"))
        assert isinstance(parsed, Record)
        self.assertEqual(parsed.path, "/api/cards/****************/charge")


class RawLineTest(unittest.TestCase):
    def test_strips_lf_and_crlf(self) -> None:
        for ending in (b"\n", b"\r\n", b""):
            self.assertIsInstance(parse_raw_line(line().encode() + ending), Record)

    def test_invalid_utf8_is_malformed(self) -> None:
        self.assertEqual(parse_raw_line(b"2026-09-12T10:00:01Z GET /\xff 200 1\n"), Malformed("not UTF-8"))


class RecordContractTest(unittest.TestCase):
    def test_rejects_status_outside_range(self) -> None:
        for status in (99, 600):
            with self.assertRaises(ContractError):
                Record(AT, "t", "GET", "/", status, 1)

    def test_rejects_duration_outside_uint32(self) -> None:
        for duration in (-1, UINT32_MAX + 1):
            with self.assertRaises(ContractError):
                Record(AT, "t", "GET", "/", 200, duration)

    def test_rejects_naive_timestamp(self) -> None:
        with self.assertRaises(ContractError):
            Record(datetime(2026, 9, 12), "t", "GET", "/", 200, 1)

    def test_rejects_unmasked_card_in_path(self) -> None:
        with self.assertRaises(ContractError):
            Record(AT, "t", "GET", "/4111111111111111", 200, 1)


class HelpersTest(unittest.TestCase):
    def test_mask_leaves_short_digit_runs(self) -> None:
        self.assertEqual(mask_cards("/orders/123456789012345"), "/orders/123456789012345")
        self.assertEqual(mask_cards("/x/41111111111111112"), "/x/*****************")

    def test_timestamp_offsets_and_fractions(self) -> None:
        self.assertEqual(parse_timestamp("2026-09-12T12:00:01+02:00"), AT)
        self.assertIsNotNone(parse_timestamp("2026-09-12T10:00:01.250Z"))
        self.assertIsNone(parse_timestamp("2026-09-12T25:00:01Z"))


if __name__ == "__main__":
    unittest.main()
