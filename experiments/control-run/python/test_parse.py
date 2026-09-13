import unittest
from datetime import datetime, timezone

from parse import UINT32_MAX, MalformedLine, Record, decode_line, parse_line, parse_timestamp

AT = datetime(2026, 9, 12, 10, 0, 1, tzinfo=timezone.utc)


class ParseLineTest(unittest.TestCase):
    def test_parses_a_line(self) -> None:
        record = parse_line("2026-09-12T10:00:01Z GET /api/users 200 12")
        self.assertEqual(record, Record(AT, "GET", "/api/users", 200, 12))
        self.assertEqual(record.at_text, "2026-09-12T10:00:01Z")

    def test_masks_card_number_in_path(self) -> None:
        record = parse_line("2026-09-12T10:00:01Z GET /api/cards/4111111111111111/charge 200 12")
        self.assertEqual(record.path, "/api/cards/****************/charge")

    def test_status_bounds_are_inclusive(self) -> None:
        self.assertEqual(parse_line("2026-09-12T10:00:01Z GET / 100 0").status, 100)
        self.assertEqual(parse_line("2026-09-12T10:00:01Z GET / 599 0").status, 599)

    def test_duration_fits_uint32(self) -> None:
        self.assertEqual(parse_line(f"2026-09-12T10:00:01Z GET / 200 {UINT32_MAX}").duration_ms, UINT32_MAX)

    def test_errors_are_500_to_599(self) -> None:
        self.assertFalse(parse_line("2026-09-12T10:00:01Z GET / 499 1").is_error)
        self.assertTrue(parse_line("2026-09-12T10:00:01Z GET / 500 1").is_error)
        self.assertTrue(parse_line("2026-09-12T10:00:01Z GET / 599 1").is_error)

    def test_rejects_malformed_lines(self) -> None:
        cases = {
            "blank": "",
            "too few fields": "2026-09-12T10:00:01Z GET /api/users 200",
            "too many fields": "this line is not a log line at all",
            "double space": "2026-09-12T10:00:01Z  GET /api/users 200 12",
            "tab separated": "2026-09-12T10:00:01Z\tGET /api/users 200 12",
            "lowercase method": "2026-09-12T10:00:01Z get /api/users 200 12",
            "path without slash": "2026-09-12T10:00:01Z GET api/users 200 12",
            "bad month": "2026-13-12T10:00:01Z GET /api/users 200 12",
            "no zone": "2026-09-12T10:00:01 GET /api/users 200 12",
            "status too high": "2026-09-12T10:00:25Z GET /api/users 700 10",
            "status too low": "2026-09-12T10:00:25Z GET /api/users 99 10",
            "status not a number": "2026-09-12T10:00:25Z GET /api/users OK 10",
            "duration not a number": "2026-09-12T10:03:01Z PUT /api/users/7 200 abc",
            "duration over UInt32": f"2026-09-12T10:03:01Z PUT /api/users/7 200 {UINT32_MAX + 1}",
            "duration negative": "2026-09-12T10:03:01Z PUT /api/users/7 200 -1",
            "duration with underscore": "2026-09-12T10:03:01Z PUT /api/users/7 200 1_000",
            "duration with plus": "2026-09-12T10:03:01Z PUT /api/users/7 200 +5",
            "non-ASCII digits": "2026-09-12T10:03:01Z PUT /api/users/7 200 ١٢",
        }
        for name, line in cases.items():
            with self.subTest(name), self.assertRaises(MalformedLine):
                parse_line(line)


class ParseTimestampTest(unittest.TestCase):
    def test_parses_utc(self) -> None:
        self.assertEqual(parse_timestamp("2026-09-12T10:00:01Z"), AT)

    def test_rejects_other_shapes_and_impossible_dates(self) -> None:
        for text in ["2026-09-12", "2026-09-12T10:00:01+00:00", "2026-02-30T10:00:00Z", "2026-09-12T24:00:00Z", ""]:
            with self.subTest(text), self.assertRaises(MalformedLine):
                parse_timestamp(text)


class RecordContractTest(unittest.TestCase):
    def test_rejects_status_outside_100_to_599(self) -> None:
        for status in (99, 600):
            with self.subTest(status), self.assertRaises(ValueError):
                Record(AT, "GET", "/", status, 1)

    def test_rejects_duration_outside_uint32(self) -> None:
        for duration in (-1, UINT32_MAX + 1):
            with self.subTest(duration), self.assertRaises(ValueError):
                Record(AT, "GET", "/", 200, duration)

    def test_rejects_naive_timestamp(self) -> None:
        with self.assertRaises(ValueError):
            Record(datetime(2026, 9, 12), "GET", "/", 200, 1)

    def test_rejects_bad_method(self) -> None:
        with self.assertRaises(ValueError):
            Record(AT, "get", "/", 200, 1)

    def test_rejects_unmasked_card_number_or_relative_path(self) -> None:
        for path in ("/cards/4111111111111111", "cards"):
            with self.subTest(path), self.assertRaises(ValueError):
                Record(AT, "GET", path, 200, 1)


class DecodeLineTest(unittest.TestCase):
    def test_strips_lf_and_crlf(self) -> None:
        self.assertEqual(decode_line(b"abc\n"), "abc")
        self.assertEqual(decode_line(b"abc\r\n"), "abc")
        self.assertEqual(decode_line(b"abc"), "abc")

    def test_rejects_invalid_utf8(self) -> None:
        with self.assertRaises(MalformedLine):
            decode_line(b"2026-09-12T10:00:01Z GET /\xff 200 1\n")


if __name__ == "__main__":
    unittest.main()
