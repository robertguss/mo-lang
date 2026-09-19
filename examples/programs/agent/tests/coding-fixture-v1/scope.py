"""Read-only scope, generated-record and frozen-evidence inspection."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
from run import ROOT, HERE
BASE = '5f87021a754474b8d742f39b0965b3e10d777573'
OWNED = {'agent/'+name+'.mo' for name in ['coding-fixture','report','exact-edit','command-adapter','main','run','steps','tools','record','registry']}
GENERATED = {'agent/'+name+'.mo' for name in ['api','book','check','filing','runs','server','shelf','transcript','steps']}
BOUNDARY = 'agent/tests/coding-fixture-v1/boundaries.mo'

def at_base(path):
    return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)

old_raw = at_base('examples/programs/.mo.ids').decode()
new_raw = (ROOT/'examples/programs/.mo.ids').read_text()
old = {f['path']:f for f in json.loads(old_raw)['files']}
new = {f['path']:f for f in json.loads(new_raw)['files']}
changed = sorted(k for k in old.keys()|new.keys() if old.get(k)!=new.get(k))
assert set(changed) <= OWNED|GENERATED|{BOUNDARY}, changed
for name in GENERATED:
    assert (ROOT/'examples/programs'/name).read_bytes() == at_base('examples/programs/'+name), name
    if name in changed:
        assert old[name]['declarations'] == new[name]['declarations'], name
# Preserve every unrelated aggregate record verbatim, not just parsed values.
def blocks(text):
    starts=list(re.finditer(r'^    \{\n      "path": "([^"]+)"',text,re.M))
    return {m.group(1):text[m.start():starts[i+1].start() if i+1<len(starts) else text.rfind('\n  ]')].rstrip(',\n ') for i,m in enumerate(starts)}
a,b=blocks(old_raw),blocks(new_raw)
for name in a.keys()-set(changed): assert a[name]==b[name], name
paths = subprocess.check_output(['git','diff','--name-only',BASE],cwd=ROOT,text=True).splitlines()
paths += subprocess.check_output(['git','ls-files','--others','--exclude-standard'],cwd=ROOT,text=True).splitlines()
for path in paths:
    assert path=='examples/programs/.mo.ids' or path.removeprefix('examples/programs/') in OWNED or path.startswith('examples/programs/agent/tests/coding-fixture-v1/'),path
sizes = {p.name:p.stat().st_size for p in (HERE/'evidence').iterdir() if p.is_file()}
assert max(sizes.values()) < 16*1024*1024
source_paths = ['examples/programs/.mo.ids']+['examples/programs/'+p for p in sorted(OWNED|{BOUNDARY})]
print(json.dumps(dict(base=BASE,changed_records=changed,generated_only=sorted(set(changed)&GENERATED),
    unrelated_records_preserved=len(a)-len(set(changed)&a.keys()),source_sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in source_paths},
    fixture_sha256={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(HERE.glob("*.py"))},
    evidence_total_bytes=sum(sizes.values()),largest_evidence_bytes=max(sizes.values()),passed=True),indent=2))
