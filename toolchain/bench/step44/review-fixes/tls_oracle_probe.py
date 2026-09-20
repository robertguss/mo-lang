#!/usr/bin/env python3
"""Force an ALPN handshake error and require the strict positive TLS oracle to fail."""
from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SOURCE = ROOT / "toolchain/testdata/step44/chunks-tls.mo"
GUARD = [sys.executable, "toolchain/bench/step36/guard.py", "30", "--"]
NAME = "step44-tls-forced-error"
BINARY = ROOT / f"zig-out/mo-build/{NAME}/{NAME}"


def guarded(*command: str) -> subprocess.CompletedProcess[str]:
    full = GUARD + list(command)
    completed = subprocess.run(full, cwd=ROOT, text=True, capture_output=True, timeout=35)
    print("$ " + " ".join(full))
    print(completed.stdout, end="")
    print(completed.stderr, end="", file=sys.stderr)
    print(f"guard_exit={completed.returncode}")
    return completed


def forced_source() -> str:
    source = SOURCE.read_text()
    positive = 'got = tried(Tls.fixture(), Net.fixture(), Sink.start(), ["step44/1"], ["step44/1"])'
    forced = 'got = tried(Tls.fixture(), Net.fixture(), Sink.start(), ["client-only"], ["server-only"])'
    if source.count(positive) < 1:
        raise RuntimeError("strict TLS positive call was not found")
    mutated = source.replace(positive, forced, 1)
    unstamped = [
        line
        for line in mutated.splitlines()
        if not line.startswith("verified:") and not line.startswith("          proven:")
    ]
    return "\n".join(unstamped) + "\n"


def require_oracle_failure(completed: subprocess.CompletedProcess[str]) -> None:
    combined = completed.stdout + completed.stderr
    if "guard: killed" in combined or completed.returncode < 0 or completed.returncode >= 128:
        raise AssertionError(("guard or signal termination is not an oracle failure", completed.returncode, combined))
    if completed.returncode != 1:
        raise AssertionError(("the positive oracle must fail with test exit 1", completed.returncode, combined))
    required = (
        'FAIL  test "fault-free TLS chunks exchange exact bounded plaintext in both directions"',
        "assert successful?(got)",
    )
    missing = [text for text in required if text not in combined]
    if missing:
        raise AssertionError((missing, combined))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", choices=("run", "binary"), required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="tls-oracle-", dir=HERE) as folder:
        mutant = Path(folder) / "chunks-tls-forced-error.mo"
        mutant.write_text(forced_source())
        if args.runtime == "run":
            completed = guarded("toolchain/zig-out/bin/mo", "test", str(mutant.relative_to(ROOT)))
        else:
            build = guarded(
                "toolchain/zig-out/bin/mo",
                "build",
                "--tests",
                "-o",
                NAME,
                str(mutant.relative_to(ROOT)),
            )
            if build.returncode != 0:
                raise AssertionError(("mutant build failed", build.stdout, build.stderr))
            completed = guarded(str(BINARY.relative_to(ROOT)))
        require_oracle_failure(completed)
    if BINARY.parent.exists():
        shutil.rmtree(BINARY.parent)
    print(f"runtime={args.runtime} forced_handshake=Handshake positive_oracle=failed result=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
