#!/usr/bin/env python3
"""Safe source/isolated-control-flow checks, NOT a jobq or hidden-suite run.
Run from repository root. No servers, agents, real process-killing or builds.
"""
import argparse
import ast
import contextlib
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[4]
SU = ROOT / 'mo-wiki/plans/erosion-round-suite'
source = (SU / 'defects6.py').read_text()
tree = ast.parse(source)
functions = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
result: dict = {'kind': 'static and explicitly mocked harness checks; no implementation results'}
result['defects6_sha256'] = hashlib.sha256(source.encode()).hexdigest()
result['shell_syntax'] = {}
for path in sorted(SU.glob('e6-*.sh')):
    p = subprocess.run(['bash', '-n', str(path)], capture_output=True, text=True, timeout=10)
    assert p.returncode == 0, p.stderr
    result['shell_syntax'][path.name] = p.returncode
result['check_call_sites_by_function'] = {
    name: sum(isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id == 'check'
              for n in ast.walk(fn))
    for name, fn in functions.items() if name.startswith('t_') or name == 'main'
}
result['check_call_sites_total'] = sum(result['check_call_sites_by_function'].values())
result['categories'] = [name[2:] for name in functions if name.startswith('t_')]

# Execute ONLY the real done_job helper with a FIFO model of t_sequence's s2
# queue after its first acknowledged job; the three older queued jobs remain.
events = []
ns = {
    'keyed': lambda *a, **k: (201, {'id': 'new-s2-late'}),
    'lease': lambda *a, **k: (200, {'id': 'older-s2-job'}),
    'ack': lambda *a, **k: events.append(['ack', *a]) or (200, {}),
}
exec(compile(ast.Module(body=[functions['done_job']], type_ignores=[]), str(SU/'defects6.py'), 'exec'), ns)
value = ns['done_job']('s2', 's2-late')
assert value is None and events == []
result['mock_fifo_sequence'] = {'helper_return': value, 'ack_calls': events,
                               'meaning': 'the newly created job is not acknowledged; the helper returns on the older FIFO lease'}

# Evaluate the original lost-ack expression against synthetic HTTP replies.
lost_node = next(n.value for n in ast.walk(functions['t_prunekill'])
                 if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'lost' for t in n.targets))
expr = compile(ast.Expression(lost_node), str(SU/'defects6.py'), 'eval')
reply = lambda *a, **k: (200, {'state': 'queued'})
lost = eval(expr, {'acked': {'acked-job'}, 'safe': reply})
assert lost == []
result['mock_lost_ack'] = {'reply': [200, {'state': 'queued'}], 'lost': lost,
                          'meaning': 'ack rollback to queued is not reported by this assertion'}

# Execute ONLY main, substituting every category with a failing mock.
passes, defects = [], []
ns = {'argparse': argparse, 'd8': SimpleNamespace(PASSES=passes, DEFECTS=defects),
      'subprocess': SimpleNamespace(run=lambda *a, **k: None)}
def check(name, condition, detail=''):
    (passes if condition else defects).append((name, detail))
ns['check'] = check
for name in functions:
    if name.startswith('t_'):
        ns[name] = lambda a, name=name: check(name, False, 'MOCK failure')
exec(compile(ast.Module(body=[functions['main']], type_ignores=[]), str(SU/'defects6.py'), 'exec'), ns)
import sys
original_argv = sys.argv
sys.argv = ['mock', '--serve', 'unused', '--verify', 'unused', '--compact', 'unused', '--prune', 'unused', '--bench', 'unused']
out = io.StringIO()
try:
    with contextlib.redirect_stdout(out):
        returned = ns['main']()
finally:
    sys.argv = original_argv
assert len(defects) == 7 and returned is None
result['mock_main_failures'] = {'defects': len(defects), 'return': returned, 'stdout': out.getvalue(),
                                'meaning': 'normal return despite failures; __main__ does not call sys.exit with a defect status'}

# Run the real shell suite() function in isolation. timeout/pkill/drain are
# shell stubs: timeout returns 124; no process is killed and no suite is run.
result['mock_wrapper_timeout'] = {}
for name in ['e6-suites.sh', 'e6-suites-mac.sh']:
    lines = (SU/name).read_text().splitlines()
    start = next(i for i, line in enumerate(lines) if line.startswith('suite()'))
    end = next(i for i in range(start+1, len(lines)) if lines[i] == '}')
    fn = '\n'.join(lines[start:end+1])
    with tempfile.TemporaryDirectory(prefix='auditor-wrapper-') as tmp:
        shell = '''OUT=$1; L=MOCK
 timeout() { printf 'MOCK timeout\n'; return 124; }
 pkill() { return 0; }
 drain() { return 0; }
 sysctl() { printf 'MOCK load\n'; }
''' + fn + '\nsuite example unused\n'
        p = subprocess.run(['bash', '-c', shell, 'mock', tmp], capture_output=True, text=True, timeout=10)
        result['mock_wrapper_timeout'][name] = {'exit': p.returncode, 'summary': (Path(tmp)/'e6-suites.out').read_text(),
                                                 'raw': (Path(tmp)/'e6-MOCK-example.txt').read_text()}
        assert p.returncode == 0

result['program7_seal_unchanged'] = subprocess.run(
    ['git', 'diff', '--quiet', '4176bd3f2161afdcdcff7cca5ca2fc0b44368af7',
     '64982b23b1dfed0bd0af3430125589da43058ac0', '--', 'mo-wiki/spec/programs/07-redis-subset.md'],
    cwd=ROOT).returncode == 0
print(json.dumps(result, indent=2, sort_keys=True))
