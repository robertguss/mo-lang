#!/usr/bin/env python3
"""Focused review checks; no compiler execution except one selected HTTP case."""
import contextlib
import io
import json
import os
from pathlib import Path
import runpy
import subprocess
from types import SimpleNamespace
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
GUARD = ["python3", str(ROOT / "toolchain/bench/step36/guard.py"), "30", "--"]

for override in [None, "/explicit/compiler/mo"]:
    environment = dict(os.environ)
    environment.pop("MO_BIN", None)
    if override is not None:
        environment["MO_BIN"] = override
    expected = override or str(ROOT / "toolchain/zig-out/bin/mo")
    with patch.dict(os.environ, environment, clear=True):
        runner = runpy.run_path(str(HERE / "run.py"))
        assert runner["MO"] == expected
        with patch("subprocess.run", return_value=SimpleNamespace(returncode=0, stdout="", stderr="")) as calls:
            with contextlib.redirect_stdout(io.StringIO()):
                try:
                    runpy.run_path(str(HERE / "checks.py"))
                except SystemExit as exc:
                    assert exc.code == 0
            assert calls.call_count == 6
            assert all(call.args[0][4] == expected for call in calls.call_args_list)
    print(json.dumps(dict(check="compiler-selection", override=override, passed=True)), flush=True)

for mode in ["interpreter", "compiled"]:
    command = GUARD + ["python3", str(HERE / "run.py"), mode, "--only", "typo"]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=35)
    print(json.dumps(dict(command=command, exit_code=result.returncode,
        stdout=result.stdout, stderr=result.stderr)), flush=True)
    assert result.returncode == 2 and not result.stdout
    assert "invalid choice" in result.stderr

command = GUARD + ["python3", str(HERE / "run.py"), "interpreter", "--only", "immediate-401"]
result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=35)
print(json.dumps(dict(command=command, exit_code=result.returncode,
    stdout=result.stdout, stderr=result.stderr)), flush=True)
assert result.returncode == 0
rows = [json.loads(line) for line in result.stdout.splitlines()]
assert len(rows) == 1 and rows[0]["case"] == "immediate-401"
assert rows[0]["passed"] and rows[0]["server_closed"]
assert rows[0]["command"][4] == os.environ.get("MO_BIN", str(ROOT / "toolchain/zig-out/bin/mo"))

prior = "6a29653002a89261c7ed5c21d73ca4c16f64e325"
paths = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", prior,
    "examples/programs/agent/tests/terminal-auth/evidence"], cwd=ROOT, text=True).splitlines()
for path in paths:
    assert (ROOT / path).read_bytes() == subprocess.check_output(["git", "show", f"{prior}:{path}"], cwd=ROOT)
print(json.dumps(dict(prior_evidence_files_unchanged=len(paths), passed=True)), flush=True)
