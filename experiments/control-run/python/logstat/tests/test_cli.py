import io
import json
import os
import tempfile
import unittest
from pathlib import Path

from logstat.cli import EXIT_NO_LOGS, EXIT_OK, EXIT_USAGE, run

PROJECT = Path(__file__).resolve().parent.parent
FIXTURE = PROJECT / "fixture"


def invoke(*argv: str) -> tuple[int, str, str]:
    stdout, stderr = io.StringIO(), io.StringIO()
    code = run(list(argv), stdout, stderr)
    return code, stdout.getvalue(), stderr.getvalue()


class FixtureTest(unittest.TestCase):
    def test_text_report_matches_expected(self) -> None:
        code, out, err = invoke(str(FIXTURE))
        self.assertEqual((code, err), (EXIT_OK, ""))
        self.assertEqual(out, (PROJECT / "expected.txt").read_text())

    def test_json_report_matches_expected(self) -> None:
        code, out, _ = invoke(str(FIXTURE), "--json")
        self.assertEqual(code, EXIT_OK)
        self.assertEqual(json.loads(out), json.loads((PROJECT / "expected.json").read_text()))

    def test_the_card_number_never_reaches_stdout(self) -> None:
        self.assertIn("4111111111111111", (FIXTURE / "b.log").read_text())
        for argv in ([str(FIXTURE)], [str(FIXTURE), "--json"], [str(FIXTURE), "--top", "100"]):
            _, out, _ = invoke(*argv)
            self.assertNotIn("4111111111111111", out)

    def test_top_and_since(self) -> None:
        code, out, _ = invoke(str(FIXTURE), "--json", "--top", "1", "--since", "2026-09-12T10:04:00Z")
        self.assertEqual(code, EXIT_OK)
        doc = json.loads(out)
        self.assertEqual((doc["requests"], doc["malformed"]), (3, 3))
        self.assertEqual(len(doc["slowest"]), 1)
        self.assertEqual(len(doc["busiest"]), 1)


class ExitCodeTest(unittest.TestCase):
    def test_usage_error_is_2_with_one_line(self) -> None:
        code, out, err = invoke(str(FIXTURE), "--top", "0")
        self.assertEqual((code, out), (EXIT_USAGE, ""))
        self.assertEqual(err.count("\n"), 1)

    def test_a_missing_directory_is_a_usage_error(self) -> None:
        code, _, err = invoke(str(FIXTURE / "missing"))
        self.assertEqual(code, EXIT_USAGE)
        self.assertEqual(err.count("\n"), 1)

    def test_no_log_file_is_1(self) -> None:
        with tempfile.TemporaryDirectory() as empty:
            (Path(empty) / "notes.txt").write_text("x\n")
            code, out, _ = invoke(empty)
        self.assertEqual((code, out), (EXIT_NO_LOGS, ""))

    @unittest.skipIf(os.geteuid() == 0, "root reads any file")
    def test_an_unreadable_log_file_is_1_and_prints_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            locked = Path(tmp) / "a.log"
            locked.write_text("2026-09-12T10:00:00Z GET / 200 1\n")
            locked.chmod(0)
            code, out, err = invoke(tmp)
        self.assertEqual((code, out), (EXIT_NO_LOGS, ""))
        self.assertIn("cannot read a.log", err)


if __name__ == "__main__":
    unittest.main()
