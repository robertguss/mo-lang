"""Trusted Linux workspace registry. Never execute candidate file operations."""
import base64
from contextlib import contextmanager
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import time

from remote import command, write, selection, manifest_policy
import workspace_files as files

BASE = Path('/var/lib/mo-harness')
ID = re.compile(r'^[0-9a-f]{32}$')


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def identity(value):
    if not isinstance(value, str) or not ID.fullmatch(value):
        raise files.Refusal('invalid_identity')
    return value


def root_for(workspace_id):
    return BASE / ('mo-workspace-' + identity(workspace_id))


@contextmanager
def lock(root, deadline):
    with (root / 'lock').open('a') as stream:
        while True:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.time() >= deadline:
                    raise files.Refusal('deadline')
                time.sleep(.01)
        yield


def mount_bounds(path):
    info = json.loads(command(['findmnt', '--json', '--mountpoint', str(path), '-o', 'TARGET,FSTYPE,OPTIONS']).stdout)['filesystems'][0]
    opts = set(info['options'].split(','))
    size = next((v.split('=', 1)[1] for v in opts if v.startswith('size=')), '')
    inodes = next((v.split('=', 1)[1] for v in opts if v.startswith('nr_inodes=')), '')
    if (info['target'] != str(path) or info['fstype'] != 'tmpfs' or
            not {'noexec', 'nosuid', 'nodev'}.issubset(opts) or
            size not in ('65536k', '64m', '67108864') or inodes != '4096'):
        raise files.Refusal('mount_bounds')
    return info


def mount(path):
    path.mkdir(mode=0o700)
    command(['mount', '-t', 'tmpfs', '-o', 'size=67108864,nr_inodes=4096,noexec,nosuid,nodev,mode=0700', 'mo-workspace', str(path)])
    return mount_bounds(path)


@contextmanager
def data_fd(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_DIRECTORY | os.O_NONBLOCK)
    try:
        yield fd
    finally:
        os.close(fd)


def state_read(root):
    return json.loads((root / 'state.json').read_text())


def state_write(root, state):
    write(root / 'state.json', state)


def no_active(state):
    if state.get('active'):
        raise files.Refusal('cleanup_required')
    if state['phase'] == 'quarantined':
        raise files.Refusal('quarantined')


def binding(root, state, readonly=False):
    return {**state.get('selection', {}), 'workspace_id': state['workspace_id'], 'workspace_run_id': state['run_id'],
            'source': str(root / ('snapshot/data' if readonly else 'storage/data')),
            'readonly': readonly, 'snapshot': state.get('snapshot') if readonly else None}


def authorize(manifest):
    """Called by existing bootstrap, with the executor registration lock held."""
    w = manifest['workspace']
    root = root_for(w['workspace_id'])
    with lock(root, time.time() + 4):
        state = state_read(root)
        active = state.get('active')
        if not active or active['execution_id'] != manifest['run_id'] or active.get('started'):
            raise files.Refusal('unregistered_execution')
        if w != binding(root, state, readonly=active['readonly']):
            raise files.Refusal('foreign_workspace')
        manifest_policy(manifest)
        if time.time() >= active['deadline']:
            raise files.Refusal('deadline')
        mount_bounds(root / ('snapshot' if active['readonly'] else 'storage'))
        if active['readonly']:
            with data_fd(root / 'snapshot/data') as fd:
                if digest(files.inventory(fd, exact_modes=True)) != state['snapshot']:
                    raise files.Refusal('stale_snapshot')
        active['started'] = True
        state_write(root, state)


