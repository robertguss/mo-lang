#!/usr/bin/env python3
"""Refresh the formatter-invalidated driver record and verify the bounded change."""
import json
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
MO = os.environ.get("MO_BIN", str(ROOT / "toolchain/zig-out/bin/mo"))
FILES = ["examples/programs/agent/model.mo", "examples/programs/agent/tests/terminal-auth/driver.mo",
         "examples/recipes/agent-model-client-v1.mo"]

def run(name, args):
    command = ["python3", "toolchain/bench/step36/guard.py", "120", "--"] + args
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=130)
    print(json.dumps(dict(name=name, command=command, exit_code=result.returncode,
                         stdout=result.stdout, stderr=result.stderr)), flush=True)
    if result.returncode:
        sys.exit(result.returncode)

run("driver-write", [MO, "test", "--write", "--sim", "100", FILES[1]])
for path in FILES:
    run("fmt-check-" + path, [MO, "fmt", "--check", path])
    run("check-" + path, [MO, "check", path])
run("model-tests", [MO, "test", FILES[0]])
run("generic-tests", [MO, "check", "--recipe", "Recipes.ModelClient.ModelClient", FILES[0]])
run("agent-check", [MO, "check", "examples/programs/agent/main.mo"])
run("agent-build", [MO, "build", "examples/programs/agent/main.mo", "-o", "terminal-auth-agent-v3"])
run("driver-build", [MO, "build", FILES[1], "-o", "terminal-auth"])
for mode in ["interpreter", "compiled"]:
    for case in ["immediate-401", "exhausted", "delayed"]:
        run(mode + "-" + case, ["python3", str(HERE / "run.py"), mode, "--only", case])
