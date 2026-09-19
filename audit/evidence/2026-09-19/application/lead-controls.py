"""Independent cold snapshot build with a spaced build path and Unicode input."""
import json
from pathlib import Path
import sys
import uuid

ROOT = Path(__file__).resolve().parents[4]
EXECUTOR = ROOT / 'toolchain/harness/executor'
sys.path[:0] = [str(EXECUTOR), str(EXECUTOR / 'application')]
from workspace import Workspace
from fixtures import load

out = Path(sys.argv[1])
out.mkdir(exist_ok=False)
mapping, _, source = load(out / 'source')
(out / 'source-receipt.json').write_text(json.dumps(source, indent=2))
w = Workspace(uuid.uuid4().hex, out / 'workspace', policy='application-build-v1',
              image=sys.argv[2], toolchain=sys.argv[3])
try:
    w.create(mapping)
    frozen = w.freeze()
    script = '''set -eu
test -z "$(ls -A /build)"
mkdir '/build/space dir'
cd '/build/space dir'
mo build /workspace/hello.mo >/build/compiler.log 2>&1 || { rc=$?; cat /build/compiler.log >&2; exit "$rc"; }
cat /build/compiler.log >&2
'./zig-out/mo-build/hello/hello' 'Zoë 🌙'
if echo mutation >> /workspace/hello.mo; then exit 1; fi
'''
    checks = [{'id': 'unicode-greeting', 'stream': 'stdout', 'mode': 'exact',
               'expected': 'Hello, Zoë 🌙!\n'}]
    result = w.verify(script, checks, seconds=120)
    (out / 'observations.json').write_text(json.dumps({'frozen': frozen, 'result': result}, indent=2))
    assert result['passed'] and result['execution_valid'], result['state']
    assert result['manifest']['workspace']['readonly'] is True
    assert result['manifest']['workspace']['snapshot'] == frozen['snapshot']
    assert result['manifest']['image'] == sys.argv[2]
    assert result['manifest']['toolchain'] == sys.argv[3]
    assert result['observation']['counters']['memory.events:oom_kill'] == 0
    print(json.dumps({'passed': 1, 'expected': 1, 'readonly': True,
                      'memory_peak': result['observation']['counters']['memory.peak']}), flush=True)
finally:
    if w.active:
        w.cancel()
        w.collect()
    deleted = w.delete()
    (out / 'deletion.json').write_text(json.dumps(deleted, indent=2))
