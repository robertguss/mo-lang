"""Read-only scope, generated-record and evidence inspection against the exact base, and the one
source/ID/evidence manifest of the frozen tip. Usage: scope.py [MANIFEST_NAME]"""
import hashlib
import json
import re
import subprocess
import sys

from common import AGENT, EVIDENCE, HERE, ROOT

BASE = '030290b8918e356be5588da2b12ad4e494aeac00'
TEST_DIR = 'examples/programs/agent/tests/application-workspace-v1/'
OWNED = {'agent/' + n + '.mo' for n in ['application', 'workspace-adapter', 'run', 'main', 'report']}
OWNED_TESTS = {'agent/tests/application-workspace-v1/' + n for n in ['driver.mo', 'boundaries.mo']}
GENERATED = {'agent/' + n + '.mo' for n in ['registry', 'server', 'check', 'coding-fixture', 'runs']} | {
    'agent/tests/coding-fixture-v1/boundaries.mo'}
IDS = 'examples/programs/.mo.ids'


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def blocks(text):
    """Each aggregate record exactly as written, by path."""
    starts = list(re.finditer(r'^    \{\n      "path": "([^"]+)"', text, re.M))
    end = text.rfind('\n  ]')
    return {m.group(1): text[m.start():starts[i + 1].start() if i + 1 < len(starts) else end].rstrip(',\n ')
            for i, m in enumerate(starts)}


checks, facts = {}, {}
head = git('rev-parse', 'HEAD').decode().strip()
checks['base_is_ancestor'] = subprocess.run(['git', 'merge-base', '--is-ancestor', BASE, 'HEAD'], cwd=ROOT).returncode == 0
changed = git('diff', '--name-only', BASE, 'HEAD').decode().split()
dirty = git('status', '--porcelain', '--untracked-files=all').decode().splitlines()
facts['uncommitted'] = dirty
allowed = lambda p: p == IDS or p.removeprefix('examples/programs/') in OWNED or p.startswith(TEST_DIR)
checks['paths_in_scope'] = all(allowed(p) for p in changed)
facts['out_of_scope'] = [p for p in changed if not allowed(p)]
old_raw, new_raw = git('show', f'{BASE}:{IDS}').decode(), (ROOT / IDS).read_text()
old = {f['path']: f for f in json.loads(old_raw)['files']}
new = {f['path']: f for f in json.loads(new_raw)['files']}
records = sorted(k for k in old.keys() | new.keys() if old.get(k) != new.get(k))
facts['changed_records'] = records
checks['records_owned_or_generated'] = set(records) <= OWNED | OWNED_TESTS | GENERATED
for name in GENERATED:
    same = (ROOT / 'examples/programs' / name).read_bytes() == git('show', f'{BASE}:examples/programs/{name}')
    checks['identical:' + name] = same
    if name in records:
        checks['declarations:' + name] = old[name]['declarations'] == new[name]['declarations']
a, b = blocks(old_raw), blocks(new_raw)
unrelated = set(a) - set(records)
checks['unrelated_records_verbatim'] = all(a[k] == b.get(k) for k in unrelated)
facts['unrelated_records'] = len(unrelated)
owned_mo = sorted(str(p.relative_to(ROOT)) for p in HERE.rglob('*.mo'))
checks['no_mo_in_evidence'] = not any('/evidence/' in p for p in owned_mo)
checks['only_positive_drivers'] = owned_mo == sorted(TEST_DIR + n for n in ['boundaries.mo', 'driver.mo'])
sizes = {p.name: p.stat().st_size for p in EVIDENCE.iterdir() if p.is_file()}
total = sum(sizes.values())
facts['evidence_bytes'] = total
checks['evidence_under_2MiB'] = total < 2 * 1024 * 1024
passed = all(checks.values())
report = dict(base=BASE, head=head, passed=passed, checks=checks, facts=facts)
if len(sys.argv) > 1:
    tracked = git('ls-files', 'examples/programs').decode().split()
    sources = sorted(p for p in tracked if p.removeprefix('examples/programs/') in OWNED | OWNED_TESTS | GENERATED
                     or (p.startswith(TEST_DIR) and not p.startswith(TEST_DIR + 'evidence/')) or p == IDS)
    report['manifest'] = dict(
        sources={p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sources},
        records={k: new[k]['verified']['hash'] for k in records if k in new and 'verified' in new[k]},
        evidence={n: hashlib.sha256((EVIDENCE / n).read_bytes()).hexdigest() for n in sorted(sizes)})
    out = EVIDENCE / (sys.argv[1] + '.json')
    if out.exists():
        raise SystemExit(f'{out} exists')
    out.write_text(json.dumps(report, indent=1) + '\n')
print(json.dumps(dict(report, manifest=None) if 'manifest' in report else report, indent=1))
sys.exit(0 if passed else 1)
