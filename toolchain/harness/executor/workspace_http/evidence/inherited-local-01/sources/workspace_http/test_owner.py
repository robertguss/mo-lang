"""Local process test double only. Never imported by the production owner."""
import base64
import json
import os
from pathlib import Path
import socket
import sys
import time
import uuid

from .owner import private_write, run

class WorkspaceDouble:
    def __init__(self, run_id, directory, **selection):
        self.directory = Path(directory)
        self.directory.mkdir(mode=0o700)
        self.workspace_id = uuid.uuid4().hex
        self.active = None
        self.source = {}
        self.mode = ''
        private_write(self.directory / 'ownership.json', {'test_double': True})

    def create(self, source, **kwargs):
        self.source = source
        self.mode = source.get('scenario', b'').decode()
        journal = json.loads((self.directory.parent / 'owner.json').read_bytes())
        assert journal['core_workspace_id'] == self.workspace_id
        assert journal['receipt_path'] == str(self.directory / 'ownership.json')
        assert journal['creation_call_id'] == kwargs['call_id']
        self.event('create')
        if self.mode == 'startup-failure':
            raise RuntimeError('private host failure')

    def event(self, op):
        with (self.directory / 'events').open('a') as out:
            out.write(op + '\n')

    def call(self, operation, args, **kwargs):
        journal = json.loads((self.directory.parent / 'owner.json').read_bytes())
        assert any(row['core_call_id'] == kwargs['call_id'] and row['intent'] for row in journal['calls'].values())
        self.event(operation)
        if self.mode == 'slow':
            time.sleep(2.3)
        if self.mode == 'stall':
            time.sleep(20)
        if args.get('path') == 'refuse':
            return {'state': 'refusal', 'execution': 'completed', 'error': 'result_too_large', 'truncated': True}
        result = {'list_files': {'items': [{'path': 'a'}]}, 'search': {'items': [{'path': 'a', 'offset': 2}]},
                  'read_file': {'text': 'héllo'}, 'write_file': {'written': True}, 'exact_edit': {'edited': True}}[operation]
        return {'state': 'success', 'execution': 'completed', 'result': result}

    def command(self, command, *, seconds, call_id):
        self.event('command')
        private_write(self.directory / 'command.json', {'seconds': seconds, 'call_id': call_id})
        if command == 'slow':
            time.sleep(.6)
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
        self.event('delete')
        return {'deleted': True}

if __name__ == '__main__':
    os.umask(0o077)
    run(socket.socket(fileno=int(sys.argv[1])), json.loads(Path(sys.argv[2]).read_bytes()), WorkspaceDouble)
