"""The fuzz driver's own tests (step 43): its arguments and its accounting, with the TLS driver
mocked. No input is fuzzed here. Run from this folder: python3 -m unittest test_fuzz
"""

from __future__ import annotations

import contextlib
import io
import pathlib
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import fuzz  # noqa: E402


def campaign(argv: list[str], runs: list[tuple[int, str]], cpu: list[float]) -> dict:
    """fuzz.main() on `argv`, each driver run answering from `runs` and the CPU clock from `cpu`."""
    with tempfile.TemporaryDirectory() as d:
        work = pathlib.Path(d)
        setup = []

        def record(*args, **kwargs):
            dest = pathlib.Path(kwargs["env"]["MO_FUZZ_RECORD"])
            for i in range(16):
                (dest / f"case-{i:02d}.bin").write_bytes(b"MOFZ\x00")
            return types.SimpleNamespace(returncode=0, stdout="", stderr="")

        answers = iter(runs)
        calls = []

        def run(listing, seconds):
            calls.append(listing)
            return next(answers)

        out, err = io.StringIO(), io.StringIO()
        code = None
        with patch.object(fuzz.c, "WORK", work), \
                patch.object(fuzz.c, "ensure_tools", lambda: setup.append("tools")), \
                patch.object(fuzz.subprocess, "run", record), \
                patch.object(fuzz, "run", run), \
                patch.object(fuzz, "cpu_seconds", side_effect=cpu), \
                patch.object(fuzz, "mutate", lambda *a: (b"MOFZ\x00", ["mock"])), \
                patch.object(fuzz.c, "stamp", lambda: "date\n"), \
                patch.object(sys, "argv", ["fuzz.py", *argv]), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                code = fuzz.main()
            except SystemExit as e:
                code = e.code
        return {"code": code, "setup": setup, "calls": calls, "out": out.getvalue(), "err": err.getvalue(),
                "made": sorted(p.name for p in work.iterdir())}


PLANTED = [(134, "planted panic"), (3, "planted hang")]


class Arguments(unittest.TestCase):
    def test_minutes_must_be_finite_and_positive(self):
        for bad in ["0", "-1", "nan", "inf", "-inf", "-0", "ten"]:
            with self.subTest(minutes=bad):
                r = campaign(["--seed", "1", "--minutes", bad], [], [])
                self.assertEqual(r["code"], 2, r)
                self.assertEqual(r["setup"], [], "refused before the tools are built")
                self.assertEqual(r["made"], [], "refused before the work folder is made")
                self.assertIn("--minutes", r["err"])

    def test_batch_must_be_positive(self):
        for bad in ["0", "-3", "1.5", "many"]:
            with self.subTest(batch=bad):
                r = campaign(["--seed", "1", "--batch", bad], [], [])
                self.assertEqual(r["code"], 2, r)
                self.assertEqual(r["setup"], [])
                self.assertEqual(r["made"], [])
                self.assertIn("--batch", r["err"])


class Accounting(unittest.TestCase):
    def test_a_campaign_of_no_inputs_never_exits_0(self):
        # The CPU budget is spent before the first batch.
        r = campaign(["--seed", "1", "--minutes", "0.001", "--batch", "2"], PLANTED, [0, 100, 100])
        self.assertNotEqual(r["code"], 0, r)
        self.assertIn("0 inputs", r["out"])
        self.assertEqual(len(r["calls"]), 2, "only the planted panic and hang ran")

    def test_a_failed_batch_exits_1(self):
        r = campaign(["--seed", "1", "--minutes", "0.001", "--batch", "2"],
                     PLANTED + [(134, "batch failed"), (0, ""), (0, "")], [0, 0, 1, 1])
        self.assertEqual(r["code"], 1, r)
        self.assertIn("1 failed batches", r["out"])

    def test_a_clean_campaign_with_inputs_exits_0(self):
        r = campaign(["--seed", "1", "--minutes", "0.001", "--batch", "2"], PLANTED + [(0, "")], [0, 0, 1, 1])
        self.assertEqual(r["code"], 0, r)
        self.assertIn("2 inputs in 1 batches", r["out"])


if __name__ == "__main__":
    unittest.main()
