#!/usr/bin/env python3
"""Lightweight recorder-control tests; no payload process is started."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import sys
import tempfile
import unittest
from unittest.mock import patch


VERIFY_PATH = Path(__file__).with_name("verify.py")
SPEC = importlib.util.spec_from_file_location("moscope_acceptance_verify_tested", VERIFY_PATH)
assert SPEC is not None and SPEC.loader is not None
verify = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = verify
SPEC.loader.exec_module(verify)


class FakeResult:
    def __init__(
        self,
        *,
        reason: str = "child_exit",
        raw: int | None = 0,
        supervision_error: str | None = None,
        group_state: str = "absent",
    ) -> None:
        self.process_group = 4242
        self.child_returncode = raw
        self.reason = reason
        self.rss_bytes = 1024
        self.elapsed_seconds = 0.01
        self.supervision_error = supervision_error
        self.group = SimpleNamespace(state=group_state, rows=[], error=None)

    @property
    def child_exit(self) -> int | None:
        if self.child_returncode is None:
            return None
        if self.child_returncode < 0:
            return 128 - self.child_returncode
        return self.child_returncode


class FakeGuard:
    def __init__(self, results: list[FakeResult]) -> None:
        self.results = results
        self.launches = 0

    def supervise(self, *_args, **_kwargs) -> FakeResult:
        result = self.results[self.launches]
        self.launches += 1
        return result


def case(name: str, expected: int = 0, restore=None) -> dict[str, object]:
    made = {
        "name": name,
        "command": ["not-launched-by-fake-guard"],
        "exit": expected,
        "stdout": b"",
        "stderr": b"",
    }
    if restore is not None:
        made["restore"] = restore
    return made


class RecorderStopTests(unittest.TestCase):
    def run_unsafe(self, result: FakeResult, *, restoration_error: bool = False) -> None:
        guard = FakeGuard([result, FakeResult()])
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / "artifacts"
            restore = [[str(Path(temporary) / "missing"), 0o600]] if restoration_error else None
            cases = [case("unsafe", restore=restore), case("must-not-launch")]
            with (
                patch.object(verify, "interpreter_cases", return_value=cases),
                patch.object(verify, "load_guard", return_value=guard),
                patch.object(verify, "source_identity", return_value={"tree_sha256": "mock", "entries": []}),
            ):
                with self.assertRaises(SystemExit):
                    verify.run_interpreter(Path("/accepted/mo"), destination)
            self.assertEqual(guard.launches, 1)
            receipt = json.loads((destination / "001-unsafe/receipt.json").read_text())
            self.assertEqual(receipt["state"], "INCOMPLETE")
            self.assertFalse(receipt["passed"])
            self.assertTrue(receipt["unsafe_outcome"])
            self.assertFalse((destination / "002-must-not-launch").exists())

    def test_each_unsafe_result_records_and_stops_before_a_second_launch(self) -> None:
        outcomes = {
            "non-child reason": FakeResult(reason="deadline"),
            "signal return": FakeResult(raw=-9),
            "missing return": FakeResult(raw=None),
            "supervision error": FakeResult(supervision_error="probe failed"),
            "group not absent": FakeResult(group_state="live"),
        }
        for name, result in outcomes.items():
            with self.subTest(name=name):
                self.run_unsafe(result)
        with self.subTest(name="fixture restoration error"):
            self.run_unsafe(FakeResult(), restoration_error=True)

    def test_expected_status_one_and_two_are_normal_and_continue(self) -> None:
        guard = FakeGuard([FakeResult(raw=1), FakeResult(raw=2)])
        cases = [case("expected-one", 1), case("expected-two", 2)]
        with tempfile.TemporaryDirectory() as temporary:
            with (
                patch.object(verify, "interpreter_cases", return_value=cases),
                patch.object(verify, "load_guard", return_value=guard),
                patch.object(verify, "source_identity", return_value={"tree_sha256": "mock", "entries": []}),
            ):
                status = verify.run_interpreter(Path("/accepted/mo"), Path(temporary) / "artifacts")
        self.assertEqual(status, 0)
        self.assertEqual(guard.launches, 2)


if __name__ == "__main__":
    unittest.main()
