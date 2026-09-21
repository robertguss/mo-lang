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


def usage_error(detail: str) -> bytes:
    usage = "usage: moscope search <query> <directory> [--all-words] [--include-tools]"
    return f"moscope: {detail}; {usage}\n".encode()


def module_output(names: list[str]) -> bytes:
    lines = [f'pass  test "{name}"\n' for name in names]
    lines.append(f"{len(names)} passed, 0 failed, 0 skipped\n")
    lines.append(
        f"verified: types, contracts, tests ({len(names)}), property (0 seeds), sim (not run)\n"
    )
    lines.append("          proven: not run\n")
    return "".join(lines).encode()


def existing_case(name: str, stem: str, args: list[str]) -> dict[str, object]:
    return {
        "name": name,
        "args": args,
        "exit": int(expected_bytes(f"expected/{stem}.status").strip()),
        "stdout": expected_bytes(f"expected/{stem}.stdout"),
        "stderr": expected_bytes(f"expected/{stem}.stderr"),
    }


def interpreter_cases(stage: Path, compiler: Path) -> list[dict[str, object]]:
    empty = stage / "inputs/empty"
    empty.mkdir(parents=True)
    no_lf = stage / "inputs/no-lf"
    crlf = stage / "inputs/crlf"
    no_lf.mkdir()
    crlf.mkdir()
    record = b'{"type":"user","sessionId":"s","message":{"role":"user","id":"m","content":"needle"}}'
    (no_lf / "case.jsonl").write_bytes(record)
    (crlf / "case.jsonl").write_bytes(record + b"\r\n")
    directory_case = stage / "inputs/directory-case"
    (directory_case / "candidate.jsonl").mkdir(parents=True)
    sparse = stage / "inputs/sparse"
    sparse.mkdir()
    with (sparse / "big.jsonl").open("wb") as output:
        output.truncate(67_108_865)
    fifo = stage / "inputs/fifo"
    fifo.mkdir()
    os.mkfifo(fifo / "special.jsonl")
    root_target = stage / "inputs/root-target"
    root_target.mkdir()
    (root_target / "case.jsonl").write_bytes(record + b"\n")
    root_link = stage / "inputs/root-link"
    root_link.symlink_to(root_target, target_is_directory=True)
    unreadable = stage / "inputs/unreadable"
    unreadable.mkdir()
    (unreadable / "readable.jsonl").write_bytes(record + b"\n")
    (unreadable / "secret.jsonl").write_bytes(record + b"\n")
    (unreadable / "shut").mkdir()
    (unreadable / "shut/hidden.jsonl").write_bytes(record + b"\n")
    (unreadable / "secret.jsonl").chmod(0)
    (unreadable / "shut").chmod(0)
    exact_line = stage / "inputs/exact-line"
    long_line = stage / "inputs/long-line"
    exact_line.mkdir()
    long_line.mkdir()
    prefix = b'{"type":"user","sessionId":"s","message":{"role":"user","id":"m","content":"needle'
    suffix = b'"}}'
    exact_record = prefix + (b"x" * (1_048_576 - len(prefix) - len(suffix))) + suffix
    (exact_line / "line.jsonl").write_bytes(exact_record + b"\n")
    (long_line / "line.jsonl").write_bytes(record + b"\n" + (b"x" * 1_048_577) + b"\n")
    invalid_utf8 = stage / "inputs/invalid-utf8"
    genuine_replacement = stage / "inputs/genuine-replacement"
    invalid_utf8.mkdir()
    genuine_replacement.mkdir()
    invalid_record = record.replace(b'needle"', b'needle \xff"')
    replacement_record = record.replace(b'needle"', "needle �\"".encode())
    (invalid_utf8 / "case.jsonl").write_bytes(invalid_record + b"\n")
    (genuine_replacement / "case.jsonl").write_bytes(replacement_record + b"\n")
    one = (
        "Session s — latest timestamp missing\n"
        "  user message m\n"
        "    case.jsonl:1 user text content[0]\n"
        "      needle\n"
        "1 matching messages.\n"
    ).encode()
    long_excerpt = "needle" + ("x" * 234) + "..."
    exact_line_output = (
        "Session s — latest timestamp missing\n"
        "  user message m\n"
        "    line.jsonl:1 user text content[0]\n"
        f"      {long_excerpt}\n"
        "1 matching messages.\n"
    ).encode()
    replacement_output = one.replace(b"      needle\n", b"      needle \\xEF\\xBF\\xBD\n")
    ordering_output = (
        "Session tie-a — latest 2026-09-21T11:00:00.123Z\n"
        "  user message tie-a\n    ordering.jsonl:5 user text content[0]\n      order-needle\n"
        "Session tie-b — latest 2026-09-21T11:00:00.123Z\n"
        "  user message tie-b\n    ordering.jsonl:6 user text content[0]\n      order-needle\n"
        "Session order-a — latest 2026-09-21T10:30:00Z\n"
        "  user message a-hit\n    ordering.jsonl:1 user text content[0]\n      order-needle\n"
        "Session order-b — latest 2026-09-21T10:30:00Z\n"
        "  user message b-hit\n    ordering.jsonl:4 user text content[0]\n      order-needle\n"
        "Session order-missing — latest timestamp missing\n"
        "  user message missing\n    ordering.jsonl:7 user text content[0]\n      order-needle\n"
        "5 matching messages.\n"
    ).encode()
    smoke = "examples/programs/moscope/fixtures/smoke"
    status2 = "examples/programs/moscope/fixtures/status2"
    cases = [
        existing_case("exact-phrase", "smoke-phrase", ["search", "connection refused", smoke]),
        existing_case(
            "exact-all-words", "smoke-all-words", ["search", "connection refused", smoke, "--all-words"]
        ),
        existing_case(
            "exact-tools", "smoke-tools", ["search", "connection refused", smoke, "--include-tools"]
        ),
        existing_case("exact-absent", "no-match", ["search", "definitely absent", smoke]),
        existing_case(
            "exact-nonobject", "status2-nonobject", ["search", "needle", f"{status2}/nonobject"]
        ),
        existing_case(
            "exact-missing-type", "status2-missing-type", ["search", "needle", f"{status2}/missing-type"]
        ),
        existing_case(
            "exact-nonstring-type",
            "status2-nonstring-type",
            ["search", "needle", f"{status2}/nonstring-type"],
        ),
        existing_case(
            "exact-unknown-conversation",
            "status2-unknown-conversation",
            ["search", "needle", f"{status2}/unknown-conversation"],
        ),
    ]
    cli = [
        ("usage-empty", [], "the first argument must be search"),
        ("usage-whitespace", ["search", " \t\n\u000b\u000c\r", str(empty)], "query is empty or ASCII whitespace only"),
        ("usage-wrong-command", ["find", "needle", str(empty)], "the first argument must be search"),
        ("usage-missing", ["search", "needle"], "search needs exactly one query and one directory"),
        ("usage-extra", ["search", "needle", str(empty), "extra"], "search needs exactly one query and one directory"),
        ("usage-empty-directory", ["search", "needle", ""], "directory is empty"),
        ("usage-duplicate-all", ["search", "needle", str(empty), "--all-words", "--all-words"], "duplicate --all-words"),
        ("usage-duplicate-tools", ["search", "needle", str(empty), "--include-tools", "--include-tools"], "duplicate --include-tools"),
        ("usage-control-option", ["search", "needle", str(empty), "--bad\x07"], "unsupported option --bad\\x07"),
        ("usage-query-4097", ["search", "x" * 4097, str(empty)], "query exceeds 4096 bytes"),
        ("usage-terms-65", ["search", "x " * 65, str(empty), "--all-words"], "--all-words query exceeds 64 terms"),
    ]
    for name, args, detail in cli:
        cases.append({"name": name, "args": args, "exit": 2, "stdout": b"", "stderr": usage_error(detail)})
    cases.extend(
        [
            {"name": "query-4096", "args": ["search", "x" * 4096, str(empty)], "exit": 1, "stdout": b"No matches.\n", "stderr": b""},
            {"name": "terms-64", "args": ["search", "x " * 64, str(empty), "--all-words"], "exit": 1, "stdout": b"No matches.\n", "stderr": b""},
            {"name": "phrase-65-terms", "args": ["search", "x " * 65, str(empty)], "exit": 1, "stdout": b"No matches.\n", "stderr": b""},
            {"name": "empty-root", "args": ["search", "needle", str(empty)], "exit": 1, "stdout": b"No matches.\n", "stderr": b""},
            {"name": "valid-no-lf", "args": ["search", "needle", str(no_lf)], "exit": 0, "stdout": one, "stderr": b""},
            {"name": "valid-crlf", "args": ["search", "needle", str(crlf)], "exit": 0, "stdout": one, "stderr": b""},
            existing_case("flags-before-positionals", "smoke-all-words", ["search", "--all-words", "connection refused", smoke]),
            existing_case("flags-combined-reversed", "smoke-tools", ["search", "--include-tools", "connection refused", smoke]),
            {"name": "missing-root", "args": ["search", "needle", str(stage / "inputs/missing")], "exit": 2, "stdout": b"No matches.\n", "stderr": b"moscope: incomplete: .: cannot list directory: missing or unsupported entry .\n"},
            {"name": "file-as-root", "args": ["search", "needle", str(root_target / "case.jsonl")], "exit": 2, "stdout": b"No matches.\n", "stderr": b"moscope: incomplete: .: cannot list directory: missing or unsupported entry .\n"},
            {"name": "directory-jsonl", "args": ["search", "needle", str(directory_case)], "exit": 2, "stdout": b"No matches.\n", "stderr": b"moscope: incomplete: candidate.jsonl: a .jsonl candidate is a directory, not a regular file\n"},
            {"name": "fifo-jsonl", "args": ["search", "needle", str(fifo)], "exit": 2, "stdout": b"No matches.\n", "stderr": b"moscope: incomplete: special.jsonl: cannot admit regular .jsonl input by size: missing or unsupported entry special.jsonl\n"},
            {"name": "sparse-64mib-plus-one", "args": ["search", "needle", str(sparse)], "exit": 2, "stdout": b"No matches.\n", "stderr": b"moscope: incomplete: big.jsonl: file exceeds 64 MiB\n"},
            {"name": "root-symlink", "args": ["search", "needle", str(root_link)], "exit": 0, "stdout": one, "stderr": b""},
            {"name": "unreadable-file-and-subtree-with-control", "args": ["search", "needle", str(unreadable)], "exit": 2, "stdout": one.replace(b"case.jsonl", b"readable.jsonl"), "stderr": b"moscope: incomplete: shut: cannot list directory: missing or unsupported entry .\nmoscope: incomplete: secret.jsonl: cannot read admitted .jsonl input: missing or unsupported entry secret.jsonl\n", "restore": [[str(unreadable / "secret.jsonl"), 0o600], [str(unreadable / "shut"), 0o700]]},
            {"name": "line-exact-1mib", "args": ["search", "needle", str(exact_line)], "exit": 0, "stdout": exact_line_output, "stderr": b"", "timeout_seconds": 90},
            {"name": "line-1mib-plus-one-retains-earlier", "args": ["search", "needle", str(long_line)], "exit": 2, "stdout": one.replace(b"case.jsonl", b"line.jsonl"), "stderr": b"moscope: incomplete: line.jsonl:2: a JSONL line exceeds 1 MiB\n", "timeout_seconds": 90},
            {"name": "invalid-utf8-conservative", "args": ["search", "needle", str(invalid_utf8)], "exit": 2, "stdout": replacement_output, "stderr": b"moscope: incomplete: case.jsonl:1: U+FFFD is present; fold_lines cannot distinguish it from replaced invalid UTF-8\n"},
            {"name": "genuine-replacement-conservative", "args": ["search", "needle", str(genuine_replacement)], "exit": 2, "stdout": replacement_output, "stderr": b"moscope: incomplete: case.jsonl:1: U+FFFD is present; fold_lines cannot distinguish it from replaced invalid UTF-8\n"},
            {"name": "ordering", "args": ["search", "order-needle", "examples/programs/moscope/fixtures/cases"], "exit": 2, "stdout": ordering_output, "stderr": b"moscope: incomplete: identity.jsonl:6: UUID id-conflict conflicts with line 5\nmoscope: incomplete: malformed-middle.jsonl:2: malformed JSON record\nmoscope: incomplete: malformed-tail.jsonl:2: malformed JSON record\nmoscope: incomplete: unsupported.jsonl:1: unsupported conversation block type future_content\nmoscope: incomplete: unsupported.jsonl:2: conversation content is neither text nor a block array\nmoscope: diagnostic: ignored 1 records of kind future_bookkeeping\nmoscope: diagnostic: ignored 1 records of kind progress\n"},
        ]
    )
    modules = {
        "limits": ["the documented limits are the production constants"],
        "model": ["empty production state starts every counter and stop flag clear"],
        "main": [
            "flags combine in either order and duplicate or unsupported arguments are rejected",
            "blank and oversized queries and malformed positional counts are usage errors",
            "all six ASCII separators are blank and query and term boundaries are exact",
            "flags are allowed around positionals while every missing duplicate and option shape rejects",
        ],
        "parse": [
            "decoded UUID equality ignores object order and JSON spelling",
            "file-local UUID state resets and malformed middle input retains neighboring messages",
            "replacement characters and conflicting payloads preserve first results but are incomplete",
            "production per-file total-record and retained-block counters refuse the next value",
        ],
        "scan": [
            "production discovery reads nested JSONL, ignores other files, and diagnoses JSONL folders",
            "production filesystem timeout and aggregate admission paths are incomplete",
            "processing expiry after a successful fold preserves admitted results",
        ],
        "search": [
            "ASCII folding leaves non-ASCII exact, and punctuation remains literal",
            "all-words uses exactly the six ASCII whitespace bytes",
            "safe output has no raw controls or non-ASCII bytes",
            "terminal safety covers NUL DEL and bidi while doubling backslash",
            "excerpt boundaries and output admission differ on both sides of the limit",
        ],
        "tests": [
            "a phrase stays inside one block while all words may span blocks of one logical message",
            "tool blocks are opt-in and thinking remains excluded",
            "an exact decoded duplicate UUID is removed and a conflicting payload is incomplete",
            "physical fallback identity cannot collide with a provided physical-looking id",
            "invalid top-level classification cases independently make a result incomplete",
            "unknown bookkeeping is counted, but unknown conversation shapes are incomplete",
        ],
    }
    for module, names in modules.items():
        cases.append(
            {
                "name": f"module-{module}",
                "command": [str(compiler), "test", str(APP / f"{module}.mo")],
                "exit": 0,
                "stdout": module_output(names),
                "stderr": b"",
                "timeout_seconds": 120,
            }
        )
    return cases


