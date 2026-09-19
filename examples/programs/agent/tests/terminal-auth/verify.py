#!/usr/bin/env python3
"""Verify retained red/green evidence and the authorized source/ID boundaries."""
import hashlib
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[5]
HERE = pathlib.Path(__file__).resolve().parent
BASE = "ff669fd52e93ccf6aa970b05082d842c471cb1c9"
CLOSURE_BASE = "bc784d87cc9c98f8c5a4978316c324129a69b1de"
DEPENDENCIES = {f"agent/{name}.mo" for name in
                ("tools", "steps", "run", "registry", "server", "check", "main", "runs")}
DRIVER = "agent/tests/terminal-auth/driver.mo"

def base(path, revision=BASE):
    return subprocess.check_output(["git", "show", f"{revision}:{path}"], cwd=ROOT)

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
    after = json.loads(base(path, CLOSURE_BASE))
    assert {f['path']: f for f in before['files'] if f['path'] != owned} == {
        f['path']: f for f in after['files'] if f['path'] != owned}
actual_diff = subprocess.check_output(["git", "diff", BASE, CLOSURE_BASE, "--",
    "examples/programs/.mo.ids", "examples/recipes/.mo.ids"], cwd=ROOT)
assert actual_diff == (HERE / "evidence/generated-ids.diff").read_bytes()
# The original artifact remains immutable; v2 records only the authorized closure.
closure_diff = subprocess.check_output(["git", "diff", CLOSURE_BASE, "--",
    "examples/programs/.mo.ids"], cwd=ROOT)
assert closure_diff == (HERE / "evidence/generated-ids-v2.diff").read_bytes()
path = "examples/programs/.mo.ids"
before = {f['path']: f for f in json.loads(base(path, CLOSURE_BASE))['files']}
after = {f['path']: f for f in json.loads((ROOT / path).read_text())['files']}
assert set(after) - set(before) == {DRIVER}
assert set(before) - set(after) == set()
assert {k for k in before if before[k] != after[k]} == DEPENDENCIES
for key in DEPENDENCIES:
    old_record, new_record = before[key], after[key]
    assert {k: v for k, v in old_record.items() if k != 'verified'} == {
        k: v for k, v in new_record.items() if k != 'verified'}
    old_verified, new_verified = old_record['verified'], new_record['verified']
    assert {k: v for k, v in old_verified.items() if k != 'uses'} == {
        k: v for k, v in new_verified.items() if k != 'uses'}
    old_uses = {u['module']: u for u in old_verified['uses']}
    new_uses = {u['module']: u for u in new_verified['uses']}
    assert old_uses.keys() == new_uses.keys()
    assert {k for k in old_uses if old_uses[k] != new_uses[k]} == {'Agent.Model'}
    source = 'examples/programs/' + key
    assert base(source, CLOSURE_BASE) == (ROOT / source).read_bytes()
source = 'examples/programs/' + DRIVER
assert (ROOT / source).read_bytes() == base(source, CLOSURE_BASE) + (
    b'\nverified: types, contracts, tests (0), property (0 seeds), sim (not run)\n'
    b'          proven: not run\n')
assert (ROOT / 'examples/recipes/.mo.ids').read_bytes() == base('examples/recipes/.mo.ids', CLOSURE_BASE)
prior_evidence = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only',
    CLOSURE_BASE, 'examples/programs/agent/tests/terminal-auth/evidence'], cwd=ROOT, text=True).splitlines()
for path in prior_evidence:
    assert (ROOT / path).read_bytes() == base(path, CLOSURE_BASE)
closure_runs = records('dependency-checks-v2-1.jsonl')
assert len(closure_runs) == 38 and all(r['exit_code'] == 0 for r in closure_runs)
for name in ['tools', 'run', 'server', 'runs']:
    row = next(r for r in closure_runs if r['name'] == 'write-' + name)
    assert row['command'][7:9] == ['--sim', '100']
    assert 'sim (100 runs' in row['stdout']

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
allowed = {"examples/programs/" + p for p in DEPENDENCIES} | {"examples/programs/.mo.ids", "examples/recipes/.mo.ids",
           "examples/programs/agent/model.mo", "examples/recipes/agent-model-client-v1.mo"}
assert all(p in allowed or p.startswith("examples/programs/agent/tests/terminal-auth/") for p in changed + untracked)
print(json.dumps(dict(base=BASE, generic_recipe_sha256=hashlib.sha256(generic).hexdigest(),
    generic_recipe_byte_identical=True, generic_tests_preserved_verbatim=True,
    generated_ids_exact_diff=True, generated_ids_v2_exact_diff=True,
    dependency_records_changed=8, driver_record_added=True, dependency_behavior_unchanged=True,
    preserved_sim100_modules=4, prior_evidence_files_unchanged=len(prior_evidence),
    unrelated_id_records_unchanged=True,
    red_reproduced=True, interpreter_passed=9, compiled_passed=9,
    fixture_servers_closed=18, source_allowlist=True), indent=2))
