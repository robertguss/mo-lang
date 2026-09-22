#!/usr/bin/env python3
"""Record the lead-owned final toolchain regression; this worker does not run it."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import time

import verify


TOOLCHAIN = verify.ROOT / "toolchain"
COMMANDS = [
    ("zig-build", 900, ["build", "-j4", "--summary", "all"]),
    ("zig-test-corpus", 7200, ["build", "test-corpus", "-j4", "--summary", "all"]),
]
SIGNAL_GRACE_SECONDS = 2
OUTER_SLOP_SECONDS = 5


def checked_zig(value: str) -> Path:
    zig = Path(value)
    if not zig.is_absolute() or not zig.is_file():
        raise SystemExit("--zig must be an absolute regular-file path")
    return zig


def environment(root: Path, zig: Path) -> dict[str, str]:
    home = root / "home"
    temporary = root / "tmp"
    global_cache = root / "cache/zig-global"
    local_cache = root / "cache/zig-local"
    mo_cache = root / "cache/mo"
    for folder in (home, temporary, global_cache, local_cache, mo_cache):
        folder.mkdir(parents=True)
    return {
        "HOME": str(home),
        "TMPDIR": str(temporary),
        "PATH": os.pathsep.join([str(zig.parent), "/usr/bin", "/bin"]),
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8",
        "TZ": "UTC",
        "ZIG_GLOBAL_CACHE_DIR": str(global_cache),
        "ZIG_LOCAL_CACHE_DIR": str(local_cache),
        "MO_CACHE": str(mo_cache),
    }


def run_one(
    number: int,
    name: str,
    budget: int,
    tail: list[str],
    zig: Path,
    destination: Path,
    guard,
    source: dict[str, object],
) -> dict[str, object]:
    case_dir = destination / f"{number:02d}-{name}"
    case_dir.mkdir()
    stdout_path = case_dir / "stdout.raw"
    stderr_path = case_dir / "stderr.raw"
    receipt_path = case_dir / "receipt.json"
    command = [str(zig), *tail]
    env = environment(case_dir, zig)
    pending = {
        "schema": "moscope-final-regression-v1",
        "state": "started",
        "case": name,
        "argv": command,
        "display_command": f"zig {' '.join(tail)}",
        "cwd": str(TOOLCHAIN),
        "environment": env,
        "forbidden_inherited_environment": ["MO_NATIVE_ASAN", "MO_STRESS", "MO_EXE", "MO_CORPUS"],
        "zig": {"path": str(zig), "bytes": zig.stat().st_size, "sha256": verify.sha256(zig)},
        "guard": {"path": str(verify.GUARD_PATH), "sha256": verify.GUARD_SHA256},
        "source": source,
        "configured_budget_seconds": budget,
        "outer_deadline_slop_seconds": OUTER_SLOP_SECONDS,
        "forwarded_signal_grace_seconds": SIGNAL_GRACE_SECONDS,
        "direct_child_rss_limit_bytes": 4 << 30,
        "captures": {"stdout": {"path": str(stdout_path)}, "stderr": {"path": str(stderr_path)}},
        "caps": {
            "sampled_stop_threshold_bytes_each": verify.STREAM_CAP,
            "final_acceptance_limit_bytes_each": verify.STREAM_CAP,
        },
    }
    receipt_path.write_text(json.dumps(pending, indent=2, sort_keys=True) + "\n")
    outer_deadline = time.monotonic() + budget + OUTER_SLOP_SECONDS
    with stdout_path.open("wb", buffering=0) as stdout, stderr_path.open("wb", buffering=0) as stderr:
        result = guard.supervise(
            budget,
            command,
            cwd=TOOLCHAIN,
            env=env,
            stdout=stdout,
            stderr=stderr,
            policy=verify.output_policy(stdout, stderr),
            forwarded_signal_grace=SIGNAL_GRACE_SECONDS,
            outer_deadline=outer_deadline,
        )
    unsafe = verify.unsafe_result(result, [])
    if unsafe:
        failed = {
            **pending,
            "state": "INCOMPLETE",
            **verify.result_fields(result),
            "captures": {
                "stdout": verify.observed_capture(stdout_path),
                "stderr": verify.observed_capture(stderr_path),
            },
            "unsafe_outcome": unsafe,
            "passed": False,
        }
        receipt_path.write_text(json.dumps(failed, indent=2, sort_keys=True) + "\n")
        raise SystemExit(f"unsafe final regression outcome in {name}: {'; '.join(unsafe)}")
    stdout_size = stdout_path.stat().st_size
    stderr_size = stderr_path.stat().st_size
    if stdout_size > verify.STREAM_CAP or stderr_size > verify.STREAM_CAP:
        failed = {
            **pending,
            "state": "failed",
            **verify.result_fields(result),
            "captures": {
                "stdout": {"path": str(stdout_path), "bytes": stdout_size, "final": True},
                "stderr": {"path": str(stderr_path), "bytes": stderr_size, "final": True},
            },
            "failure": "a final capture exceeds the 16 MiB acceptance limit",
            "passed": False,
        }
        receipt_path.write_text(json.dumps(failed, indent=2, sort_keys=True) + "\n")
        raise SystemExit(f"final regression capture overflow in {name}")
    actual_stdout = stdout_path.read_bytes()
    actual_stderr = stderr_path.read_bytes()
    passed = result.child_exit == 0
    receipt = {
        **pending,
        "state": "finished",
        **verify.result_fields(result),
        "captures": {
            "stdout": {"path": str(stdout_path), "bytes": len(actual_stdout), "sha256": verify.sha256_bytes(actual_stdout), "final": True},
            "stderr": {"path": str(stderr_path), "bytes": len(actual_stderr), "sha256": verify.sha256_bytes(actual_stderr), "final": True},
        },
        "expected_exit": 0,
        "passed": passed,
    }
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    return {"case": name, "passed": passed, "receipt": str(receipt_path)}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zig", required=True)
    parser.add_argument("--artifacts", required=True)
    args = parser.parse_args()
    zig = checked_zig(args.zig)
    destination = Path(args.artifacts).resolve()
    if destination.exists():
        raise SystemExit(f"refusing to overwrite artifact directory: {destination}")
    destination.mkdir(parents=True)
    guard = verify.load_guard()
    source = verify.source_identity()
    summary = []
    for number, (name, budget, tail) in enumerate(COMMANDS, 1):
        recorded = run_one(number, name, budget, tail, zig, destination, guard, source)
        summary.append(recorded)
        if not recorded["passed"]:
            break
    (destination / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return 0 if len(summary) == len(COMMANDS) and all(item["passed"] for item in summary) else 1


if __name__ == "__main__":
    raise SystemExit(main())
