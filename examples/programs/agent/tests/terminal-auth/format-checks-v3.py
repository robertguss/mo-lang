#!/usr/bin/env python3
"""Capture actual formatter output, apply it only to owned sources, and check it."""
import hashlib
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
    command = ["python3", "toolchain/bench/step36/guard.py", "120", "--", MO] + args
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=130)
    print(json.dumps(dict(name=name, command=command, exit_code=result.returncode,
                         stdout=result.stdout, stderr=result.stderr)), flush=True)
    if result.returncode:
        sys.exit(result.returncode)
    return result.stdout

manifest = []
for path in FILES:
    before = (ROOT / path).read_bytes()
    formatted = run("preview-" + path, ["fmt", "--stdout", path]).encode()
    run("format-" + path, ["fmt", path])
    assert (ROOT / path).read_bytes() == formatted
    manifest.append(dict(path=path, before_sha256=hashlib.sha256(before).hexdigest(),
                         after_sha256=hashlib.sha256(formatted).hexdigest()))
(HERE / "evidence/formatter-manifest-v3.json").write_text(json.dumps(manifest, indent=2) + "\n")
for path in FILES:
    run("fmt-check-" + path, ["fmt", "--check", path])
    run("check-" + path, ["check", path])
run("model-tests", ["test", FILES[0]])
run("generic-tests", ["check", "--recipe", "Recipes.ModelClient.ModelClient", FILES[0]])
run("agent-check", ["check", "examples/programs/agent/main.mo"])
run("agent-build", ["build", "examples/programs/agent/main.mo", "-o", "terminal-auth-agent-v3"])
run("driver-build", ["build", FILES[1], "-o", "terminal-auth-driver-v3"])
