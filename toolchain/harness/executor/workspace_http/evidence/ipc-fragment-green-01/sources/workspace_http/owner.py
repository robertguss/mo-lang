"""Serialized Workspace owner. IPC EOF ends admission, never interrupts work."""
import base64
import hashlib
import json
import os
from pathlib import Path
import socket
import struct
import sys
import time
import uuid

from .protocol import JOURNAL_CAP, RESPONSE_CAP, encode, envelope, project

IPC_CAP = 2 * 1024 * 1024
RESERVE = RESPONSE_CAP + 8192


def private_write(path, value):
    path = Path(path)
    data = encode(value)
    temp = path.with_name(path.name + '.new')
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
        os.replace(temp, path)
    finally:
        if temp.exists():
            temp.unlink()


def receive(sock, *, deadline=None):
    if deadline is None:
        timeout = sock.gettimeout()
        if timeout is None:
            raise ValueError('IPC deadline required')
        deadline = time.monotonic() + timeout
    def exact(count):
        data = bytearray()
        while len(data) < count:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise socket.timeout()
            sock.settimeout(remaining)
            part = sock.recv(count - len(data))
            if not part:
                raise EOFError()
            data.extend(part)
        return bytes(data)
    size = struct.unpack('!I', exact(4))[0]
    if size > IPC_CAP:
        raise ValueError('IPC bound')
    result = json.loads(exact(size))
    if time.monotonic() >= deadline:
        raise socket.timeout()
    return result


def send(sock, value):
    data = encode(value)
    if len(data) > IPC_CAP:
        raise ValueError('IPC bound')
    sock.sendall(struct.pack('!I', len(data)) + data)


def run(sock, config, factory=None):
    # Factory injection is Python-only and used by local subprocess controls.
    if factory is None:
        from workspace import Workspace
        factory = Workspace
    directory = Path(config['directory'])
    journal = {'version': 'mo-workspace-http-owner-v1', 'run_id': config['run_id'],
               'workspace_id': config['workspace_id'], 'core_run_id': uuid.uuid4().hex,
               'core_workspace_id': None, 'receipt_path': str(directory / 'workspace' / 'ownership.json'),
               'owner_pid': os.getpid(), 'calls': {}, 'creation': 'intent',
               'cleanup': {'cleanup': 'unresolved', 'execution': 'unknown'}}
    def persist():
        if len(encode(journal)) > JOURNAL_CAP:
            raise ValueError('journal bound')
        private_write(directory / 'owner.json', journal)
    persist()
    ws = None
    try:
        ws = factory(journal['core_run_id'], directory / 'workspace', **config['selection'])
        journal['core_workspace_id'] = ws.workspace_id
        # Constructor is local only; known receipt and IDs precede create dispatch.
        journal['creation_call_id'] = uuid.uuid4().hex
        persist()
        ws.create({key: base64.b64decode(value, validate=True) for key, value in config['source'].items()},
                  call_id=journal['creation_call_id'])
        journal['creation'] = 'completed'
        deadline = time.monotonic() + 900
        journal['ready_monotonic'] = deadline - 900
        persist()
        sock.settimeout(2)
        send(sock, {'ready': True, 'deadline': deadline})
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            sock.settimeout(remaining)
            message = receive(sock, deadline=deadline)
            kind = message['kind']
            if kind == 'close':
                break
            if kind == 'freeze':
                result = ws.freeze()
                sock.settimeout(2)
                send(sock, {'operator_result': result})
                continue
            if kind == 'verify':
                verifier = config['verifier']
                result = ws.verify(verifier['script'], verifier['checks'], seconds=verifier['seconds'])
                private_write(directory / 'verification.json', result)
                sock.settimeout(2)
                send(sock, {'operator_result': result})
                continue
            if kind != 'tool':
                raise ValueError('invalid operator IPC')
            req = message['request']
            call_id = req['call_id']
            refused = None
            if call_id in journal['calls']:
                refused = 'conflict'
            elif len(journal['calls']) >= 16:
                refused = 'call_limit'
            elif len(encode(journal)) + RESERVE > JOURNAL_CAP:
                refused = 'journal_full'
            remaining = deadline - time.monotonic()
            if remaining < .5:
                refused = 'admission_closed'
            if refused:
                sock.settimeout(2)
                send(sock, {'response': envelope(req, error=refused), 'status': 409})
                continue
            core_id = uuid.uuid4().hex
            row = {'core_call_id': core_id, 'payload_sha256': hashlib.sha256(encode(req)).hexdigest(),
                   'intent': True, 'result': None}
            journal['calls'][call_id] = row
            persist()
            try:
                args = dict(req['args'])
                if req['operation'] == 'command':
                    seconds = min(args['timeout_ms'] / 1000, max(0, deadline - time.monotonic()))
                    if seconds < .5:
                        core = {'state': 'refusal', 'execution': 'not_started', 'error': 'deadline',
                                'exit_code': None, 'signal': None, 'stdout': '', 'stderr': '',
                                'encoding': 'base64', 'execution_valid': False, 'truncated': False}
                    else:
                        core = ws.command(args['command'], seconds=seconds, call_id=core_id)
                else:
                    if req['operation'] == 'search':
                        args['text'] = args.pop('query')
                    elif req['operation'] == 'exact_edit':
                        args['old'], args['new'] = args.pop('old_text'), args.pop('new_text')
                    core = ws.call(req['operation'], args, call_id=core_id,
                                   seconds=min(2, max(.5, deadline - time.monotonic())))
                # Raw operator evidence stays outside the candidate projection/journal cap.
                private_write(directory / ('core-' + core_id + '.json'), core)
                response = project(req, core)
            except Exception as exc:
                private_write(directory / ('exception-' + core_id + '.json'),
                              {'type': type(exc).__name__, 'detail': str(exc)})
                response = envelope(req, accepted=True, state='failure', execution='unknown', error='owner_unknown')
            row['result'] = response
            persist()
            sock.settimeout(2)
            send(sock, {'response': response, 'status': 200})
            if response['execution'] == 'unknown':
                break
    except (EOFError, OSError, ValueError, KeyError) as exc:
        journal['owner_error'] = type(exc).__name__
    except Exception as exc:
        journal['owner_error'] = type(exc).__name__
    finally:
        # No recovery while a Workspace owns its lock. A failed normal cleanup
        # remains unresolved for a separate explicit operator recovery invocation.
        cleanup_deadline = time.monotonic() + 60
        if ws is not None:
            try:
                if ws.active:
                    ws.collect()
                # Workspace.call adds five seconds to its configured transport wait.
                seconds = min(55, cleanup_deadline - time.monotonic() - 5)
                if seconds < .5:
                    raise TimeoutError('cleanup budget exhausted')
                result = ws.delete(seconds=seconds)
                if result.get('deleted') is True:
                    journal['cleanup'] = {'cleanup': 'confirmed', 'execution': 'unknown', 'method': 'Workspace.delete'}
            except Exception as exc:
                journal['cleanup']['error'] = type(exc).__name__
        persist()
        sock.close()


def main():
    os.umask(0o077)
    sock = socket.socket(fileno=int(sys.argv[1]))
    config = json.loads(Path(sys.argv[2]).read_bytes())
    run(sock, config)

if __name__ == '__main__':
    main()
