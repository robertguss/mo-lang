import io
import json
import os
import random
import tempfile
import unittest
from pathlib import Path

from logstat.cli import Options, UsageError, parse_args, run

FIXTURE = Path(__file__).resolve().parent.parent / "fixture"


def invoke(*argv: str) -> tuple[int, str, str]:
    out, err = io.StringIO(), io.StringIO()
    code = run(list(argv), out, err)
    return code, out.getvalue(), err.getvalue()


class ParseArgsTest(unittest.TestCase):
    def test_defaults(self) -> None:
        self.assertEqual(parse_args(["logs"]), Options(directory=Path("logs")))

    def test_all_options_in_any_order(self) -> None:
        options = parse_args(["--json", "--top", "100", "logs", "--since", "2026-09-12T10:00:00Z"])
        self.assertEqual((options.top, options.as_json), (100, True))
        self.assertIsNotNone(options.since)

    def test_rejects(self) -> None:
        cases = [
            [],
            ["a", "b"],
            ["logs", "--top", "0"],
            ["logs", "--top", "101"],
            ["logs", "--top", "-1"],
            ["logs", "--top", "five"],
            ["logs", "--top"],
            ["logs", "--top", "3", "--top", "4"],
            ["logs", "--since", "2026-09-12T10:00:00"],
            ["logs", "--since", "soon"],
            ["logs", "--json", "--json"],
            ["logs", "--verbose"],
        ]
        for argv in cases:
            with self.subTest(argv=argv), self.assertRaises(UsageError):
                parse_args(argv)


class ExitCodeTest(unittest.TestCase):
    def test_usage_error_is_2_with_one_line_on_stderr(self) -> None:
        code, out, err = invoke(str(FIXTURE), "--top", "0")
        self.assertEqual((code, out), (2, ""))
        self.assertEqual(err.count("\n"), 1)
        self.assertIn("--top", err)

    def test_no_log_file_is_1(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "notes.txt").write_text("2026-09-12T10:00:01Z GET / 200 1\n")
            Path(tmp, "nested.log").mkdir()
            code, out, err = invoke(tmp)
        self.assertEqual((code, out), (1, ""))
        self.assertIn("no .log file", err)

    def test_missing_directory_is_1(self) -> None:
        code, out, _ = invoke("/nonexistent/logstat/dir")
        self.assertEqual((code, out), (1, ""))

    def test_success_is_0(self) -> None:
        self.assertEqual(invoke(str(FIXTURE))[0], 0)


class FixtureTest(unittest.TestCase):
    def test_json_over_the_fixture(self) -> None:
        code, out, _ = invoke(str(FIXTURE), "--json")
        data = json.loads(out)
        self.assertEqual(code, 0)
        self.assertEqual(
            (data["requests"], data["errors"], data["malformed"], data["per_minute"]),
            (16, 3, 5, 4.6),
        )
        self.assertEqual(data["busiest"][0], {"count": 7, "method": "GET", "path": "/api/users"})

    def test_no_card_number_reaches_stdout(self) -> None:
        for argv in ([str(FIXTURE)], [str(FIXTURE), "--json"], [str(FIXTURE), "--top", "100"]):
            _, out, _ = invoke(*argv)
            self.assertNotIn("4111111111111111", out)
            self.assertNotIn("5500000000000004", out)
            self.assertIn("/api/cards/****************/charge", out)

    def test_since_filters_the_fixture(self) -> None:
        _, out, _ = invoke(str(FIXTURE), "--json", "--since", "2026-09-12T10:01:00Z")
        data = json.loads(out)
        self.assertEqual((data["requests"], data["errors"], data["malformed"]), (5, 1, 5))


class NeverOutsideTest(unittest.TestCase):
    def test_a_symlink_out_of_the_directory_is_not_read(self) -> None:
        with tempfile.TemporaryDirectory() as outside, tempfile.TemporaryDirectory() as inside:
            secret = Path(outside, "secret.log")
            secret.write_text("2026-09-12T10:00:01Z GET /secret 200 1\n")
            os.symlink(secret, Path(inside, "link.log"))
            os.symlink(outside, Path(inside, "dir.log"))
            Path(inside, "real.log").write_text("2026-09-12T10:00:01Z GET /mine 200 1\n")
            code, out, _ = invoke(inside)
        self.assertEqual(code, 0)
        self.assertNotIn("/secret", out)
        self.assertIn("/mine", out)

    def test_hidden_and_other_names_are_skipped(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, ".hidden.log").write_text("2026-09-12T10:00:01Z GET /hidden 200 1\n")
            Path(tmp, "a.log.bak").write_text("2026-09-12T10:00:01Z GET /bak 200 1\n")
            Path(tmp, "a.log").write_text("2026-09-12T10:00:01Z GET /a 200 1\n")
            _, out, _ = invoke(tmp, "--json")
        self.assertEqual([e["path"] for e in json.loads(out)["busiest"]], ["/a"])


class BadInputTest(unittest.TestCase):
    def test_invalid_utf8_is_malformed_and_never_crashes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "a.log").write_bytes(
                b"2026-09-12T10:00:01Z GET /a 200 1\n\xff\xfe\x00 junk\n\n\r\n"
                b"2026-09-12T10:00:02Z GET /\xc3\xa9 200 1"
            )
            code, out, _ = invoke(tmp, "--json")
        data = json.loads(out)
        self.assertEqual((code, data["requests"], data["malformed"]), (0, 2, 3))

    def test_random_bytes_never_crash_and_every_line_is_counted(self) -> None:
        pieces = [b" ", b"\n", b"\r", b"\xff", b"GET", b"/a", b"200", b"12", b"x"]
        pieces += [b"2026-09-12T10:00:01Z", b"4111111111111111", b"\x00", b"\xc3"]
        for seed in range(200):
            rng = random.Random(seed)
            lines = [
                b"".join(rng.choice(pieces) for _ in range(rng.randint(0, 12))).replace(b"\n", b"")
                for _ in range(rng.randint(1, 30))
            ]
            with tempfile.TemporaryDirectory() as tmp:
                Path(tmp, "fuzz.log").write_bytes(b"\n".join(lines) + b"\n")
                code, out, _ = invoke(tmp, "--json", "--top", "100")
            data = json.loads(out)
            with self.subTest(seed=seed):
                self.assertEqual(code, 0)
                self.assertEqual(data["requests"] + data["malformed"], len(lines))
                self.assertNotIn("4111111111111111", out)

    @unittest.skipIf(os.geteuid() == 0, "root reads any file")
    def test_an_unreadable_file_is_reported_and_skipped(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "a.log").write_text("2026-09-12T10:00:01Z GET /a 200 1\n")
            locked = Path(tmp, "b.log")
            locked.write_text("2026-09-12T10:00:01Z GET /b 200 1\n")
            locked.chmod(0)
            code, out, err = invoke(tmp, "--json")
        self.assertEqual((code, json.loads(out)["requests"]), (0, 1))
        self.assertIn("cannot read b.log", err)


if __name__ == "__main__":
    unittest.main()
