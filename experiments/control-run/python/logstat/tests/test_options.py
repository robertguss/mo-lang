import unittest
from datetime import UTC, datetime

from logstat.options import Options, UsageError, parse_args


class ParseArgsTest(unittest.TestCase):
    def test_defaults(self) -> None:
        self.assertEqual(parse_args(["logs"]), Options(directory="logs"))

    def test_every_option_in_any_order(self) -> None:
        options = parse_args(["--json", "--since", "2026-09-12T10:00:00Z", "logs", "--top", "7"])
        self.assertEqual(options.directory, "logs")
        self.assertEqual(options.top, 7)
        self.assertEqual(options.since, datetime(2026, 9, 12, 10, tzinfo=UTC))
        self.assertTrue(options.json_output)

    def test_top_bounds_are_inclusive(self) -> None:
        self.assertEqual(parse_args(["logs", "--top", "1"]).top, 1)
        self.assertEqual(parse_args(["logs", "--top", "100"]).top, 100)

    def test_rejects_top_below_1(self) -> None:
        with self.assertRaisesRegex(UsageError, "--top must be 1 to 100, got 0"):
            parse_args(["logs", "--top", "0"])

    def test_rejects_top_above_100_rather_than_clamping(self) -> None:
        with self.assertRaisesRegex(UsageError, "--top must be 1 to 100, got 101"):
            parse_args(["logs", "--top", "101"])

    def test_rejects_top_that_is_not_a_whole_number(self) -> None:
        for value in ("-1", "five", "5.0", " 5", "+5", "5_0"):
            with self.assertRaises(UsageError, msg=value):
                parse_args(["logs", "--top", value])

    def test_rejects_a_missing_value(self) -> None:
        for argv in (["logs", "--top"], ["logs", "--since"]):
            with self.assertRaises(UsageError, msg=str(argv)):
                parse_args(argv)

    def test_rejects_since_without_offset_or_not_iso(self) -> None:
        for value in ("2026-09-12T10:00:00", "soon"):
            with self.assertRaises(UsageError, msg=value):
                parse_args(["logs", "--since", value])

    def test_rejects_zero_or_two_directories(self) -> None:
        for argv in ([], ["a", "b"], ["--json"]):
            with self.assertRaises(UsageError, msg=str(argv)):
                parse_args(argv)

    def test_rejects_unknown_and_repeated_options(self) -> None:
        for argv in (["logs", "--verbose"], ["logs", "--json", "--json"], ["logs", "--top=5"]):
            with self.assertRaises(UsageError, msg=str(argv)):
                parse_args(argv)

    def test_a_usage_error_is_one_line(self) -> None:
        with self.assertRaises(UsageError) as caught:
            parse_args(["logs", "--top", "0"])
        self.assertNotIn("\n", str(caught.exception))
        self.assertIn("usage: logstat <dir>", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
