import unittest
from datetime import UTC, datetime

from logstat.files import decode_line
from logstat.record import (
    LogRecord,
    Malformed,
    format_timestamp,
    mask_cards,
    parse_line,
    parse_timestamp,
)


def parsed(line: str) -> LogRecord:
    result = parse_line(line)
    if not isinstance(result, LogRecord):
        raise AssertionError(f"expected a record, got {result}")
    return result


class ParseLineTest(unittest.TestCase):
    def test_a_well_formed_line_yields_a_record(self) -> None:
        record = parsed("2026-09-12T10:00:02Z POST /api/orders 500 340")
        self.assertEqual(record.at, datetime(2026, 9, 12, 10, 0, 2, tzinfo=UTC))
        self.assertEqual((record.method, record.path), ("POST", "/api/orders"))
        self.assertEqual((record.status, record.duration_ms), (500, 340))
        self.assertTrue(record.is_error)

    def test_status_bounds_are_inclusive(self) -> None:
        self.assertEqual(parsed("2026-09-12T10:00:02Z GET / 100 1").status, 100)
        self.assertEqual(parsed("2026-09-12T10:00:02Z GET / 599 1").status, 599)
        self.assertFalse(parsed("2026-09-12T10:00:02Z GET / 499 1").is_error)

    def test_duration_fits_uint32(self) -> None:
        self.assertEqual(parsed("2026-09-12T10:00:02Z GET / 200 0").duration_ms, 0)
        record = parsed("2026-09-12T10:00:02Z GET / 200 4294967295")
        self.assertEqual(record.duration_ms, 4_294_967_295)

    def test_a_zone_offset_is_read_as_utc(self) -> None:
        record = parsed("2026-09-12T12:00:01+02:00 GET / 200 1")
        self.assertEqual(format_timestamp(record.at), "2026-09-12T10:00:01Z")


class RejectsTest(unittest.TestCase):
    """A `rejects` test for every requirement a record makes of its line."""

    def assert_malformed(self, line: str) -> None:
        self.assertIsInstance(parse_line(line), Malformed, line)

    def test_rejects_status_below_100(self) -> None:
        self.assert_malformed("2026-09-12T10:00:01Z GET / 099 1")

    def test_rejects_status_above_599(self) -> None:
        self.assert_malformed("2026-09-12T10:00:01Z GET / 600 1")
        self.assert_malformed("2026-09-12T10:00:01Z GET / 700 1")

    def test_rejects_status_that_is_not_digits(self) -> None:
        self.assert_malformed("2026-09-12T10:00:01Z GET / 2x0 1")
        self.assert_malformed("2026-09-12T10:00:01Z GET / 2000 1")

    def test_rejects_duration_past_uint32(self) -> None:
        self.assert_malformed("2026-09-12T10:00:01Z GET / 200 4294967296")
        self.assert_malformed("2026-09-12T10:00:01Z GET / 200 99999999999")

    def test_rejects_duration_that_is_not_an_unsigned_integer(self) -> None:
        self.assert_malformed("2026-09-12T10:00:01Z GET / 200 abc")
        self.assert_malformed("2026-09-12T10:00:01Z GET / 200 -1")
        self.assert_malformed("2026-09-12T10:00:01Z GET / 200 1.5")

    def test_rejects_a_timestamp_that_is_not_iso_8601(self) -> None:
        self.assert_malformed("2026-13-12T10:01:45Z GET / 200 7")
        self.assert_malformed("yesterday GET / 200 7")

    def test_rejects_a_timestamp_without_a_zone(self) -> None:
        self.assert_malformed("2026-09-12T10:01:45 GET / 200 7")

    def test_rejects_a_timestamp_that_overflows_into_utc(self) -> None:
        self.assert_malformed("0001-01-01T00:00:00+01:00 GET / 200 7")

    def test_rejects_a_method_that_is_not_uppercase_letters(self) -> None:
        self.assert_malformed("2026-09-12T10:00:01Z get / 200 1")
        self.assert_malformed("2026-09-12T10:00:01Z GE7 / 200 1")

    def test_rejects_a_path_without_a_leading_slash(self) -> None:
        self.assert_malformed("2026-09-12T10:00:01Z GET api 200 1")
        self.assert_malformed("2026-09-12T10:00:01Z GET /a\tb 200 1")

    def test_rejects_the_wrong_number_of_fields(self) -> None:
        self.assert_malformed("")
        self.assert_malformed("this line is not a log line")
        self.assert_malformed("2026-09-12T10:00:01Z GET / 200")
        self.assert_malformed("2026-09-12T10:00:01Z GET / 200 1 extra")
        self.assert_malformed("2026-09-12T10:00:01Z GET  / 200 1")

    def test_a_malformed_reason_never_quotes_a_card_number(self) -> None:
        result = parse_line("4111111111111111 GET / 200 1")
        assert isinstance(result, Malformed)
        self.assertNotIn("4111111111111111", result.reason)


class CardNumberTest(unittest.TestCase):
    def test_sixteen_digits_are_masked(self) -> None:
        self.assertEqual(
            mask_cards("/api/cards/4111111111111111/charge"),
            "/api/cards/****************/charge",
        )

    def test_a_longer_run_is_masked_whole(self) -> None:
        self.assertEqual(mask_cards("/x/12345678901234567"), "/x/" + "*" * 17)

    def test_fifteen_digits_are_left(self) -> None:
        self.assertEqual(mask_cards("/orders/123456789012345"), "/orders/123456789012345")

    def test_a_parsed_record_holds_the_masked_path(self) -> None:
        record = parsed("2026-09-12T10:00:09Z GET /api/cards/4111111111111111/charge 200 88")
        self.assertEqual(record.path, "/api/cards/****************/charge")


class TimestampTest(unittest.TestCase):
    def test_parse_requires_a_zone(self) -> None:
        self.assertIsNone(parse_timestamp("2026-09-12T10:00:00"))
        self.assertEqual(
            parse_timestamp("2026-09-12T10:00:00Z"), datetime(2026, 9, 12, 10, tzinfo=UTC)
        )

    def test_format_is_utc_with_microseconds_only_when_present(self) -> None:
        at = datetime(2026, 9, 12, 10, 0, 0, 1500, tzinfo=UTC)
        self.assertEqual(format_timestamp(at), "2026-09-12T10:00:00.001500Z")
        self.assertEqual(format_timestamp(at.replace(microsecond=0)), "2026-09-12T10:00:00Z")

    def test_a_long_fraction_is_never_echoed(self) -> None:
        at = parse_timestamp("2026-09-12T10:00:01.1234567890123456Z")
        assert at is not None
        self.assertEqual(format_timestamp(at), "2026-09-12T10:00:01.123456Z")


class DecodeLineTest(unittest.TestCase):
    def test_strips_lf_and_crlf(self) -> None:
        self.assertEqual(decode_line(b"a b\n"), "a b")
        self.assertEqual(decode_line(b"a b\r\n"), "a b")
        self.assertEqual(decode_line(b"a b"), "a b")

    def test_invalid_utf8_is_none(self) -> None:
        self.assertIsNone(decode_line(b"\xff\xfe\n"))


if __name__ == "__main__":
    unittest.main()
