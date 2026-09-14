import calendar
import unittest

from logstat.contracts import ContractError
from logstat.record import (
    UINT32_MAX,
    Malformed,
    Record,
    decode_line,
    mask_card,
    parse_line,
    parse_timestamp,
)

AT = "2026-09-12T10:00:02Z"
EPOCH = calendar.timegm((2026, 9, 12, 10, 0, 2))
GOOD = f"{AT} POST /api/orders 500 340"


def line(at: str = AT, method: str = "POST", path: str = "/p", status: str = "200", ms: str = "1") -> str:
    return f"{at} {method} {path} {status} {ms}"


class ParseTimestampTest(unittest.TestCase):
    def test_epoch_seconds(self) -> None:
        self.assertEqual(parse_timestamp(AT), EPOCH)

    def test_rejects_other_shapes(self) -> None:
        for text in [
            "2026-13-12T10:01:45Z",
            "2026-02-30T10:00:00Z",
            "2026-09-12T24:00:00Z",
            "2026-09-12T23:59:60Z",
            "0000-01-01T00:00:00Z",
            "2026-09-12 10:00:02",
            "2026-09-12T10:00:02",
            "2026-09-12T10:00:02+00:00",
            "2026-09-12T10:00:02.5Z",
            "٢٠٢٦-09-12T10:00:02Z",
            "",
        ]:
            with self.subTest(text=text):
                self.assertIsNone(parse_timestamp(text))


class ParseLineTest(unittest.TestCase):
    def test_parses_a_good_line(self) -> None:
        expected = Record(AT, EPOCH, "POST", "/api/orders", 500, 340)
        self.assertEqual(parse_line(GOOD), expected)

    def test_accepts_the_edges(self) -> None:
        for status, ms in [("100", "0"), ("599", str(UINT32_MAX)), ("200", "0000000012")]:
            with self.subTest(status=status, ms=ms):
                record = parse_line(line(status=status, ms=ms))
                assert isinstance(record, Record)
                self.assertEqual((record.status, record.duration_ms), (int(status), int(ms)))

    def test_malformed_lines(self) -> None:
        for text in [
            "",
            "this line is not a log line",
            GOOD.replace(" ", "  ", 1),
            GOOD.replace(" ", "\t"),
            GOOD + " ",
            line(at="2026-13-12T10:01:45Z"),
            line(method="get"),
            line(method="G3T"),
            line(path="api/users"),
            line(path="/a\x1b[31m"),
            line(status="700"),
            line(status="099"),
            line(status="99"),
            line(status="0200"),
            line(status="+20"),
            line(status="abc"),
            line(status="٢٠٠"),
            line(ms="abc"),
            line(ms="-1"),
            line(ms="+5"),
            line(ms="1_0"),
            line(ms=str(UINT32_MAX + 1)),
            line(ms="99999999999"),
        ]:
            with self.subTest(text=text):
                self.assertIsInstance(parse_line(text), Malformed)

    def test_masks_card_numbers_in_the_path(self) -> None:
        record = parse_line(line(path="/api/cards/4111111111111111/charge"))
        assert isinstance(record, Record)
        self.assertEqual(record.path, "/api/cards/****************/charge")


class DecodeLineTest(unittest.TestCase):
    def test_line_endings_are_not_part_of_the_line(self) -> None:
        for ending in [b"", b"\n", b"\r\n"]:
            with self.subTest(ending=ending):
                self.assertIsInstance(decode_line(GOOD.encode() + ending), Record)

    def test_a_lone_carriage_return_is_malformed(self) -> None:
        self.assertIsInstance(decode_line(GOOD.encode() + b"\r\r\n"), Malformed)

    def test_invalid_utf8_is_malformed(self) -> None:
        self.assertIsInstance(decode_line(GOOD.encode().replace(b"/api", b"/\xff")), Malformed)


class MaskCardTest(unittest.TestCase):
    def test_masks_runs_of_16_or_more_digits(self) -> None:
        cases = {
            "/c/4111111111111111": "/c/****************",
            "/c/41111111111111112": "/c/*****************",
            "/c/411111111111111": "/c/411111111111111",
            "/a/1111222233334444/b/5555666677778888": "/a/****************/b/****************",
            "/orders/17": "/orders/17",
        }
        for path, masked in cases.items():
            with self.subTest(path=path):
                self.assertEqual(mask_card(path), masked)


class RecordContractTest(unittest.TestCase):
    def test_rejects_at_that_is_not_a_timestamp(self) -> None:
        with self.assertRaises(ContractError):
            Record("yesterday", EPOCH, "GET", "/p", 200, 1)

    def test_rejects_epoch_that_disagrees_with_at(self) -> None:
        with self.assertRaises(ContractError):
            Record(AT, EPOCH + 1, "GET", "/p", 200, 1)

    def test_rejects_method_that_is_not_letters(self) -> None:
        with self.assertRaises(ContractError):
            Record(AT, EPOCH, "get", "/p", 200, 1)

    def test_rejects_path_without_slash(self) -> None:
        with self.assertRaises(ContractError):
            Record(AT, EPOCH, "GET", "p", 200, 1)

    def test_rejects_path_with_card_number(self) -> None:
        with self.assertRaises(ContractError):
            Record(AT, EPOCH, "GET", "/c/4111111111111111", 200, 1)

    def test_rejects_status_outside_100_to_599(self) -> None:
        for status in [99, 600]:
            with self.subTest(status=status), self.assertRaises(ContractError):
                Record(AT, EPOCH, "GET", "/p", status, 1)

    def test_rejects_duration_outside_uint32(self) -> None:
        for ms in [-1, UINT32_MAX + 1]:
            with self.subTest(ms=ms), self.assertRaises(ContractError):
                Record(AT, EPOCH, "GET", "/p", 200, ms)


if __name__ == "__main__":
    unittest.main()
