"""hostile.py: step-40 / test_workspace.py cases against the Mo server's real workspace.
Lexical escapes, a symlink at the last and a middle component, a hardlink, a FIFO,
setuid, and exact_edit with missing / multiple / empty matches leaving bytes unchanged.
Every socket read and write has a deadline. Run under the step-36 guard."""
import json
import os
import socket
import stat
import sys
import tempfile
import time
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


def refused(bridge, operation, args, error, call_id):
    status, r = call(bridge, operation, args, call_id)
    assert (status, r['state'], r['execution'], r['error'], r['result']) == (
        200, 'refusal', 'completed', error, None), (operation, args, r)
    assert 'secret' not in json.dumps(r)


def main():
    tmp = tempfile.TemporaryDirectory()
    b = local.Served(
        'run-1', Path(tmp.name) / '0', {'scenario': b'', 'answer': b'aaa\n'},
        selection={'policy': 'x', 'image': 'x', 'toolchain': None},
        verifier={'script': 'protected', 'checks': [], 'seconds': 1},
    )
    data = b.directory / 'workspace/data'
    (b.directory / 'workspace/outside').write_bytes(b'secret\n')
    os.symlink(b.directory / 'workspace/outside', data / 'link')
    os.symlink(b.directory / 'workspace', data / 'dirlink')
    os.link(data / 'answer', data / 'hard')
    os.mkfifo(data / 'fifo')
    (data / 'suid').write_bytes(b'x')
    os.chmod(data / 'suid', 0o4755)
    b.start()
    try:
        for i, path in enumerate(('link', 'dirlink/outside')):
            refused(b, 'read_file', {'path': path}, 'filesystem_refusal', f'link{i}')
        refused(b, 'read_file', {'path': 'fifo'}, 'filesystem_refusal', 'fifo')
        refused(b, 'read_file', {'path': 'hard'}, 'unsupported_entry', 'hard')
        # A tree holding a link, a FIFO, a hardlink or setuid refuses every walk,
        # including write_file, which inventories before it looks at the path.
        for i, op in enumerate(('list_files', 'search', 'write_file')):
            args = {'path': 'answer', 'text': 'x'} if op == 'write_file' else (
                {} if op == 'list_files' else {'query': 'a'})
            status, r = call(b, op, args, f'walk{i}')
            assert r['state'] == 'refusal' and r['result'] is None, (op, r)
            assert r['error'] in ('filesystem_refusal', 'unsupported_entry', 'unsupported_mode'), (op, r)
        assert (b.directory / 'workspace/outside').read_bytes() == b'secret\n'
        assert (data / 'answer').read_bytes() == b'aaa\n'
        assert stat.S_ISFIFO((data / 'fifo').stat().st_mode)
        print('hostile: links, hardlink, fifo, setuid walk: ok', flush=True)
    finally:
        b.close()
        tmp.cleanup()

    tmp = tempfile.TemporaryDirectory()
    edit = local.Served(
        'run-1', Path(tmp.name) / '1', {'scenario': b'', 'answer': b'aaa\n'},
        selection={'policy': 'x', 'image': 'x', 'toolchain': None},
        verifier={'script': 'protected', 'checks': [], 'seconds': 1},
    )
    edit.start()
    try:
        before = (edit.directory / 'workspace/data/answer').read_bytes()
        for i, path in enumerate(('../escape', '/etc/passwd', 'a//b', 'a/./b', 'answer/..')):
            refused(edit, 'read_file', {'path': path}, 'invalid_path', f'lex{i}')
        refused(edit, 'write_file', {'path': '../outside', 'text': 'x'}, 'invalid_path', 'lexw')
        for old, error, cid in (('zzz', 'missing_match', 'e0'), ('a', 'multiple_matches', 'e1'),
                                ('', 'empty_old', 'e2')):
            refused(edit, 'exact_edit', {'path': 'answer', 'old_text': old, 'new_text': 'b'}, error, cid)
            assert (edit.directory / 'workspace/data/answer').read_bytes() == before
        _, r = call(edit, 'read_file', {'path': 'answer'}, 'after')
        assert r['result']['text'] == 'aaa\n'
        print('hostile: lexical escapes and exact_edit leave bytes unchanged: ok', flush=True)
    finally:
        edit.close()
        tmp.cleanup()
    print('hostile: all ok', flush=True)


if __name__ == '__main__':
    main()
