"""Read-only cross-attempt closure after all lead acceptance work has stopped."""
import gzip
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import zlib

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUT = HERE / sys.argv[1]
OUT.mkdir(exist_ok=False)
names = ['local-01', 'busybox-01', 'application-01', 'regression-01', 'extra-01', 'full-01']
groups, tokens, attempts, incomplete, manifest = set(), [], [], [], {}
for name in names:
    directory, launch = HERE / name, HERE / ('launch-' + name)
    receipt = json.loads((launch / 'receipt.json').read_text())
    assert receipt['exit'] == 0 and not receipt['forced'] and not receipt['remaining']
    groups.update(receipt['groups'])
    statuses = [json.loads(p.read_text()) for p in directory.glob('*.status.json')]
    assert all(r['exit'] == r['expected_exit'] and not r['forced'] and not r['group_remaining'] for r in statuses)
    source = json.loads((directory / 'source-after.json').read_text())
    assert source['tracked_bytes_unchanged'] and not source['changed']
    size = sum(p.stat().st_size for d in (directory, launch) for p in d.rglob('*') if p.is_file())
    assert size <= 16 * 1024 * 1024
    attempts.append({'name': name, 'exit': receipt['exit'], 'seconds': receipt['finished'] - receipt['started'],
                     'groups': receipt['groups'], 'bytes': size, 'source': source})
    tokens.extend(json.loads(p.read_text())['token'].encode() for p in directory.rglob('capability.json'))
for name in names:
    for directory in (HERE / name, HERE / ('launch-' + name)):
        for path in directory.rglob('*'):
            if not path.is_file() or path.name == 'capability.json':
                continue
            raw = path.read_bytes()
            content = raw
            if path.suffix == '.gz':
                try:
                    content = gzip.decompress(raw)
                except EOFError:
                    decoder = zlib.decompressobj(31)
                    content = decoder.decompress(raw)
                    assert not decoder.eof and content.endswith(b'\n')
                    assert all(isinstance(json.loads(line), dict) for line in content.splitlines())
                    incomplete.append(str(path.relative_to(HERE)))
            assert not any(token in raw or token in content for token in tokens), str(path)
            manifest[str(path.relative_to(HERE))] = {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}
assert incomplete == ['busybox-01/live/owner-death/transport.jsonl.gz',
                      'application-01/live/owner-death/transport.jsonl.gz']
payload = {key: set() for key in ('runs', 'workspaces', 'cgroups')}
for name in ('busybox-01', 'application-01', 'regression-01', 'extra-01'):
    identity = json.loads((HERE / name / 'final-command.json').read_text())['input']
    for key in payload:
        payload[key].update(identity[key])
seed = {'executions': [{'name': value} for value in sorted(payload['runs'])],
        'workspaces': [{'workspace_id': value} for value in sorted(payload['workspaces'])],
        'cgroups': sorted(payload['cgroups'])}
(OUT / 'identities.json').write_text(json.dumps(seed, indent=2) + '\n')
argv = ['python3', '-B', str(ROOT / 'toolchain/bench/step36/guard.py'), '60', '--',
        'python3', '-B', str(HERE.parent / 'workspace-recovery/inventory.py'), str(OUT)]
with (OUT / 'stdout.txt').open('xb') as stdout, (OUT / 'stderr.txt').open('xb') as stderr:
    child = subprocess.Popen(argv, cwd=ROOT, stdout=stdout, stderr=stderr, start_new_session=True)
    (OUT / 'started.json').write_text(json.dumps({'group': child.pid, 'argv': argv}))
    try:
        code = child.wait(timeout=75)
    finally:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        child.wait(timeout=5)
groups.add(child.pid)
time.sleep(.1)
snapshot = subprocess.check_output(['ps', '-axo', 'pid=,pgid=,command='], text=True)
(OUT / 'processes.txt').write_text(snapshot)
remaining = [r for r in snapshot.splitlines() if len(r.split(None, 2)) == 3 and int(r.split(None, 2)[1]) in groups]
assert code == 0 and not remaining
actual = json.loads((OUT / 'final-command.json').read_text())['input']
assert all(set(actual[key]) == payload[key] for key in payload)
shared = subprocess.run(['docker', '--context', 'orbstack', 'ps', '-a', '--no-trunc', '--format', '{{json .}}'],
                        capture_output=True, text=True, timeout=15, check=True)
(OUT / 'shared.json').write_text(json.dumps({'stdout': shared.stdout, 'stderr': shared.stderr, 'exit': shared.returncode}))
current = sorted((json.loads(r)['ID'], json.loads(r)['State']) for r in shared.stdout.splitlines())
assert len(current) == 5
for name in ('busybox-01', 'application-01', 'regression-01', 'extra-01'):
    before = json.loads((HERE / name / 'shared-before.json').read_text())['stdout']
    assert sorted((json.loads(r)['ID'], json.loads(r)['State']) for r in before.splitlines()) == current
record = {'attempts': attempts, 'inventory_exit': code, 'identities': {k: len(v) for k, v in payload.items()},
          'all_groups': sorted(groups), 'remaining': remaining, 'shared5_unchanged': True,
          'private_capability_files_excluded': len(tokens), 'no_capability_in_retained_bytes': True,
          'incomplete_gzip_members': incomplete,
          'gzip_limit': 'Actual owner SIGKILL leaves no final gzip footer; five complete JSON rows recover in each. No claim about unreturned in-flight transport.',
          'manifest_entries': len(manifest)}
(OUT / 'MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n')
(OUT / 'receipt.json').write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps(record))
