#!/usr/bin/env python3
"""Regenerate only the authorized dependency closure and check/build its consumers."""
import json
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
MO = os.environ.get("MO_BIN", str(ROOT / "toolchain/zig-out/bin/mo"))
FILES = [("tools", True), ("steps", False), ("run", True), ("registry", False),
         ("server", True), ("check", False), ("main", False), ("runs", True),
         ("tests/terminal-auth/driver", True)]

def run(name, command):
    command = ["python3", "toolchain/bench/step36/guard.py", "180", "--"] + command
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=190)
    print(json.dumps(dict(name=name, command=command, exit_code=result.returncode,
                         stdout=result.stdout, stderr=result.stderr)), flush=True)
    if result.returncode:
        sys.exit(result.returncode)

for name, sim in FILES:
    command = [MO, "test", "--write"] + (["--sim", "100"] if sim else [])
    run("write-" + name, command + [f"examples/programs/agent/{name}.mo"])
for name, _ in FILES:
    run("check-" + name, [MO, "check", f"examples/programs/agent/{name}.mo"])
run("agent-build", [MO, "build", "examples/programs/agent/main.mo", "-o", "terminal-auth-agent-v2"])
run("driver-build", [MO, "build", str(HERE / "driver.mo"), "-o", "terminal-auth-driver-v2"])
for name, _ in FILES:
    output = "terminal-auth-tests-v2-" + name.split("/")[-1]
    run("native-tests-build-" + name, [MO, "build", "--tests", f"examples/programs/agent/{name}.mo", "-o", output])
    run("native-tests-" + name, [str(ROOT / "zig-out/mo-build" / output / output)])
