from __future__ import annotations

import io
import json
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from logstat import EXIT_NO_LOGS, EXIT_OK, EXIT_USAGE, UsageError, main, parse_args

HERE = Path(__file__).resolve().parent
FIXTURE = HERE / "fixture"


def run(*argv: str) -> tuple[int, str, str]:
    out, err = io.StringIO(), io.StringIO()
    status = main(list(argv), out, err)
    return status, out.getvalue(), err.getvalue()


class ArgsTest(unittest.TestCase):
    def test_defaults(self) -> None:
        options = parse_args(["logs"])
        self.assertEqual((options.directory, options.top, options.since, options.as_json), (Path("logs"), 5, None, False))

    def test_all_options_in_any_order(self) -> None:
        options = parse_args(["--json", "--top", "100", "logs", "--since", "2026-09-12T10:00:00Z"])
        self.assertEqual(options.top, 100)
        self.assertEqual(options.since, datetime(2026, 9, 12, 10, tzinfo=timezone.utc))
        self.assertTrue(options.as_json)

    def test_rejects_top_outside_1_to_100_without_clamping(self) -> None:
        for top in ("0", "101", "-1", "abc", "5.0", "", "99999999999"):
            with self.assertRaises(UsageError, msg=top):
                parse_args(["logs", "--top", top])
        self.assertEqual(parse_args(["logs", "--top", "1"]).top, 1)

    def test_rejects_bad_usage(self) -> None:
        bad: tuple[list[str], ...] = (
            [],
            ["a", "b"],
            ["logs", "--top"],
            ["logs", "--since"],
            ["logs", "--since", "yesterday"],
            ["logs", "--verbose"],
            ["logs", "--json", "--json"],
            ["logs", "--top", "3", "--top", "4"],
        )
        for argv in bad:
            with self.assertRaises(UsageError, msg=str(argv)):
                parse_args(argv)


class ExitCodeTest(unittest.TestCase):
    def test_usage_error_is_2_with_one_line_on_stderr(self) -> None:
        status, out, err = run(str(FIXTURE), "--top", "101")
        self.assertEqual((status, out), (EXIT_USAGE, ""))
        self.assertEqual(err.count("\n"), 1)
        self.assertIn("usage: logstat", err)

    def test_missing_directory_is_a_usage_error(self) -> None:
        self.assertEqual(run(str(FIXTURE / "nope"))[0], EXIT_USAGE)
        self.assertEqual(run(str(FIXTURE / "a.log"))[0], EXIT_USAGE)

    def test_no_log_file_is_1(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "notes.txt").write_text("x\n")
            status, out, err = run(tmp)
        self.assertEqual((status, out), (EXIT_NO_LOGS, ""))
        self.assertIn("no .log file", err)

    def test_success_is_0(self) -> None:
        status, out, err = run(str(FIXTURE))
        self.assertEqual((status, err), (EXIT_OK, ""))
        self.assertTrue(out.startswith("requests"))


class FixtureTest(unittest.TestCase):
    def test_text_matches_expected(self) -> None:
        self.assertEqual(run(str(FIXTURE))[1], (HERE / "expected.txt").read_text())

    def test_json_matches_expected(self) -> None:
        self.assertEqual(run(str(FIXTURE), "--json")[1], (HERE / "expected.json").read_text())

    def test_card_numbers_never_reach_stdout(self) -> None:
        for argv in ([str(FIXTURE)], [str(FIXTURE), "--json"], [str(FIXTURE), "--top", "100"]):
            out = run(*argv)[1]
            self.assertNotIn("4111111111111111", out)
            self.assertNotIn("5500000000000004", out)

    def test_since_ignores_earlier_lines_but_counts_malformed(self) -> None:
        document = json.loads(run(str(FIXTURE), "--json", "--since", "2026-09-12T10:01:00Z")[1])
        self.assertEqual((document["requests"], document["errors"], document["malformed"]), (5, 1, 5))

    def test_top_limits_both_lists(self) -> None:
        document = json.loads(run(str(FIXTURE), "--json", "--top", "2")[1])
        self.assertEqual((len(document["slowest"]), len(document["busiest"])), (2, 2))

    def test_invariants_hold_on_fixture(self) -> None:
        document = json.loads(run(str(FIXTURE), "--json")[1])
        self.assertLessEqual(document["errors"], document["requests"])


class ProcessTest(unittest.TestCase):
    def test_script_runs_as_a_program(self) -> None:
        result = subprocess.run(
            [sys.executable, str(HERE / "logstat.py"), str(FIXTURE), "--top", "0"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual((result.returncode, result.stdout), (EXIT_USAGE, ""))
        self.assertEqual(result.stderr.count("\n"), 1)


if __name__ == "__main__":
    unittest.main()