def run_interpreter(compiler: Path, destination: Path) -> int:
    if destination.exists():
        raise SystemExit(f"refusing to overwrite artifact directory: {destination}")
    destination.mkdir(parents=True)
    cases = interpreter_cases(destination, compiler)
    guard = load_guard()
    source = source_identity()
    summary = []
    for number, case in enumerate(cases, 1):
        case_dir = destination / f"{number:03d}-{case['name']}"
        case_dir.mkdir()
        home = case_dir / "home"
        (home / "tmp").mkdir(parents=True)
        stdout_path = case_dir / "stdout.raw"
        stderr_path = case_dir / "stderr.raw"
        receipt_path = case_dir / "receipt.json"
        command = case.get("command") or [str(compiler), "run", str(MAIN), "--", *case["args"]]
        pending = {
            "schema": "moscope-acceptance-v1",
            "state": "started",
            "case": case["name"],
            "argv": command,
            "cwd": str(ROOT),
            "environment": minimal_env(home),
            "compiler": {"path": str(compiler), "bytes": COMPILER_BYTES, "sha256": COMPILER_SHA256},
            "guard": {"path": str(GUARD_PATH), "sha256": GUARD_SHA256},
            "source": source,
            "captures": {"stdout": {"path": str(stdout_path)}, "stderr": {"path": str(stderr_path)}},
            "caps": {"sampled_stop_threshold_bytes_each": STREAM_CAP, "final_acceptance_limit_bytes_each": STREAM_CAP},
        }
        receipt_path.write_text(json.dumps(pending, indent=2, sort_keys=True) + "\n")
        with stdout_path.open("wb", buffering=0) as stdout, stderr_path.open("wb", buffering=0) as stderr:
            result = guard.supervise(
                case.get("timeout_seconds", 60), command, cwd=ROOT, env=pending["environment"],
                stdout=stdout, stderr=stderr, policy=output_policy(stdout, stderr),
            )
        fixture_cleanup = []
        for path, mode in case.get("restore", []):
            try:
                os.chmod(path, mode)
                fixture_cleanup.append({"path": path, "restored_mode": mode, "error": None})
            except OSError as error:
                fixture_cleanup.append({"path": path, "restored_mode": None, "error": f"{type(error).__name__}: {error}"})
        if result.group.state != "absent":
            failed = {**pending, "state": "INCOMPLETE", **result_fields(result), "fixture_cleanup": fixture_cleanup, "captures": {"stdout": observed_capture(stdout_path), "stderr": observed_capture(stderr_path)}, "passed": False}
            receipt_path.write_text(json.dumps(failed, indent=2, sort_keys=True) + "\n")
            raise SystemExit(f"unsafe cleanup in {case['name']}")
        stdout_size = stdout_path.stat().st_size
        stderr_size = stderr_path.stat().st_size
        if stdout_size > STREAM_CAP or stderr_size > STREAM_CAP:
            failed = {**pending, "state": "failed", **result_fields(result), "fixture_cleanup": fixture_cleanup, "captures": {"stdout": {"path": str(stdout_path), "bytes": stdout_size}, "stderr": {"path": str(stderr_path), "bytes": stderr_size}}, "failure": "final capture overflow", "passed": False}
            receipt_path.write_text(json.dumps(failed, indent=2, sort_keys=True) + "\n")
            raise SystemExit(f"capture overflow in {case['name']}")
        actual_stdout = stdout_path.read_bytes()
        actual_stderr = stderr_path.read_bytes()
        comparisons = {"status_exact": result.child_exit == case["exit"], "stdout_exact": actual_stdout == case["stdout"], "stderr_exact": actual_stderr == case["stderr"]}
        passed = all(comparisons.values()) and result.reason == "child_exit" and result.supervision_error is None
        receipt = {**pending, "state": "finished", **result_fields(result), "fixture_cleanup": fixture_cleanup, "captures": {"stdout": {"path": str(stdout_path), "bytes": len(actual_stdout), "sha256": sha256_bytes(actual_stdout), "final": True}, "stderr": {"path": str(stderr_path), "bytes": len(actual_stderr), "sha256": sha256_bytes(actual_stderr), "final": True}}, "expected": {"exit": case["exit"], "stdout_sha256": sha256_bytes(case["stdout"]), "stderr_sha256": sha256_bytes(case["stderr"])}, "comparisons": comparisons, "passed": passed}
        receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
        summary.append({"case": case["name"], "passed": passed, "receipt": str(receipt_path)})
    (destination / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return 0 if all(item["passed"] for item in summary) else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("plan")
    probe = subparsers.add_parser("probe")
    probe.add_argument("--mo", required=True)
    probe.add_argument("--artifacts", required=True)
    interpreter = subparsers.add_parser("interpreter")
    interpreter.add_argument("--mo", required=True)
    interpreter.add_argument("--artifacts", required=True)
    args = parser.parse_args()
    if args.command == "plan":
        print(json.dumps(PLAN, indent=2, sort_keys=True))
        return 0
    compiler = checked_compiler(args.mo)
    destination = Path(args.artifacts).resolve()
    if args.command == "probe":
        return run_probe(compiler, destination)
    return run_interpreter(compiler, destination)


if __name__ == "__main__":
    raise SystemExit(main())