def dispatch(root, state, operation, args, deadline):
    if operation == 'cancel':
        active = state.get('active')
        if not active or not active.get('started'):
            raise files.Refusal('not_started')
        (Path('/tmp/mo-executor-' + active['execution_id']) / 'cancel').touch()
        return {'cancel_requested': True}
    if operation == 'complete':
        active = state.get('active')
        if not active or args != {'execution_id': active['execution_id']}:
            raise files.Refusal('foreign_execution')
        run_root = Path('/tmp/mo-executor-' + active['execution_id'])
        proof = json.loads((run_root / 'cleanup-confirmed.json').read_text())
        if not all(proof.get(k) is True for k in ('host_confirmed', 'host_cgroup_absent', 'services_absent')):
            state['phase'] = 'quarantined'
            raise files.Refusal('cleanup_unknown')
        state['last_cleanup'] = proof
        state['active'] = None
        return {'cleanup': proof}
    if operation == 'delete' and state.get('active'):
        raise files.Refusal('cleanup_required')
    if operation == 'delete':
        for name in ('snapshot', 'storage'):
            path = root / name
            if path.exists():
                # Only exact owned mounts; never recursive unmount or lazy detach.
                mount_bounds(path)
                command(['umount', str(path)])
                path.rmdir()
        state['phase'] = 'deleted'
        return {'deleted': True}
    no_active(state)
    if operation == 'reserve':
        if args.get('selection', {}) != state.get('selection', {}):
            raise files.Refusal('policy_mismatch')
        readonly = args['readonly']
        if type(readonly) is not bool or state['phase'] != ('frozen' if readonly else 'ready'):
            raise files.Refusal('closed')
        identity(args['execution_id'])
        state['active'] = {'execution_id': args['execution_id'], 'readonly': readonly,
                           'deadline': deadline, 'started': False}
        return {'workspace': binding(root, state, readonly)}
    if state['phase'] != 'ready':
        raise files.Refusal('closed')
    if operation == 'freeze':
        state['phase'] = 'closed'
        state_write(root, state)
        with data_fd(root / 'storage/data') as source:
            rows = files.inventory(source)
            if state.get('selection') and not rows:
                raise files.Refusal('empty_snapshot')
            state['snapshot_mount'] = mount(root / 'snapshot')
            (root / 'snapshot/data').mkdir(mode=0o755)
            with data_fd(root / 'snapshot/data') as target:
                for row in rows:
                    parts = files.path_parts(row['path'])
                    with files.directory(source, parts[:-1]) as parent:
                        data, mode = files.read_at(parent, parts[-1])
                    files.replace_file(target, row['path'], data, create=True, mode=mode)
                copied = files.inventory(target, exact_modes=True)
            if copied != rows:
                raise files.Refusal('snapshot_mismatch')
        state['snapshot'] = digest(rows)
        write(root / 'snapshot-inventory.json', rows)
        state['phase'] = 'frozen'
        return {'snapshot': state['snapshot'], 'inventory': files.bounded(rows, files.MAX_FILES)}
    with data_fd(root / 'storage/data') as fd:
        if operation == 'list_files':
            return files.list_files(fd, args.get('path', '.'))
        if operation == 'read_file':
            return {'text': files.read_file(fd, args['path'])}
        if operation == 'search':
            return files.search(fd, args['text'], args.get('path', '.'))
        if operation in ('write_file', 'exact_edit'):
            # Enforce tree limits before and after replacement, without publishing
            # an over-quota write. A same-directory temporary can still hit tmpfs.
            rows = files.inventory(fd)
            if operation == 'write_file':
                path, text = args['path'], args['text']
                data = files.text_bytes(text)
                existing = next((r for r in rows if r['path'] == path), None)
                if not existing and len(rows) >= files.MAX_FILES:
                    raise files.Refusal('quota')
                if sum(r['length'] for r in rows) - (existing['length'] if existing else 0) + len(data) > files.MAX_BYTES:
                    raise files.Refusal('quota')
                return files.write_file(fd, path, text, owner=(65534, 65534))
            return files.exact_edit(fd, args['path'], args['old'], args['new'], owner=(65534, 65534))
    raise files.Refusal('invalid_operation')


