#!/usr/bin/env python3
"""Bounded recipe/unit/build verification with per-command logs and real exit codes."""
import json
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[5]
HERE = pathlib.Path(__file__).resolve().parent
MO = os.environ.get("MO_BIN", str(ROOT / "toolchain/zig-out/bin/mo"))
commands = [
    ("model-write", [MO, "test", "--write", "examples/programs/agent/model.mo"]),
    ("recipe-write", [MO, "test", "--write", "examples/recipes/agent-model-client-v1.mo"]),
    ("conformance", [MO, "check", "examples/programs/agent/model.mo"]),
    ("generic-conformance", [MO, "check", "--recipe", "Recipes.ModelClient.ModelClient", "examples/programs/agent/model.mo"]),
    ("driver-check", [MO, "check", str(HERE / "driver.mo")]),
    ("driver-build", [MO, "build", str(HERE / "driver.mo"), "-o", "terminal-auth"]),
]
failures = 0
for name, command in commands:
    guarded = ["python3", "toolchain/bench/step36/guard.py", "180", "--"] + command
    result = subprocess.run(guarded, cwd=ROOT, capture_output=True, text=True, timeout=190)
    print(json.dumps(dict(name=name, command=guarded, exit_code=result.returncode,
                         stdout=result.stdout, stderr=result.stderr)), flush=True)
    failures += result.returncode != 0
sys.exit(int(failures != 0))
