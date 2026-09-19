"""observations.py: one admitted read_file, then operator close. Prints the four
journal observations (admission, execution, reply produced, delivery) and cleanup
as separate fields. Every socket read and write has a deadline. Run under the
step-36 guard."""
import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'toolchain/harness/executor'))
sys.path.insert(0, str(ROOT / 'toolchain/harness/executor/workspace_http'))
os.chdir(ROOT)

from workspace_http import client
from workspace_http import protocol as wire
import local

local.TARGET = os.environ.get(
    'MO_TARGET',
    'python3 toolchain/bench/step36/guard.py 60 -- '
    'toolchain/zig-out/bin/mo run examples/programs/workspace-server/double.mo --',
)


def call(bridge, operation, args, call_id, timeout=4):
    req = client.request(bridge, operation, args, call_id)
    raw = wire.encode(req) + b'\n'
    conn = client.connect(bridge, raw, timeout=timeout)
    conn.settimeout(timeout)
    return client.response(conn, timeout)


def main():
    tmp = tempfile.TemporaryDirectory()
    b = local.Served(
        'run-1', Path(tmp.name) / 'obs', {'scenario': b'', 'answer': b'aaa\n'},
        selection={'policy': 'x', 'image': 'x', 'toolchain': None},
        verifier={'script': 'protected', 'checks': [], 'seconds': 1},
    )
    b.start()
    try:
        status, r = call(b, 'read_file', {'path': 'answer'}, 'obs-1')
        assert status == 200 and r['state'] == 'success', r
        assert b.close()
        journal = json.loads((b.directory / 'owner.json').read_bytes())
        print(json.dumps(journal, indent=2), flush=True)
        call_row = journal['calls']['obs-1']
        print('OBSERVATION admission', call_row.get('admission'), 'intent', call_row.get('intent'),
              flush=True)
        print('OBSERVATION execution', call_row.get('execution'), 'result', call_row.get('result'),
              flush=True)
        print('OBSERVATION reply_produced', call_row.get('reply'), flush=True)
        print('OBSERVATION delivery', call_row.get('delivery'), flush=True)
        print('OBSERVATION cleanup', journal.get('cleanup'), flush=True)
        print('OBSERVATION binding', journal.get('binding'), flush=True)
    finally:
        if b.process is not None and b.process.poll() is None:
            b.stop_owner()
        tmp.cleanup()


if __name__ == '__main__':
    main()
