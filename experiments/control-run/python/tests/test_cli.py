import io
import json
import os
import re
import tempfile
import unittest
from pathlib import Path

from logstat.cli import EXIT_NO_LOGS, EXIT_OK, EXIT_USAGE, Options, UsageError, main, parse_args
from tests.support import BASE

HERE = Path(__file__).resolve().parent.parent
FIXTURE = HERE / "fixture"
LINE_A = "2026-09-12T10:00:01Z GET /inside 200 7\n"


def run(*argv: str) -> tuple[int, str, str]:
    stdout, stderr = io.BytesIO(), io.StringIO()
    code = main(list(argv), stdout, stderr)
    return code, stdout.getvalue().decode("utf-8"), stderr.getvalue()


class ParseArgsTest(unittest.TestCase):
    def test_defaults(self) -> None:
        self.assertEqual(parse_args(["logs"]), Options("logs", 5, None, False))

    def test_flags_in_any_order(self) -> None:
        options = parse_args(["--json", "--since", "2026-09-12T10:00:00Z", "logs", "--top", "100"])
        self.assertEqual(options, Options("logs", 100, BASE, True))

    def test_top_one_is_allowed(self) -> None:
        self.assertEqual(parse_args(["logs", "--top", "1"]).top, 1)

    def test_usage_errors(self) -> None:
        for argv in [
            [],
            ["a", "b"],
            ["logs", "--top"],
            ["logs", "--top", "0"],
            ["logs", "--top", "101"],
            ["logs", "--top", "-1"],
            ["logs", "--top", "+5"],
            ["logs", "--top", "1.5"],
            ["logs", "--top", "abc"],
            ["logs", "--top", "5", "--top", "6"],
            ["logs", "--since"],
            ["logs", "--since", "yesterday"],
            ["logs", "--since", "2026-13-01T00:00:00Z"],
            ["logs", "--json", "--json"],
            ["logs", "--verbose"],
            ["logs", "-x"],
        ]:
            with self.subTest(argv=argv), self.assertRaises(UsageError):
                parse_args(argv)


class ExitCodeTest(unittest.TestCase):
    def test_usage_error_is_2_with_one_stderr_line(self) -> None:
        code, out, err = run(str(FIXTURE), "--top", "0")
        self.assertEqual((code, out, err.count("\n")), (EXIT_USAGE, "", 1))
        self.assertTrue(err.startswith("logstat: --top"))

    def test_missing_directory_is_a_usage_error(self) -> None:
        code, out, err = run(str(FIXTURE / "nope"))
        self.assertEqual((code, out, err.count("\n")), (EXIT_USAGE, "", 1))

    def test_no_log_file_is_1(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "notes.txt").write_text(LINE_A)
            Path(tmp, "old.log.gz").write_text(LINE_A)
            code, out, err = run(tmp)
        self.assertEqual((code, out, err.count("\n")), (EXIT_NO_LOGS, "", 1))

    def test_unreadable_log_is_1(self) -> None:
        if os.geteuid() == 0:
            self.skipTest("root reads anything")
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "a.log").write_text(LINE_A)
            Path(tmp, "a.log").chmod(0)
            code, out, err = run(tmp)
        self.assertEqual((code, out, err.count("\n")), (EXIT_NO_LOGS, "", 1))


class FixtureTest(unittest.TestCase):
    def test_text_report(self) -> None:
        self.assertEqual(run(str(FIXTURE)), (EXIT_OK, (HERE / "expected.txt").read_text(), ""))

    def test_json_report(self) -> None:
        self.assertEqual(run(str(FIXTURE), "--json"), (EXIT_OK, (HERE / "expected.json").read_text(), ""))

    def test_no_card_number_reaches_stdout(self) -> None:
        for flags in [[], ["--json"], ["--top", "100"]]:
            with self.subTest(flags=flags):
                self.assertIsNone(re.search(r"[0-9]{16}", run(str(FIXTURE), *flags)[1]))

    def test_since_ignores_earlier_lines_but_still_counts_malformed(self) -> None:
        code, out, _ = run(str(FIXTURE), "--json", "--since", "2026-09-12T10:01:00Z", "--top", "2")
        document = json.loads(out)
        self.assertEqual(code, EXIT_OK)
        self.assertEqual((document["requests"], document["errors"], document["malformed"]), (5, 1, 5))
        self.assertEqual([s["ms"] for s in document["slowest"]], [610, 340])
        self.assertEqual(document["per_minute"], 2.0)


class DirectoryTest(unittest.TestCase):
    def test_reads_only_regular_log_files_directly_inside(self) -> None:
        with tempfile.TemporaryDirectory() as outer:
            secret = Path(outer, "secret.log")
            secret.write_text("2026-09-12T10:00:01Z GET /secret 200 9\n")
            logs = Path(outer, "logs")
            (logs / "nested.log").mkdir(parents=True)
            (logs / "nested.log" / "deep.log").write_text("2026-09-12T10:00:01Z GET /deep 200 9\n")
            (logs / "a.log").write_text(LINE_A)
            (logs / "link.log").symlink_to(secret)
            (logs / "up.log").symlink_to(Path("..", "secret.log"))
            code, out, _ = run(str(logs), "--json")
        document = json.loads(out)
        self.assertEqual(code, EXIT_OK)
        self.assertEqual([entry["path"] for entry in document["busiest"]], ["/inside"])

    def test_files_are_read_in_name_order(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "b.log").write_text("2026-09-12T10:00:01Z GET /from-b 200 7\n")
            Path(tmp, "a.log").write_text("2026-09-12T10:00:01Z GET /from-a 200 7\n")
            _, out, _ = run(tmp, "--json")
        self.assertEqual([s["path"] for s in json.loads(out)["slowest"]], ["/from-a", "/from-b"])

    def test_bad_bytes_are_malformed_not_a_crash(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "a.log").write_bytes(b"\xff\xfe\x00garbage\n" + LINE_A.encode() + b"\x00" * 50)
            code, out, _ = run(tmp, "--json")
        self.assertEqual(code, EXIT_OK)
        self.assertEqual((json.loads(out)["requests"], json.loads(out)["malformed"]), (1, 2))


if __name__ == "__main__":
    unittest.main()
