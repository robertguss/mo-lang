"""Local process test double only. Never imported by the production owner.

The five file tools run the real workspace_controller.handle against a local
directory standing in for the machine's workspace root, so path containment,
exact_edit matching and result bounds are the production code's. Commands,
freeze, verify and delete stay scripted: they need the machine.
"""
import base64
import json
import os
from pathlib import Path
import socket
import struct
import sys
import time
import uuid

from . import owner
from .owner import private_write, run
import workspace_controller as controller
import workspace_files as files


class WorkspaceDouble:
    def __init__(self, run_id, directory, **selection):
        self.directory = Path(directory)
        self.directory.mkdir(mode=0o700)
        self.run_id = run_id
        self.workspace_id = uuid.uuid4().hex
        self.active = None
        self.mode = ''
        private_write(self.directory / 'ownership.json', {'test_double': True})

    def create(self, source, **kwargs):
        self.mode = source.get('scenario', b'').decode()
        journal = json.loads((self.directory.parent / 'owner.json').read_bytes())
        assert journal['core_workspace_id'] == self.workspace_id
        assert journal['receipt_path'] == str(self.directory / 'ownership.json')
        assert journal['creation_call_id'] == kwargs['call_id']
        self.event('create')
        if self.mode == 'startup-failure':
            raise RuntimeError('private host failure')
        root = controller.root_for(self.workspace_id)
        (root / 'storage/data').mkdir(parents=True)
        with controller.data_fd(root / 'storage/data') as fd:
            for path, data in source.items():
                files.replace_file(fd, path, data, create=True)
        if self.mode == 'links':
            outside = self.directory / 'outside'
            outside.write_bytes(b'secret\n')
            os.symlink(outside, root / 'storage/data/link')
            os.symlink(self.directory, root / 'storage/data/dirlink')
        controller.state_write(root, {'run_id': self.run_id, 'workspace_id': self.workspace_id,
                                      'phase': 'ready', 'active': None})

    def event(self, op):
        with (self.directory / 'events').open('a') as out:
            out.write(op + '\n')

    def call(self, operation, args, *, call_id, seconds):
        journal = json.loads((self.directory.parent / 'owner.json').read_bytes())
        assert any(row['core_call_id'] == call_id and row['intent'] for row in journal['calls'].values())
        self.event(operation)
        if self.mode == 'slow':
            time.sleep(2.3)
        if self.mode == 'stall':
            time.sleep(20)
        return controller.handle({'run_id': self.run_id, 'workspace_id': self.workspace_id, 'call_id': call_id,
                                  'operation': operation, 'args': args, 'deadline': time.time() + seconds})

    def command(self, command, *, seconds, call_id):
        self.event('command')
        private_write(self.directory / 'command.json', {'seconds': seconds, 'call_id': call_id})
        if command == 'slow':
            time.sleep(.6)
        if command == 'lease-slow':
            time.sleep(1.3)
        if command == 'stall':
            time.sleep(20)
        data = b'\xff' if command == 'binary' else 'hello 🌊'.encode()
        return {'state': 'timeout' if command == 'timeout' else 'success', 'execution': 'completed',
                'stdout': base64.b64encode(data).decode(), 'stderr': '', 'encoding': 'base64',
                'exit_code': 7, 'signal': None, 'execution_valid': True, 'truncated': False,
                'elapsed_seconds': .1239, 'manifest': {'secret': '/private/host'}, 'observation': {'secret': True}}

    def freeze(self):
        self.event('freeze')
        return {'snapshot': 'test-only'}

    def verify(self, script, checks, **kwargs):
        self.event('verify')
        return {'passed': script == 'protected', 'checks': checks}

    def delete(self, **kwargs):
        if self.mode == 'cleanup-budget':
            assert .5 <= kwargs['seconds'] <= 55, 'reserve transport time within cleanup budget'
        self.event('delete')
        return {'deleted': True}


def hooks(mode):
    """Owner parameters for the fault scenarios; the owner module is never patched."""
    if mode == 'journal-full':
        return {'journal_cap': owner.RESERVE + 300}
    if mode in ('near-lease', 'lease-active'):
        # The first reading sets the lease deadline; it starts nearly spent.
        first = [True]
        def clock():
            if first[0]:
                first[0] = False
                return time.monotonic() - (899.7 if mode == 'near-lease' else 899.0)
            return time.monotonic()
        return {'clock': clock}
    if mode == 'partial-ipc':
        def partial(sock, value):
            if 'response' in value:
                sock.sendall(struct.pack('!I', 100) + b'{')
                time.sleep(2.3)
            else:
                owner.send(sock, value)
        return {'transmit': partial}
    if mode in ('fragmented-valid', 'fragmented-incomplete'):
        def fragmented(sock, value):
            if 'response' not in value:
                return owner.send(sock, value)
            data = owner.encode(value)
            sock.sendall(struct.pack('!I', len(data)) + data[:1])
            for chunk in (data[1:2], data[2:3], data[3:] if mode == 'fragmented-valid' else data[3:-1]):
                time.sleep(.8)
                sock.sendall(chunk)
        return {'transmit': fragmented}
    return {}


if __name__ == '__main__':
    os.umask(0o077)
    config = json.loads(Path(sys.argv[2]).read_bytes())
    # This process stands in for the machine: its registry lives beside the
    # owner's directory, and the machine's candidate uid 65534 does not exist here.
    controller.BASE = Path(config['directory']) / 'machine'
    real_fchown = os.fchown
    os.fchown = lambda fd, uid, gid: None if (uid, gid) == (65534, 65534) else real_fchown(fd, uid, gid)
    mode = base64.b64decode(config['source'].get('scenario', '')).decode()
    run(socket.socket(fileno=int(sys.argv[1])), config, WorkspaceDouble, **hooks(mode))
