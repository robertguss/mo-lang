"""Trusted operator ownership records and explicit cleanup-only recovery."""
from contextlib import contextmanager
import fcntl
import json
import math
import os
from pathlib import Path
import stat
import time
import uuid

from remote import IMAGE, WORKSPACE_POLICY, selection, write
from workspace_controller import identity

VERSION = 'mo-workspace-ownership-v1'
MAX_EXECUTIONS = 1000
MAX_RECORD = 1024 * 1024


def validate(receipt):
    if not isinstance(receipt, dict) or set(receipt) != {'version', 'run_id', 'workspace_id', 'selection', 'directory', 'executions'}:
        raise ValueError('ownership schema')
    if receipt['version'] != VERSION:
        raise ValueError('ownership version')
    for key in ('run_id', 'workspace_id'):
        identity(receipt[key])
    selected = receipt['selection']
    if not isinstance(selected, dict) or selected != {'policy': selected.get('policy'), 'image': selected.get('image'), 'toolchain': selected.get('toolchain')}:
        raise ValueError('ownership selection')
    selection(**selected)
    if not isinstance(receipt['directory'], str) or not Path(receipt['directory']).is_absolute():
        raise ValueError('ownership directory')
    rows = receipt['executions']
    if not isinstance(rows, list) or len(rows) > MAX_EXECUTIONS:
        raise ValueError('ownership bound')
    seen = set()
    for row in rows:
        if not isinstance(row, dict) or set(row) != {'execution_id', 'call_id', 'directory', 'readonly', 'dispatch_requested'}:
            raise ValueError('execution schema')
        for key in ('execution_id', 'call_id'):
            identity(row[key])
            if row[key] in seen:
                raise ValueError('duplicate execution identity')
            seen.add(row[key])
        if row['directory'] != 'execution-' + row['execution_id'] or type(row['readonly']) is not bool or type(row['dispatch_requested']) is not bool:
            raise ValueError('execution binding')
    if len(json.dumps(receipt).encode()) > MAX_RECORD:
        raise ValueError('ownership bound')
    return receipt


def safe_directory(path):
    path = Path(os.path.abspath(path))
    # macOS /tmp is an alias; the persisted path is canonical at creation.
    for parent in (*reversed(path.parents), path):
        if parent.is_symlink():
            raise ValueError('linked ownership directory')
    info = path.stat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError('nonprivate ownership directory')
    return path


def read_receipt(path):
    path = Path(os.path.abspath(path))
    directory = safe_directory(path.parent)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.getuid() or info.st_size > MAX_RECORD:
            raise ValueError('ownership file')
        with os.fdopen(fd, 'rb', closefd=False) as stream:
            receipt = validate(json.load(stream))
    finally:
        os.close(fd)
    if receipt['directory'] != str(directory):
        raise ValueError('foreign result directory')
    return receipt


def validate_supporting(receipt):
    for row in receipt['executions']:
        directory = safe_directory(Path(receipt['directory']) / row['directory'])
        path = directory / 'manifest.json'
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_size > MAX_RECORD:
                raise ValueError('execution record')
            with os.fdopen(fd, 'rb', closefd=False) as stream:
                manifest = json.load(stream)
        finally:
            os.close(fd)
        selected = receipt['selection']
        if (manifest.get('run_id') != row['execution_id'] or manifest.get('name') != 'mo-executor-' + row['execution_id'] or
                any(manifest.get(k) != selected[k] for k in ('policy', 'image', 'toolchain'))):
            raise ValueError('conflicting execution record')
        workspace = manifest.get('workspace', {})
        if 'workspace_id' in workspace and (workspace.get('workspace_id') != receipt['workspace_id'] or
                workspace.get('workspace_run_id') != receipt['run_id'] or workspace.get('readonly') != row['readonly'] or
                manifest.get('workspace_call_id') != row['call_id']):
            raise ValueError('conflicting workspace binding')


