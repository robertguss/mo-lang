"""timings.py: best of five, both Mo runtimes and the Python service on loopback.
A read_file of 1 KiB and of 60 KiB, a search over 200 files, and 1,000 sequential
small list_files. Load average is printed beside the table. Every socket has a
deadline. Run under the step-36 guard. Named timings.py so it does not shadow
the stdlib `numbers` module (a file named numbers.py cannot import statistics)."""
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'toolchain/harness/executor'))
sys.path.insert(0, str(ROOT / 'toolchain/harness/executor/workspace_http'))
os.chdir(ROOT)

from remote import IMAGE, WORKSPACE_POLICY
from workspace_http import client
from workspace_http import protocol as wire
import local


def loadavg():
    return Path('/proc/loadavg').read_text().split()[:3]


def call(bridge, operation='list_files', args=None, call_id='c', timeout=8):
    req = client.request(bridge, operation, args or {}, call_id)
    raw = wire.encode(req) + b'\n'
    conn = client.connect(bridge, raw, timeout=timeout)
    conn.settimeout(timeout)
    return client.response(conn, timeout)


def once(bridge, kind):
    started = time.perf_counter()
    if kind == 'read-1k':
        status, r = call(bridge, 'read_file', {'path': 'onek'}, 'read1k')
        assert status == 200 and r['state'] == 'success' and len(r['result']['text']) == 1024
    elif kind == 'read-60k':
        status, r = call(bridge, 'read_file', {'path': 'sixty'}, 'read60k')
        assert status == 200 and r['state'] == 'success'
    elif kind == 'search-200':
        status, r = call(bridge, 'search', {'query': 'needle', 'path': 'tree'}, 'search')
        assert status == 200 and r['state'] == 'success'
    elif kind == 'seq-16':
        for i in range(16):
            status, r = call(bridge, 'list_files', {}, f's{i}')
            assert status == 200 and r.get('accepted') is True
    elif kind == 'seq-1000':
        # The contract admits 16 calls per run. 1,000 requests on one run: the
        # first 16 are admitted, the rest are call_limit. Timed as sequential
        # wire requests, not as 1,000 admitted operations.
        for i in range(1000):
            status, r = call(bridge, 'list_files', {}, f's{i}')
            assert status in (200, 409)
    else:
        raise ValueError(kind)
    return time.perf_counter() - started


def best_of_five(make_bridge, kind):
    times = []
    for i in range(5):
        b = make_bridge(f'{kind}-{i}')
        try:
            times.append(once(b, kind))
        finally:
            b.close(seconds=8)
    return min(times), times


def python_bridge(name, files):
    tmp = Path(tempfile.mkdtemp(prefix='ws-py-'))
    local.TARGET = None
    b = local.Bridge(
        'run-1', tmp / name, {'scenario': b'', **files},
        selection={'policy': WORKSPACE_POLICY, 'image': IMAGE, 'toolchain': None},
        verifier={'script': 'protected',
                  'checks': [{'id': 'protected', 'stream': 'stdout', 'mode': 'exact', 'expected': 'ok'}],
                  'seconds': 1},
    )
    b.start(owner_module='workspace_http.test_owner')
    return b


def mo_bridge(name, files, target):
    tmp = Path(tempfile.mkdtemp(prefix='ws-mo-'))
    local.TARGET = target
    b = local.Served(
        'run-1', tmp / name, {'scenario': b'', **files},
        selection={'policy': 'x', 'image': 'x', 'toolchain': None},
        verifier={'script': 'protected', 'checks': [], 'seconds': 1},
    )
    b.start()
    return b


def files_for():
    tree = {f'tree/{i:03}': b'needle in file\n' for i in range(200)}
    return {'onek': b'x' * 1024, 'sixty': b'y' * (60 * 1024), **tree}


def main():
    print('loadavg', ' '.join(loadavg()), flush=True)
    ps = subprocess.run(['ps', '-eo', 'pid,etimes,pcpu,args', '--sort=-pcpu'],
                        capture_output=True, text=True)
    print('ps-top', '\n'.join(ps.stdout.splitlines()[:8]), flush=True)
    files = files_for()
    kinds = ('read-1k', 'read-60k', 'search-200', 'seq-16', 'seq-1000')
    runtimes = {
        'python': lambda name: python_bridge(name, files),
        'mo-run': lambda name: mo_bridge(name, files,
            'python3 toolchain/bench/step36/guard.py 180 -- '
            'toolchain/zig-out/bin/mo run examples/programs/workspace-server/double.mo --'),
        'mo-build': lambda name: mo_bridge(name, files,
            'python3 toolchain/bench/step36/guard.py 180 -- '
            'zig-out/mo-build/workspace-server-double/workspace-server-double'),
    }
    table = {}
    for runtime, maker in runtimes.items():
        table[runtime] = {}
        for kind in kinds:
            print(f'{runtime} {kind} ...', flush=True)
            best, all_times = best_of_five(maker, kind)
            table[runtime][kind] = {'best_s': round(best, 4), 'all_s': [round(t, 4) for t in all_times]}
            print(f'  best {best:.4f}s  all {all_times}', flush=True)
    print('loadavg-end', ' '.join(loadavg()), flush=True)
    print(json.dumps(table, indent=2), flush=True)


if __name__ == '__main__':
    main()
