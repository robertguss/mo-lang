#!/usr/bin/env python3
"""Serial, fail-closed moscope acceptance recorder.

The initial executable stage is deliberately one case. Its raw report must be
reviewed before the broader manifest is implemented and run.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
from typing import BinaryIO


APP = Path(__file__).resolve().parents[1]
ROOT = APP.parents[2]
MAIN = APP / "main.mo"
GUARD_PATH = ROOT / "toolchain/bench/step36/guard.py"
COMPILER_SHA256 = "3ef07d08ed6d0c802a2597bd956579873851855961cf2e5f01cf87018d273b78"
COMPILER_BYTES = 15_849_056
GUARD_SHA256 = "7a5eadf9794110efec179872b02833df8fb4a12a3ad8fb8244074f903a8d23c2"
STREAM_CAP = 16 << 20

PROBE = {
    "name": "existing-smoke-phrase",
    "timeout_seconds": 60,
    "args": ["search", "connection refused", "examples/programs/moscope/fixtures/smoke"],
    "stdout": "expected/smoke-phrase.stdout",
    "stderr": "expected/smoke-phrase.stderr",
    "status": "expected/smoke-phrase.status",
}

PLAN = {
    "serial": True,
    "direct_guard_api": True,
    "stream_cap_bytes_each": STREAM_CAP,
    "timeouts_seconds": {"cli": 60, "line": 90, "module_tests": 120, "native_build": 900},
    "review_gate": "probe report must be reviewed before broad execution",
    "stages": ["probe", "interpreter", "production-seams", "native", "release-metadata"],
    "probe": PROBE,
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def source_identity() -> dict[str, object]:
    records: list[dict[str, object]] = []

    def visit(folder: Path) -> None:
        for entry in sorted(os.scandir(folder), key=lambda item: item.name):
            path = Path(entry.path)
            relative = str(path.relative_to(APP))
            if entry.is_symlink():
                records.append({"path": relative, "type": "symlink", "target": os.readlink(path)})
            elif entry.is_dir(follow_symlinks=False):
                records.append({"path": relative, "type": "directory"})
                visit(path)
            elif entry.is_file(follow_symlinks=False):
                records.append(
                    {
                        "path": relative,
                        "type": "regular",
                        "bytes": entry.stat(follow_symlinks=False).st_size,
                        "sha256": sha256(path),
                    }
                )
            else:
                records.append({"path": relative, "type": "other"})

    visit(APP)
    encoded = json.dumps(records, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return {"tree_sha256": sha256_bytes(encoded), "entries": records}


def load_guard():
    if sha256(GUARD_PATH) != GUARD_SHA256:
        raise SystemExit("guard bytes do not match accepted dad7b374 guard")
    spec = importlib.util.spec_from_file_location("moscope_accepted_guard", GUARD_PATH)
    if spec is None or spec.loader is None:
        raise SystemExit("cannot load accepted guard")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def checked_compiler(value: str) -> Path:
    compiler = Path(value)
    if not compiler.is_absolute():
        raise SystemExit("--mo must be an absolute path; PATH lookup is forbidden")
    if not compiler.is_file() or compiler.stat().st_size != COMPILER_BYTES:
        raise SystemExit("compiler path is missing or has the wrong byte size")
    if sha256(compiler) != COMPILER_SHA256:
        raise SystemExit("compiler SHA-256 does not match the accepted binary")
    return compiler


def minimal_env(home: Path) -> dict[str, str]:
    zig = shutil.which("zig")
    linker_dir = str(Path(zig).resolve().parent) if zig else "/usr/bin"
    path = os.pathsep.join(dict.fromkeys([linker_dir, "/usr/bin", "/bin"]))
    return {
        "HOME": str(home),
        "TMPDIR": str(home / "tmp"),
        "PATH": path,
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8",
        "TZ": "UTC",
    }


def expected_bytes(relative: str) -> bytes:
    return (APP / relative).read_bytes()


def output_policy(stdout: BinaryIO, stderr: BinaryIO):
    def check(_payload, _now):
        if os.fstat(stdout.fileno()).st_size > STREAM_CAP:
            return "stdout_overflow"
        if os.fstat(stderr.fileno()).st_size > STREAM_CAP:
            return "stderr_overflow"
        return None

    return check


def observed_capture(path: Path) -> dict[str, object]:
    try:
        return {"path": str(path), "observed_bytes": path.stat().st_size, "final": False}
    except OSError as error:
        return {
            "path": str(path),
            "observed_bytes": None,
            "size_error": f"{type(error).__name__}: {error}",
            "final": False,
        }


def result_fields(result) -> dict[str, object]:
    return {
        "process_group": result.process_group,
        "termination": {"raw_returncode": result.child_returncode, "exit": result.child_exit},
        "guard_result": {
            "reason": result.reason,
            "rss_bytes": result.rss_bytes,
            "elapsed_seconds": result.elapsed_seconds,
            "supervision_error": result.supervision_error,
        },
        "cleanup": {
            "group_state": result.group.state,
            "rows": result.group.rows,
            "error": result.group.error,
            "accepted": result.group.state == "absent",
        },
    }


def run_probe(compiler: Path, destination: Path) -> int:
    if destination.exists():
        raise SystemExit(f"refusing to overwrite artifact directory: {destination}")
    destination.mkdir(parents=True)
    home = destination / "home"
    (home / "tmp").mkdir(parents=True)
    env = minimal_env(home)
    command = [str(compiler), "run", str(MAIN), "--", *PROBE["args"]]
    stdout_path = destination / "stdout.raw"
    stderr_path = destination / "stderr.raw"
    receipt_path = destination / "receipt.json"
    pending = {
        "schema": "moscope-acceptance-v1",
        "state": "started",
        "case": PROBE["name"],
        "argv": command,
        "cwd": str(ROOT),
        "environment": env,
        "compiler": {"path": str(compiler), "bytes": COMPILER_BYTES, "sha256": COMPILER_SHA256},
        "guard": {"path": str(GUARD_PATH), "sha256": GUARD_SHA256},
        "source": source_identity(),
        "captures": {
            "stdout": {"path": str(stdout_path)},
            "stderr": {"path": str(stderr_path)},
        },
        "caps": {
            "sampled_stop_threshold_bytes_each": STREAM_CAP,
            "final_acceptance_limit_bytes_each": STREAM_CAP,
        },
    }
    receipt_path.write_text(json.dumps(pending, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    guard = load_guard()
    with stdout_path.open("wb", buffering=0) as stdout, stderr_path.open("wb", buffering=0) as stderr:
        result = guard.supervise(
            PROBE["timeout_seconds"],
            command,
            cwd=ROOT,
            env=env,
            stdout=stdout,
            stderr=stderr,
            policy=output_policy(stdout, stderr),
        )
    if result.group.state != "absent":
        incomplete = {
            **pending,
            "state": "INCOMPLETE",
            **result_fields(result),
            "captures": {
                "stdout": observed_capture(stdout_path),
                "stderr": observed_capture(stderr_path),
            },
            "failure": "process group was not literally absent; captures are nonfinal",
            "passed": False,
        }
        receipt_path.write_text(json.dumps(incomplete, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(receipt_path)
        raise SystemExit("unsafe cleanup result: process group is not literally absent")
    stdout_size = stdout_path.stat().st_size
    stderr_size = stderr_path.stat().st_size
    if stdout_size > STREAM_CAP or stderr_size > STREAM_CAP:
        overflow = {
            **pending,
            "state": "failed",
            **result_fields(result),
            "captures": {
                "stdout": {"path": str(stdout_path), "bytes": stdout_size, "final": True},
                "stderr": {"path": str(stderr_path), "bytes": stderr_size, "final": True},
            },
            "failure": "a final capture exceeds the 16 MiB acceptance limit; streams were not read or hashed",
            "passed": False,
        }
        receipt_path.write_text(json.dumps(overflow, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(receipt_path)
        return 1
    actual_stdout = stdout_path.read_bytes()
    actual_stderr = stderr_path.read_bytes()
    expected_status = int(expected_bytes(PROBE["status"]).strip())
    comparisons = {
        "stdout_exact": actual_stdout == expected_bytes(PROBE["stdout"]),
        "stderr_exact": actual_stderr == expected_bytes(PROBE["stderr"]),
        "status_exact": result.child_exit == expected_status,
    }
    complete = {
        **pending,
        "state": "finished",
        **result_fields(result),
        "captures": {
            "stdout": {
                "path": str(stdout_path),
                "bytes": len(actual_stdout),
                "sha256": sha256_bytes(actual_stdout),
                "final": True,
            },
            "stderr": {
                "path": str(stderr_path),
                "bytes": len(actual_stderr),
                "sha256": sha256_bytes(actual_stderr),
                "final": True,
            },
        },
        "expected": {"exit": expected_status, "stdout": PROBE["stdout"], "stderr": PROBE["stderr"]},
        "comparisons": comparisons,
        "passed": all(comparisons.values())
        and result.reason == "child_exit"
        and result.supervision_error is None,
    }
    receipt_path.write_text(json.dumps(complete, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(receipt_path)
    return 0 if complete["passed"] else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("plan")
    probe = subparsers.add_parser("probe")
    probe.add_argument("--mo", required=True)
    probe.add_argument("--artifacts", required=True)
    args = parser.parse_args()
    if args.command == "plan":
        print(json.dumps(PLAN, indent=2, sort_keys=True))
        return 0
    return run_probe(checked_compiler(args.mo), Path(args.artifacts).resolve())


if __name__ == "__main__":
    raise SystemExit(main())