@contextmanager
def owner_lock(directory, deadline):
    fd = os.open(Path(directory) / 'ownership.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError('ownership busy')
                time.sleep(.01)
        yield
    finally:
        os.close(fd)


def initialize(ws):
    ws.directory = ws.directory.resolve()
    ws.ownership = {'version': VERSION, 'run_id': ws.run_id, 'workspace_id': ws.workspace_id,
                    'selection': {'policy': ws.selection.get('policy', WORKSPACE_POLICY),
                                  'image': ws.selection.get('image', IMAGE), 'toolchain': ws.selection.get('toolchain')},
                    'directory': str(ws.directory), 'executions': []}
    persist(ws)
    ws._ownership_fd = os.open(ws.directory / 'ownership.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    fcntl.flock(ws._ownership_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)


def persist(ws):
    validate(ws.ownership)
    write(ws.directory / 'ownership.json', ws.ownership)
    os.chmod(ws.directory / 'ownership.json', 0o600)


def intent(ws, run, call_id, readonly):
    identity(call_id)
    execution_id = run.manifest['run_id']
    target = ws.directory / ('execution-' + execution_id)
    run.directory.rename(target)
    run.directory = target
    ws.ownership['executions'].append({'execution_id': execution_id, 'call_id': call_id,
                                      'directory': target.name, 'readonly': readonly, 'dispatch_requested': False})
    persist(ws)


def validate_response(raw, receipt):
    if not isinstance(raw, bytes) or len(raw) > MAX_RECORD:
        raise ValueError('recovery response bound')
    response = json.loads(raw)
    required = {'run_id', 'workspace_id', 'cleanup', 'execution', 'completed', 'unresolved'}
    if not isinstance(response, dict) or not required <= set(response) <= required | {'error'}:
        raise ValueError('recovery response schema')
    if any(response[k] != receipt[k] for k in ('run_id', 'workspace_id')):
        raise ValueError('recovery response identity')
    if response['cleanup'] not in ('confirmed', 'unresolved') or response['execution'] != 'unknown':
        raise ValueError('recovery response status')
    ids = [row['execution_id'] for row in receipt['executions']]
    done, remaining = response['completed'], response['unresolved']
    if not isinstance(done, list) or not isinstance(remaining, list):
        raise ValueError('recovery response phases')
    if response['cleanup'] == 'confirmed':
        if done != ['terminal_barrier', *ids, 'workspace_deleted'] or remaining or 'error' in response:
            raise ValueError('contradictory cleanup confirmation')
    else:
        if response.get('error') != 'cleanup_unknown':
            raise ValueError('recovery response error')
        count = len(done) - 1 if done else 0
        if count < 0 or count > len(ids) or (done and done != ['terminal_barrier', *ids[:count]]) or remaining != ids[count:]:
            raise ValueError('recovery response phases')
    return response


def recover(receipt_path, *, seconds=60):
    """Retire and clean exact recorded ownership. Never start/resume execution."""
    if type(seconds) not in (int, float) or not math.isfinite(seconds) or not .5 <= seconds <= 1800:
        raise ValueError('recovery budget')
    receipt = read_receipt(receipt_path)  # invalid records cause no transport/effects
    deadline = time.monotonic() + seconds
    result = {'run_id': receipt['run_id'], 'workspace_id': receipt['workspace_id'],
              'cleanup': 'unresolved', 'execution': 'unknown', 'completed': [],
              'unresolved': [row['execution_id'] for row in receipt['executions']]}
    acquired = False
    try:
        with owner_lock(receipt['directory'], deadline):
            acquired = True
            receipt = read_receipt(receipt_path)
            validate_supporting(receipt)
            Path(receipt['directory'], 'recovery-requested').touch()
            import adapter
            sources = adapter.sources('remote', 'workspace_files', 'workspace_controller')
            sources['recovery'] = Path(__file__).read_text()
            sources['recovery_machine'] = Path(__file__).with_name('machine.py').read_text()
            remaining = max(.01, deadline - time.monotonic())
            raw = adapter.machine_call(sources, "sys.modules['recovery_machine'].recover(p['receipt'],p['seconds'])",
                                       {'receipt': receipt, 'seconds': remaining}, remaining)
            response = validate_response(raw, receipt)
            result.update(response)
    except Exception as exc:
        result['error'] = 'ownership_busy' if isinstance(exc, TimeoutError) and not acquired else 'recovery_unknown'
    # Each attempt is new evidence; original execution observations are untouched.
    path = Path(receipt['directory']) / ('recovery-' + uuid.uuid4().hex + '.json')
    with path.open('x') as stream:
        json.dump(result, stream, indent=2)
    return result
