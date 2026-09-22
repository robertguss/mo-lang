#!/usr/bin/env python3
"""Run moscope's CLI cases against golden stdout, stderr, and exit status.

usage: check.py [--mo MO | --native BINARY] [--bless] [NAME ...]

Each case runs in a fresh temporary directory holding a copy of what it searches, so every
path in the output is relative and stable. Expectations live in ../expected/<name>.stdout,
.stderr, and .status. They are goldens: --bless rewrites them from the program under test,
and every rewrite is reviewed as a diff before it is committed. The smoke and warning
goldens were written by hand before the program first ran them.
"""

import argparse
import os
import shutil
import stat
import subprocess
import sys
import tempfile

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(APP)))
EXPECTED = os.path.join(APP, "expected")
FIXTURES = os.path.join(APP, "fixtures")


def copy_fixtures(tmp):
    shutil.copytree(FIXTURES, os.path.join(tmp, "fixtures"), symlinks=True)


def case_root(*names):
    def setup(tmp):
        os.mkdir(os.path.join(tmp, "root"))
        for name in names:
            shutil.copy(os.path.join(FIXTURES, "cases", name), os.path.join(tmp, "root", name))
    return setup


def nested(levels):
    def setup(tmp):
        path = os.path.join(tmp, "root")
        for index in range(levels):
            path = os.path.join(path, f"d{index}")
        os.makedirs(path)
        with open(os.path.join(path, "deep.jsonl"), "w") as out:
            out.write('{"type":"user","sessionId":"deep","message":{"role":"user","content":"deep-needle"}}\n')
    return setup


def unreadable(tmp):
    root = os.path.join(tmp, "root")
    os.makedirs(os.path.join(root, "shut"))
    with open(os.path.join(root, "open.jsonl"), "w") as out:
        out.write('{"type":"user","sessionId":"open","message":{"role":"user","content":"shut-needle"}}\n')
    os.chmod(os.path.join(root, "shut"), 0)


def oversized(tmp):
    root = os.path.join(tmp, "root")
    os.mkdir(root)
    with open(os.path.join(root, "big.jsonl"), "w") as out:
        out.write('{"type":"user","sessionId":"big","message":{"role":"user","content":"big-needle kept"}}\n')
        out.write("x" * (32 * 1024 * 1024 + 1) + "\n")
        out.write('{"type":"user","sessionId":"big","message":{"role":"user","content":"big-needle after"}}\n')


def root_link(tmp):
    copy_fixtures(tmp)
    os.symlink(os.path.join("fixtures", "smoke"), os.path.join(tmp, "anchor"))


