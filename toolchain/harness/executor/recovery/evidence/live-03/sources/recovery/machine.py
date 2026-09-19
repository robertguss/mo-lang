"""Cleanup only, loaded from installed caller sources, never retained scripts."""
from contextlib import nullcontext
import json
from pathlib import Path
import shutil
import signal
import time

import remote
import workspace_controller as controller
from recovery import validate

EXECUTION_BASE = Path('/tmp')


def read_json(path, limit=1024 * 1024):
    if path.is_symlink() or not path.is_file() or path.stat().st_nlink != 1 or path.stat().st_size > limit:
        raise ValueError('invalid remote record')
    return json.loads(path.read_text())


def absence(execution_id):
    name = 'mo-executor-' + execution_id
    containers = remote.command(['docker', 'ps', '-aq', '--no-trunc', '--filter', 'name=^/' + name + '$'])
    units = remote.command(['systemctl', 'list-units', '--all', '--no-legend', name + '*'])
    if containers.stdout.strip() or units.stdout.strip():
        raise ValueError('unowned runtime remains')


def recover(receipt, seconds):
    receipt = validate(receipt)
    deadline = time.time() + seconds
    result = {'run_id': receipt['run_id'], 'workspace_id': receipt['workspace_id'],
              'cleanup': 'unresolved', 'execution': 'unknown', 'completed': [],
              'unresolved': [r['execution_id'] for r in receipt['executions']]}
    root = controller.root_for(receipt['workspace_id'])
    terminal = controller.terminal_path(receipt['workspace_id'])
    def expired(*_):
        raise TimeoutError('recovery budget')
    previous = signal.signal(signal.SIGALRM, expired)
    signal.setitimer(signal.ITIMER_REAL, max(.01, seconds))
    try:
        with remote.registration_lock(deadline):
            controller.BASE.mkdir(mode=0o755, exist_ok=True)
            if root.is_symlink():
                raise ValueError('linked workspace')
            with (controller.lock(root, deadline) if root.exists() else nullcontext()):
                state = read_json(root / 'state.json') if root.exists() else None
                if state and (state.get('run_id') != receipt['run_id'] or state.get('workspace_id') != receipt['workspace_id'] or
                              remote.selection(**receipt['selection']) != state.get('selection', {})):
                    raise ValueError('foreign workspace')
                if terminal.exists() and read_json(terminal).get('ownership') != receipt:
                    raise ValueError('conflicting terminal ownership')
                retired = controller.BASE / ('.retired-' + receipt['workspace_id'])
                if retired.exists():
                    old = read_json(retired)
                    if any(old.get(k) != receipt[k] for k in ('run_id', 'workspace_id')):
                        raise ValueError('foreign retired workspace')
                rows = {r['execution_id']: r for r in receipt['executions']}
                active = state.get('active') if state else None
                if active and active['execution_id'] not in rows:
                    raise ValueError('unrecorded active execution')
                # Validate every surviving identity before any cleanup side effect.
                for row in rows.values():
                    eroot = EXECUTION_BASE / ('mo-executor-' + row['execution_id'])
                    if eroot.is_symlink():
                        raise ValueError('linked execution')
                    if eroot.exists():
                        m = read_json(eroot / 'manifest.json')
                        w = m.get('workspace', {})
                        if (m.get('run_id') != row['execution_id'] or m.get('name') != eroot.name or
                                w.get('workspace_id') != receipt['workspace_id'] or w.get('workspace_run_id') != receipt['run_id'] or
                                w.get('readonly') != row['readonly'] or m.get('workspace_call_id') != row['call_id']):
                            raise ValueError('foreign execution')
                        remote.manifest_policy(m)
                        if remote.workspace_selection(w) != remote.selection(**receipt['selection']):
                            raise ValueError('foreign execution selection')
                if not terminal.exists():
                    remote.write(terminal, {'ownership': receipt, 'phase': 'cleaning', 'executions': {}})
                record = read_json(terminal)
                result['completed'].append('terminal_barrier')
                if state:
                    state['phase'] = 'quarantined'
                    controller.state_write(root, state)
                for row in rows.values():
                    eid = row['execution_id']
                    eroot = EXECUTION_BASE / ('mo-executor-' + eid)
                    if eroot.exists():
                        proof = remote.finalize(eroot, locked=True)
                        if not all(proof.get(k) is True for k in ('host_confirmed', 'host_cgroup_absent', 'services_absent')):
                            raise ValueError('cleanup proof missing')
                        record['executions'][eid] = proof
                        remote.write(terminal, record)  # survives interruption during disposal
                        if active and active['execution_id'] == eid:
                            state['active'] = None
                            controller.state_write(root, state)
                        remote.dispose(eroot, locked=True)
                    else:
                        absence(eid)
                        proof = record['executions'].get(eid) or (state or {}).get('completed_executions', {}).get(eid)
                        if row['dispatch_requested'] and not proof:
                            raise ValueError('dispatched execution proof missing')
                        if proof and proof.get('host_cgroup') and Path(proof['host_cgroup']).exists():
                            raise ValueError('candidate cgroup remains')
                        if active and active['execution_id'] == eid:
                            if active.get('started') and not proof:
                                raise ValueError('started execution proof missing')
                            state['active'] = None
                            controller.state_write(root, state)
                    result['completed'].append(eid)
                    result['unresolved'].remove(eid)
                if state:
                    for name in ('snapshot', 'storage'):
                        mount = root / name
                        if mount.is_symlink():
                            raise ValueError('linked mount')
                        if mount.exists():
                            controller.mount_bounds(mount)
                            remote.command(['umount', str(mount)])
                            mount.rmdir()
                    state['phase'] = 'deleted'
                    controller.state_write(root, state)
                record['phase'] = 'cleaned'
                remote.write(terminal, record)
            if root.exists():
                shutil.rmtree(root)
            result['completed'].append('workspace_deleted')
            result['cleanup'] = 'confirmed'
    except Exception:
        result['error'] = 'cleanup_unknown'
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)
    return result
