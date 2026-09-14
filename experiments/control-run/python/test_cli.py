"""logstat.py: arguments, exit codes, the directory rules, --since, and the program over the fixture."""

from __future__ import annotations

import io
import json
import os
import re
import tempfile
import unittest
from datetime import UTC, datetime
from pathlib import Path

from contracts import ContractViolation
from logstat import (
    EXIT_FAILURE,
    EXIT_OK,
    EXIT_USAGE,
    Options,
    ReadFailure,
    UsageError,
    list_logs,
    main,
    open_log,
    parse_args,
    tally_lines,
)
from stats import Tally

HERE = Path(__file__).resolve().parent
FIXTURE = HERE / "fixture"
CARD_RUN = re.compile(r"[0-9]{16}")


def run_main(*argv: str) -> tuple[int, str, str]:
    stdout, stderr = io.BytesIO(), io.BytesIO()
    code = main(list(argv), stdout, stderr)
    return code, stdout.getvalue().decode("utf-8"), stderr.getvalue().decode("utf-8")


def instant(text: str) -> int:
    return int(datetime.fromisoformat(text).astimezone(UTC).timestamp()) * 1_000_000


class ParseArgs(unittest.TestCase):
    def test_defaults(self) -> None:
        self.assertEqual(parse_args(["logs"]), Options(directory="logs", top=5, since=None, json=False))

    def test_every_option_in_any_order(self) -> None:
        argv = ["--json", "--since", "2026-09-12T10:00:00Z", "logs", "--top", "7"]
        self.assertEqual(parse_args(argv), Options("logs", 7, instant("2026-09-12T10:00:00+00:00"), True))

    def test_top_at_both_bounds_and_with_leading_zeros(self) -> None:
        for text, expected in (("1", 1), ("100", 100), ("007", 7)):
            with self.subTest(text=text):
                self.assertEqual(parse_args(["logs", "--top", text]).top, expected)

    def test_rejects_every_bad_command_line(self) -> None:
        cases = {
            "no dir": [],
            "two dirs": ["a", "b"],
            "top without a value": ["logs", "--top"],
            "top 0 is not clamped": ["logs", "--top", "0"],
            "top 101 is not clamped": ["logs", "--top", "101"],
            "top 0101": ["logs", "--top", "0101"],
            "top not a number": ["logs", "--top", "abc"],
            "signed top": ["logs", "--top", "+5"],
            "fractional top": ["logs", "--top", "5.0"],
            "underscored top": ["logs", "--top", "1_0"],
            "since not a timestamp": ["logs", "--since", "yesterday"],
            "since without a zone": ["logs", "--since", "2026-09-12T10:00:00"],
            "json twice": ["logs", "--json", "--json"],
            "top twice": ["logs", "--top", "5", "--top", "6"],
            "unknown option": ["logs", "--verbose"],
            "short option": ["-h"],
        }
        for name, argv in cases.items():
            with self.subTest(name), self.assertRaises(UsageError):
                parse_args(argv)


class OverTheFixture(unittest.TestCase):
    def test_text_report(self) -> None:
        code, out, err = run_main(str(FIXTURE))
        self.assertEqual((code, err), (EXIT_OK, ""))
        self.assertEqual(out, (HERE / "expected.txt").read_text(encoding="utf-8"))

    def test_json_report(self) -> None:
        code, out, err = run_main(str(FIXTURE), "--json")
        self.assertEqual((code, err), (EXIT_OK, ""))
        self.assertEqual(out, (HERE / "expected.json").read_text(encoding="utf-8"))

    def test_no_card_number_reaches_stdout(self) -> None:
        for flags in ([], ["--json"], ["--top", "100"]):
            with self.subTest(flags=flags):
                _, out, _ = run_main(str(FIXTURE), *flags)
                self.assertIsNone(CARD_RUN.search(out))
                self.assertIn("****************", out)

    def test_since_skips_earlier_lines_but_malformed_lines_still_count(self) -> None:
        _, out, _ = run_main(str(FIXTURE), "--since", "2026-09-12T10:01:00Z", "--json")
        parsed = json.loads(out)
        self.assertEqual((parsed["requests"], parsed["errors"], parsed["malformed"]), (5, 1, 5))
        self.assertEqual(parsed["per_minute"], round(5 / 2.5, 1))

    def test_top_one(self) -> None:
        _, out, _ = run_main(str(FIXTURE), "--top", "1", "--json")
        parsed = json.loads(out)
        self.assertEqual([entry["ms"] for entry in parsed["slowest"]], [1204])
        self.assertEqual([entry["count"] for entry in parsed["busiest"]], [7])


class WithTempDir(unittest.TestCase):
    def setUp(self) -> None:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.logs = self.root / "logs"
        self.logs.mkdir()
        self.outside = self.root / "outside.log"
        self.outside.write_bytes(b"2026-09-12T10:00:01Z GET /secret 200 12\n")

    def assert_one_line(self, err: str) -> None:
        self.assertTrue(err.endswith("\n") and err.count("\n") == 1, err)