def create(request, root):
    selected = selection(**request['args'].get('selection', {}))
    entries = [(row[0], base64.b64decode(row[1], validate=True)) for row in request['args']['files']]
    files.validate_import(entries)
    BASE.mkdir(mode=0o755, exist_ok=True)
    if (BASE / ('.retired-' + request['workspace_id'])).exists():
        raise files.Refusal('retired_workspace')
    root.mkdir(mode=0o700)
    state = {'workspace_id': request['workspace_id'], 'run_id': request['run_id'],
             'phase': 'creating', 'active': None}
    if selected:
        state['selection'] = selected
    state_write(root, state)
    with lock(root, request['deadline']):
        claim(root, request)
        try:
            state['mount'] = mount(root / 'storage')
            (root / 'storage/data').mkdir(mode=0o755)
            with data_fd(root / 'storage/data') as fd:
                for path, data in entries:
                    files.replace_file(fd, path, data, create=True, owner=(65534, 65534))
            # Imported directories are candidate-owned, without following links.
            for parent, dirs, _ in os.walk(root / 'storage/data', followlinks=False):
                os.chown(parent, 65534, 65534)
            state['phase'] = 'ready'
            state_write(root, state)
            return {'mount': state['mount'], 'workspace_id': state['workspace_id']}
        except BaseException:
            state['phase'] = 'quarantined'
            state_write(root, state)
            raise


def claim(root, request):
    claims = root / 'calls'
    claims.mkdir(mode=0o700, exist_ok=True)
    try:
        with (claims / request['call_id']).open('x') as out:
            json.dump({'operation': request['operation'], 'deadline': request['deadline'], 'started': time.time()}, out)
    except FileExistsError:
        raise files.Refusal('duplicate_call') from None


def handle(request):
    start = time.monotonic()
    for key in ('run_id', 'workspace_id', 'call_id'):
        identity(request[key])
    deadline = request['deadline']
    if type(deadline) not in (int, float) or not math.isfinite(deadline) or not 0 < deadline - time.time() <= 60:
        raise files.Refusal('deadline')
    root = root_for(request['workspace_id'])
    response = {k: request[k] for k in ('run_id', 'workspace_id', 'call_id')}
    response.update(state='failure', execution='not_started', truncated=False)
    state = None
    def expired(*_):
        raise TimeoutError('deadline')
    previous = signal.signal(signal.SIGALRM, expired)
    signal.setitimer(signal.ITIMER_REAL, deadline - time.time())
    try:
        if request['operation'] == 'create':
            response['result'] = create(request, root)
        else:
            with lock(root, deadline):
                state = state_read(root)
                if state['run_id'] != request['run_id']:
                    raise files.Refusal('foreign_run')
                claim(root, request)
                response['execution'] = 'unknown'
                try:
                    response['result'] = dispatch(root, state, request['operation'], request['args'], deadline)
                finally:
                    state_write(root, state)
        response.update(state='success', execution='completed')
        if len(json.dumps(response).encode()) > files.CAP - 256:
            response.pop('result', None)
            response.update(state='refusal', error='result_too_large', truncated=True)
    except TimeoutError:
        response.update(state='timeout', execution='unknown', error='deadline')
    except (files.Refusal, OSError, ValueError, KeyError, TypeError) as exc:
        code = str(exc) if isinstance(exc, files.Refusal) else 'filesystem_refusal'
        response.update(state='refusal', execution='completed', error=code)
    except Exception:
        response.update(state='failure', execution='unknown', error='controller_failure')
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)
    response['elapsed_seconds'] = time.monotonic() - start
    if root.exists() and response['execution'] == 'unknown':
        # Never reuse a state that may have been partly mutated on timeout.
        with lock(root, time.time() + 2):
            state = state_read(root)
            state['phase'] = 'quarantined'
            state_write(root, state)
    if root.exists():
        with lock(root, time.time() + 2):
            result = root / 'calls' / (request['call_id'] + '.result')
            # Duplicate requests cannot replace the authoritative first outcome.
            try:
                with result.open('x') as out:
                    json.dump(response, out)
            except FileExistsError:
                pass
    if response['state'] == 'success' and request['operation'] == 'delete':
        # Trusted tombstone prevents identity replay after owned directories go.
        with (BASE / ('.retired-' + request['workspace_id'])).open('x') as out:
            json.dump(response, out)
        shutil.rmtree(root)
    return response
