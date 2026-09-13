import io
import json
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from logstat import Options, UsageError, main, parse_args

HERE = Path(__file__).resolve().parent
FIXTURE = HERE / "fixture"


def run(*argv: str) -> tuple[int, str, str]:
    stdout, stderr = io.StringIO(), io.StringIO()
    code = main(list(argv), stdout, stderr)
    return code, stdout.getvalue(), stderr.getvalue()


class ParseArgsTest(unittest.TestCase):
    def test_defaults(self) -> None:
        self.assertEqual(parse_args(["logs"]), Options("logs", 5, None, False))

    def test_flags_in_any_order(self) -> None:
        since = datetime(2026, 9, 12, 10, 1, tzinfo=timezone.utc)
        expected = Options("logs", 100, since, True)
        self.assertEqual(parse_args(["--json", "--top", "100", "logs", "--since", "2026-09-12T10:01:00Z"]), expected)
        self.assertEqual(parse_args(["logs", "--since", "2026-09-12T10:01:00Z", "--json", "--top", "100"]), expected)

    def test_rejects_top_outside_1_to_100_rather_than_clamping(self) -> None:
        for value in ("0", "101", "-1", "abc", "5.0", "", "٥"):
            with self.subTest(value), self.assertRaises(UsageError):
                parse_args(["logs", "--top", value])

    def test_rejects_bad_arguments(self) -> None:
        cases = [
            [],
            ["a", "b"],
            ["logs", "--top"],
            ["logs", "--since"],
            ["logs", "--since", "yesterday"],
            ["logs", "--since", "2026-13-01T00:00:00Z"],
            ["logs", "--verbose"],
            ["logs", "--top=5"],
            ["logs", "--json", "--json"],
            ["logs", "--top", "5", "--top", "6"],
        ]
        for argv in cases:
            with self.subTest(argv), self.assertRaises(UsageError):
                parse_args(argv)


class MainTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.dir = Path(self.temp.name)

    def test_fixture_text_matches_expected(self) -> None:
        self.assertEqual(run(str(FIXTURE)), (0, (HERE / "expected.txt").read_text(), ""))

    def test_fixture_json_matches_expected(self) -> None:
        self.assertEqual(run(str(FIXTURE), "--json"), (0, (HERE / "expected.json").read_text(), ""))

    def test_card_numbers_never_reach_stdout(self) -> None:
        for argv in ([str(FIXTURE)], [str(FIXTURE), "--json"], [str(FIXTURE), "--top", "100"]):
            _, out, _ = run(*argv)
            self.assertNotIn("4111111111111111", out)
            self.assertNotIn("5500000000000004", out)

    def test_since_ignores_earlier_lines_but_still_counts_malformed(self) -> None:
        _, out, _ = run(str(FIXTURE), "--json", "--since", "2026-09-12T10:01:00Z")
        document = json.loads(out)
        self.assertEqual((document["requests"], document["errors"], document["malformed"]), (5, 1, 5))
        self.assertEqual(document["per_minute"], round(5 / (151 / 60), 1))

    def test_top_limits_both_lists(self) -> None:
        _, out, _ = run(str(FIXTURE), "--json", "--top", "2")
        document = json.loads(out)
        self.assertEqual([s["ms"] for s in document["slowest"]], [1204, 610])
        self.assertEqual([b["count"] for b in document["busiest"]], [7, 4])

    def test_usage_error_exits_2_with_one_stderr_line(self) -> None:
        for argv in (["--top", "0", str(FIXTURE)], [], [str(self.dir / "missing")], [str(FIXTURE / "a.log")]):
            with self.subTest(argv):
                code, out, err = run(*argv)
                self.assertEqual((code, out), (2, ""))
                self.assertEqual(err.count("\n"), 1)

    def test_no_log_file_exits_1(self) -> None:
        (self.dir / "notes.txt").write_text("hello\n")
        code, out, err = run(str(self.dir))
        self.assertEqual((code, out, err.count("\n")), (1, "", 1))

    def test_bad_bytes_and_garbage_are_malformed_not_crashes(self) -> None:
        (self.dir / "x.log").write_bytes(
            b"\xff\xfe\x00garbage\n2026-09-12T10:00:00Z GET / 200 1\n\x00\n" + b"9" * 10_000 + b"\n\n"
        )
        code, out, _ = run(str(self.dir), "--json")
        document = json.loads(out)
        self.assertEqual((code, document["requests"], document["malformed"]), (0, 1, 4))

    def test_empty_log_file_reports_zero(self) -> None:
        (self.dir / "empty.log").write_bytes(b"")
        code, out, _ = run(str(self.dir))
        self.assertEqual(code, 0)
        self.assertTrue(out.startswith("requests       0\n"))

    def test_symlinked_log_to_outside_is_not_read(self) -> None:
        logs = self.dir / "logs"
        logs.mkdir()
        secret = self.dir / "secret.log"
        secret.write_text("2026-09-12T10:00:00Z GET /secret 200 1\n")
        (logs / "link.log").symlink_to(secret)
        (logs / "real.log").write_text("2026-09-12T10:00:00Z GET /real 200 1\n")
        _, out, _ = run(str(logs))
        self.assertNotIn("/secret", out)
        self.assertIn("/real", out)

    def test_script_runs_as_a_program(self) -> None:
        result = subprocess.run(
            [sys.executable, str(HERE / "logstat.py"), str(FIXTURE), "--top", "101"],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual((result.returncode, result.stdout, result.stderr.count("\n")), (2, "", 1))


if __name__ == "__main__":
    unittest.main()
