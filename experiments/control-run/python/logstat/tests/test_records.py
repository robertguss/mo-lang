import unittest
from datetime import UTC, datetime

from logstat.contract import ContractError
from logstat.records import UINT32_MAX, Malformed, Record, parse_line, parse_raw_line


class ParseLineTest(unittest.TestCase):
    def test_a_well_formed_line_yields_a_record(self) -> None:
        record = parse_line("2026-09-12T10:00:02Z POST /api/orders 500 340")
        assert isinstance(record, Record)
        self.assertEqual(record.at, datetime(2026, 9, 12, 10, 0, 2, tzinfo=UTC))
        self.assertEqual(record.at_text, "2026-09-12T10:00:02Z")
        self.assertEqual((record.method, record.path), ("POST", "/api/orders"))
        self.assertEqual((record.status, record.duration_ms), (500, 340))
        self.assertTrue(record.is_error)

    def test_status_bounds_are_inclusive(self) -> None:
        for status in ("100", "599"):
            self.assertIsInstance(parse_line(f"2026-09-12T10:00:02Z GET / {status} 1"), Record)

    def test_rejects_status_below_100(self) -> None:
        self.assertIsInstance(parse_line("2026-09-12T10:00:02Z GET / 099 1"), Malformed)

    def test_rejects_status_above_599(self) -> None:
        self.assertIsInstance(parse_line("2026-09-12T10:00:02Z GET / 600 1"), Malformed)

    def test_duration_fits_uint32(self) -> None:
        record = parse_line(f"2026-09-12T10:00:02Z GET / 200 {UINT32_MAX}")
        assert isinstance(record, Record)
        self.assertEqual(record.duration_ms, UINT32_MAX)

    def test_rejects_duration_past_uint32(self) -> None:
        line = f"2026-09-12T10:00:02Z GET / 200 {UINT32_MAX + 1}"
        self.assertIsInstance(parse_line(line), Malformed)

    def test_rejects_a_negative_or_signed_number(self) -> None:
        for fields in ("200 -1", "+200 1", "200 +1", "2_00 1", "200 1.5"):
            line = f"2026-09-12T10:00:02Z GET / {fields}"
            self.assertIsInstance(parse_line(line), Malformed, fields)

    def test_rejects_wrong_field_counts_and_spacing(self) -> None:
        for line in (
            "2026-09-12T10:00:02Z GET / 200",
            "2026-09-12T10:00:02Z GET / 200 1 extra",
            "2026-09-12T10:00:02Z  GET / 200 1",
            "2026-09-12T10:00:02Z\tGET / 200 1",
            "this line is not a log line",
        ):
            self.assertIsInstance(parse_line(line), Malformed, line)

    def test_rejects_a_timestamp_without_offset_or_not_iso(self) -> None:
        for stamp in ("2026-09-12T10:00:02", "2026-13-12T10:00:02Z", "yesterday", "1757671202"):
            self.assertIsInstance(parse_line(f"{stamp} GET / 200 1"), Malformed, stamp)

    def test_accepts_an_offset_and_keeps_the_instant(self) -> None:
        record = parse_line("2026-09-12T12:00:02+02:00 GET / 200 1")
        assert isinstance(record, Record)
        self.assertEqual(record.at, datetime(2026, 9, 12, 10, 0, 2, tzinfo=UTC))

    def test_rejects_a_bad_method_or_path(self) -> None:
        for method_path in ("get /", "G3T /", "GET api/users"):
            line = f"2026-09-12T10:00:02Z {method_path} 200 1"
            self.assertIsInstance(parse_line(line), Malformed, method_path)

    def test_masks_a_card_number_in_the_path(self) -> None:
        record = parse_line("2026-09-12T10:00:02Z GET /cards/4111111111111111/x 200 1")
        assert isinstance(record, Record)
        self.assertEqual(record.path, "/cards/****************/x")

    def test_masks_a_card_number_hidden_in_fractional_seconds(self) -> None:
        record = parse_line("2026-09-12T10:00:02.4111111111111111Z GET / 200 1")
        assert isinstance(record, Record)
        self.assertNotIn("4111111111111111", record.at_text)

    def test_rejects_a_line_holding_a_newline(self) -> None:
        with self.assertRaisesRegex(ContractError, "requires the line holds no newline"):
            parse_line("2026-09-12T10:00:02Z GET / 200 1\n")


class ParseRawLineTest(unittest.TestCase):
    def test_strips_lf_and_crlf(self) -> None:
        self.assertIsInstance(parse_raw_line(b"2026-09-12T10:00:02Z GET / 200 1\n"), Record)
        self.assertIsInstance(parse_raw_line(b"2026-09-12T10:00:02Z GET / 200 1\r\n"), Record)

    def test_an_empty_line_is_not_counted(self) -> None:
        self.assertIsNone(parse_raw_line(b"\n"))
        self.assertIsNone(parse_raw_line(b"\r\n"))

    def test_invalid_utf8_is_malformed(self) -> None:
        self.assertIsInstance(parse_raw_line(b"2026-09-12T10:00:02Z GET /\xff 200 1\n"), Malformed)

    def test_a_utf8_path_is_accepted(self) -> None:
        raw = "2026-09-12T10:00:02Z GET /café 200 1\n".encode()
        record = parse_raw_line(raw)
        assert isinstance(record, Record)
        self.assertEqual(record.path, "/café")


if __name__ == "__main__":
    unittest.main()