class ExitCodes(WithTempDir):
    def test_usage_errors_exit_2_with_one_line(self) -> None:
        cases = {
            "top 0": [str(FIXTURE), "--top", "0"],
            "missing dir": [str(self.root / "missing")],
            "a file, not a dir": [str(FIXTURE / "a.log")],
            "no arguments": [],
        }
        for name, argv in cases.items():
            with self.subTest(name):
                code, out, err = run_main(*argv)
                self.assertEqual((code, out), (EXIT_USAGE, ""))
                self.assert_one_line(err)
                self.assertIn("usage: logstat <dir>", err)

    def test_no_log_file_exits_1_with_one_line(self) -> None:
        code, out, err = run_main(str(self.logs))
        self.assertEqual((code, out), (EXIT_FAILURE, ""))
        self.assert_one_line(err)

    def test_only_non_log_hidden_directory_and_symlinked_entries_is_no_log_file(self) -> None:
        (self.logs / "notes.txt").write_bytes(b"x\n")
        (self.logs / ".hidden.log").write_bytes(b"x\n")
        (self.logs / "sub.log").mkdir()
        (self.logs / "link.log").symlink_to(self.outside)
        code, out, _ = run_main(str(self.logs))
        self.assertEqual((code, out), (EXIT_FAILURE, ""))

    def test_a_card_number_in_the_dir_name_is_masked_in_the_message(self) -> None:
        card_dir = self.root / "4111111111111111"
        card_dir.mkdir()
        _, _, err = run_main(str(card_dir))
        self.assertIsNone(CARD_RUN.search(err))

    @unittest.skipIf(os.geteuid() == 0, "root reads any file")
    def test_an_unreadable_log_exits_1_with_one_line(self) -> None:
        unreadable = self.logs / "a.log"
        unreadable.write_bytes(b"x\n")
        unreadable.chmod(0)
        self.addCleanup(unreadable.chmod, 0o600)
        code, out, err = run_main(str(self.logs))
        self.assertEqual((code, out), (EXIT_FAILURE, ""))
        self.assert_one_line(err)

    def test_output_is_utf8(self) -> None:
        (self.logs / "a.log").write_bytes("2026-09-12T10:00:01Z GET /café 200 12\n".encode())
        code, out, _ = run_main(str(self.logs))
        self.assertEqual(code, EXIT_OK)
        self.assertIn("GET /café", out)


class DirectoryRules(WithTempDir):
    def test_lists_regular_log_files_in_code_point_order(self) -> None:
        for name in ("b.log", "a.log", "A.log", "c.txt", ".h.log", "b.log.bak"):
            (self.logs / name).write_bytes(b"")
        (self.logs / "d.log").mkdir()
        (self.logs / "link.log").symlink_to(self.outside)
        self.assertEqual(list_logs(str(self.logs)), ["A.log", "a.log", "b.log"])

    def test_open_rejects_a_name_that_is_not_a_direct_child(self) -> None:
        for name in ("../outside.log", "sub/x.log", "", ".", ".."):
            with self.subTest(name=name), self.assertRaisesRegex(ContractViolation, "direct child"):
                open_log(str(self.logs), name)

    def test_open_refuses_a_symlink_resolving_outside(self) -> None:
        (self.logs / "link.log").symlink_to(self.outside)
        with self.assertRaisesRegex(ReadFailure, "resolves outside"):
            open_log(str(self.logs), "link.log")

    def test_open_refuses_a_symlink_even_inside(self) -> None:
        (self.logs / "real.log").write_bytes(b"")
        (self.logs / "link.log").symlink_to(self.logs / "real.log")
        with self.assertRaisesRegex(ReadFailure, "cannot open"):
            open_log(str(self.logs), "link.log")

    def test_open_refuses_a_directory(self) -> None:
        (self.logs / "d.log").mkdir()
        with self.assertRaisesRegex(ReadFailure, "not a regular file"):
            open_log(str(self.logs), "d.log")

    def test_the_outside_file_is_never_counted(self) -> None:
        (self.logs / "a.log").write_bytes(b"2026-09-12T10:00:01Z GET /inside 200 12\n")
        (self.logs / "link.log").symlink_to(self.outside)
        _, out, _ = run_main(str(self.logs), "--json")
        self.assertEqual(json.loads(out)["requests"], 1)
        self.assertNotIn("/secret", out)


class TallyLines(unittest.TestCase):
    LINES = (
        b"2026-09-12T10:00:00Z GET /a 200 1\n",
        b"2026-09-12T10:00:01Z GET /a 200 1\n",
        b"2026-09-12T10:00:02Z GET /a 200 1\n",
    )

    def test_since_keeps_lines_at_or_after(self) -> None:
        tally = Tally(5)
        tally_lines(tally, self.LINES, instant("2026-09-12T10:00:01+00:00"))
        self.assertEqual(tally.requests, 2)

    def test_malformed_lines_count_whatever_since_is(self) -> None:
        tally = Tally(5)
        tally_lines(tally, [b"garbage\n", b"\n"], instant("2099-01-01T00:00:00+00:00"))
        self.assertEqual((tally.requests, tally.malformed), (0, 2))


if __name__ == "__main__":
    unittest.main()