SMOKE = "fixtures/smoke"
CASES = [
    ("smoke-phrase", ["connection refused", SMOKE], copy_fixtures),
    ("smoke-all-words", ["connection refused", SMOKE, "--all-words"], copy_fixtures),
    ("smoke-tools", ["connection refused", SMOKE, "--include-tools"], copy_fixtures),
    ("no-match", ["definitely absent", SMOKE], copy_fixtures),
    ("warning-relaxed", ["needle", "fixtures/warnings/nonobject"], copy_fixtures),
    ("warning-nonobject", ["needle", "fixtures/warnings/nonobject", "--strict"], copy_fixtures),
    ("warning-missing-type", ["needle", "fixtures/warnings/missing-type", "--strict"], copy_fixtures),
    ("warning-nonstring-type", ["needle", "fixtures/warnings/nonstring-type", "--strict"], copy_fixtures),
    ("warning-unknown-conversation", ["needle", "fixtures/warnings/unknown-conversation", "--strict"], copy_fixtures),
    ("root-symlink-anchor", ["connection refused", "anchor"], root_link),
    ("eligibility-thinking", ["only-thinking-needle", "root"], case_root("eligibility.jsonl")),
    ("eligibility-meta", ["only-meta-needle", "root"], case_root("eligibility.jsonl")),
    ("eligibility-image-data", ["b25seS1pbWFnZS1uZWVkbGU", "root", "--include-tools"], case_root("eligibility.jsonl")),
    ("eligibility-tool-default", ["only-tool-needle", "root"], case_root("eligibility.jsonl")),
    ("eligibility-tool-opt-in", ["only-tool-needle", "root", "--include-tools"], case_root("eligibility.jsonl")),
    ("eligibility-result", ["only-result-needle", "root", "--include-tools"], case_root("eligibility.jsonl")),
    ("eligibility-punctuation-control", ["[A.B]", "root"], case_root("eligibility.jsonl")),
    ("eligibility-nonascii-exact", ["nonascii é", "root"], case_root("eligibility.jsonl")),
    ("identity-all-words", ["alpha omega", "root", "--all-words"], case_root("identity.jsonl")),
    ("identity-physical", ["physical fallback", "root"], case_root("identity.jsonl")),
    ("identity-kind", ["alpha omega", "root", "--all-words"], case_root("identity-kind.jsonl")),
    ("ordering", ["order-needle", "root"], case_root("ordering.jsonl")),
    ("malformed-middle", ["malformed-needle", "root"], case_root("malformed-middle.jsonl")),
    ("malformed-middle-strict", ["malformed-needle", "root", "--strict"], case_root("malformed-middle.jsonl")),
    ("malformed-tail", ["tail-needle", "root"], case_root("malformed-tail.jsonl")),
    ("unsupported", ["unsupported-needle", "root"], case_root("unsupported.jsonl")),
    ("tool-parts", ["read", "root", "--include-tools"], case_root("tool-parts.jsonl")),
    ("depth-24", ["deep-needle", "root"], nested(24)),
    ("depth-25", ["deep-needle", "root"], nested(25)),
    ("unreadable", ["shut-needle", "root"], unreadable),
    ("oversized-line", ["big-needle", "root"], oversized),
    ("usage-dash-query", ["--", "--no-verify", SMOKE], copy_fixtures),
    ("usage-unsupported", ["needle", SMOKE, "--regex"], copy_fixtures),
    ("usage-help", ["--help"], copy_fixtures),
]


def command(args, runner):
    if runner.native:
        return [runner.native, "search", *args]
    return [runner.mo, "run", os.path.join(APP, "main.mo"), "--", "search", *args]


def restore(tmp):
    for top, dirs, _ in os.walk(tmp):
        for name in dirs:
            path = os.path.join(top, name)
            if not os.path.islink(path):
                os.chmod(path, stat.S_IRWXU)


def run_case(name, args, setup, runner):
    tmp = tempfile.mkdtemp(prefix=f"moscope-{name}-")
    try:
        setup(tmp)
        done = subprocess.run(command(args, runner), cwd=tmp, capture_output=True, timeout=300)
    finally:
        restore(tmp)
        shutil.rmtree(tmp)
    return done.stdout, done.stderr, f"{done.returncode}\n".encode()


def expected(name):
    parts = []
    for suffix in ("stdout", "stderr", "status"):
        with open(os.path.join(EXPECTED, f"{name}.{suffix}"), "rb") as source:
            parts.append(source.read())
    return tuple(parts)


def bless(name, actual):
    for suffix, data in zip(("stdout", "stderr", "status"), actual):
        with open(os.path.join(EXPECTED, f"{name}.{suffix}"), "wb") as out:
            out.write(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--mo", default=os.path.join(REPO, "toolchain", "zig-out", "bin", "mo"))
    parser.add_argument("--native", help="a moscope binary from mo build, run instead of mo run")
    parser.add_argument("--bless", action="store_true", help="rewrite goldens from this run")
    parser.add_argument("names", nargs="*")
    runner = parser.parse_args()
    if os.geteuid() == 0:
        sys.exit("check.py: run as a non-root user so the unreadable-directory case can deny access")
    chosen = [case for case in CASES if not runner.names or case[0] in runner.names]
    failures = 0
    for name, args, setup in chosen:
        actual = run_case(name, args, setup, runner)
        if runner.bless:
            bless(name, actual)
            print(f"blessed {name}")
            continue
        wanted = expected(name)
        if actual == wanted:
            print(f"pass  {name}")
            continue
        failures += 1
        print(f"FAIL  {name}")
        for label, got, want in zip(("stdout", "stderr", "status"), actual, wanted):
            if got != want:
                print(f"  {label} differs:\n    want {want[:400]!r}\n    got  {got[:400]!r}")
    if runner.bless:
        print(f"blessed {len(chosen)}; review the diff of expected/ before committing")
        return
    print(f"{len(chosen) - failures} passed, {failures} failed")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
