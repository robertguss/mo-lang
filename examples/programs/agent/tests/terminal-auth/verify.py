#!/usr/bin/env python3
"""Verify retained red/green evidence and the authorized source/ID boundaries."""
import hashlib
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[5]
HERE = pathlib.Path(__file__).resolve().parent
BASE = "ff669fd52e93ccf6aa970b05082d842c471cb1c9"

def base(path):
    return subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=ROOT)

def records(path):
    return [json.loads(line) for line in (HERE / "evidence" / path).read_text().splitlines()]

path = "examples/recipes/model-client.mo"
generic = (ROOT / path).read_bytes()
assert base(path) == generic
new = (ROOT / "examples/recipes/agent-model-client-v1.mo").read_text()
old = generic.decode()
start = old.index('  test "the body')
end = old.index('\nend\n\nverified:', start)
assert old[start:end] in new
for path, owned in [("examples/programs/.mo.ids", "agent/model.mo"),
                    ("examples/recipes/.mo.ids", "agent-model-client-v1.mo")]:
    before = json.loads(base(path))
    after = json.loads((ROOT / path).read_text())
    assert {f['path']: f for f in before['files'] if f['path'] != owned} == {
        f['path']: f for f in after['files'] if f['path'] != owned}
actual_diff = subprocess.check_output(["git", "diff", BASE, "--",
    "examples/programs/.mo.ids", "examples/recipes/.mo.ids"], cwd=ROOT)
assert actual_diff == (HERE / "evidence/generated-ids.diff").read_bytes()
red = records("red-3.jsonl")[0]
assert red['exit_code'] == 0 and not red['passed']
assert red['stdout'].strip() == 'Answer(7,5)'
assert [r['status'] for r in red['requests']] == [401, 200]
for name in ["green-interpreter-3.jsonl", "green-compiled-2.jsonl"]:
    rows = records(name)
    assert len(rows) == 9
    assert all(r['passed'] and r['exit_code'] == 0 and r['server_closed'] for r in rows)
    assert [len(r['requests']) for r in rows] == [1, 2, 2, 2, 3, 1, 0, 1, 1]
assert all(r['exit_code'] == 0 for r in records("checks-1.jsonl"))
changed = subprocess.check_output(["git", "diff", BASE, "--name-only"], cwd=ROOT, text=True).splitlines()
untracked = subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard"], cwd=ROOT, text=True).splitlines()
allowed = {"examples/programs/.mo.ids", "examples/recipes/.mo.ids",
           "examples/programs/agent/model.mo", "examples/recipes/agent-model-client-v1.mo"}
assert all(p in allowed or p.startswith("examples/programs/agent/tests/terminal-auth/") for p in changed + untracked)
print(json.dumps(dict(base=BASE, generic_recipe_sha256=hashlib.sha256(generic).hexdigest(),
    generic_recipe_byte_identical=True, generic_tests_preserved_verbatim=True,
    generated_ids_exact_diff=True, unrelated_id_records_unchanged=True,
    red_reproduced=True, interpreter_passed=9, compiled_passed=9,
    fixture_servers_closed=18, source_allowlist=True), indent=2))
