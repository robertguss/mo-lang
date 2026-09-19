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


def mounted_paths(root):
    # Inventory only for absence proof, never resource adoption.
    paths = {line.split()[4] for line in Path('/proc/self/mountinfo').read_text().splitlines()}
    return {path for path in paths if path == str(root) or path.startswith(str(root) + '/')}


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
                prior = read_json(terminal) if terminal.exists() else None
                if prior and prior.get('ownership') != receipt:
                    raise ValueError('conflicting terminal ownership')
                owner_path = controller.BASE / ('.owner-' + receipt['workspace_id'])
                owner = read_json(owner_path) if owner_path.exists() else None
                expected_owner = {'run_id': receipt['run_id'], 'workspace_id': receipt['workspace_id'],
                                  'selection': remote.selection(**receipt['selection'])}
                if owner and owner != expected_owner:
                    raise ValueError('foreign machine ownership')
                if root.exists() and not (root / 'state.json').exists() and owner:
                    state = {**owner, 'phase': 'quarantined', 'active': None}
                else:
                    state = read_json(root / 'state.json') if root.exists() and ((root / 'state.json').exists() or not prior or prior.get('phase') != 'cleaned') else None
                if state and (state.get('run_id') != receipt['run_id'] or state.get('workspace_id') != receipt['workspace_id'] or
                              remote.selection(**receipt['selection']) != state.get('selection', {})):
                    raise ValueError('foreign workspace')
                if terminal.exists() and read_json(terminal).get('ownership') != receipt:
                    raise ValueError('conflicting terminal ownership')
                retired = controller.BASE / ('.retired-' + receipt['workspace_id'])
                old = {}
                if retired.exists():
                    old = read_json(retired)
                    if any(old.get(k) != receipt[k] for k in ('run_id', 'workspace_id')):
                        raise ValueError('foreign retired workspace')
                    if old.get('selection', {}) != remote.selection(**receipt['selection']):
                        raise ValueError('foreign retired selection')
                retained = read_json(terminal).get('executions', {}) if terminal.exists() else {}
                rows = {r['execution_id']: r for r in receipt['executions']}
                active = state.get('active') if state else None
                if active and (active['execution_id'] not in rows or
                               active.get('call_id') != rows[active['execution_id']]['call_id'] or
                               active.get('readonly') != rows[active['execution_id']]['readonly']):
                    raise ValueError('unrecorded active execution')
                completed = {**old.get('completed_executions', {}), **(state or {}).get('completed_executions', {})}
                if set(completed) - set(rows):
                    raise ValueError('omitted completed execution')
                not_started = {active['execution_id']} if active and active.get('started') is False else set()
                # Validate every surviving identity before any cleanup side effect.
                for row in rows.values():
                    eroot = EXECUTION_BASE / ('mo-executor-' + row['execution_id'])
                    if eroot.is_symlink():
                        raise ValueError('linked execution')
                    if eroot.exists() and ((eroot / 'manifest.json').exists() or row['execution_id'] not in retained and row['execution_id'] not in not_started):
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
                    if eid in not_started and not (eroot / 'manifest.json').exists():
                        absence(eid)
                        proof = {'host_confirmed': True, 'host_cgroup_absent': True, 'services_absent': True,
                                 'host_cgroup': None, 'execution_not_started': True,
                                 'ordering': ['terminal_barrier', 'reservation_not_started', 'runtime_absent']}
                        record['executions'][eid] = proof
                        remote.write(terminal, record)
                        retained[eid] = proof
                    if eroot.exists() and not (eroot / 'manifest.json').exists() and eid in retained:
                        absence(eid)
                        proof = retained[eid]
                        if not all(proof.get(k) is True for k in ('host_confirmed', 'host_cgroup_absent', 'services_absent')):
                            raise ValueError('incomplete disposal proof')
                        if proof.get('host_cgroup') and Path(proof['host_cgroup']).exists():
                            raise ValueError('candidate cgroup remains')
                        shutil.rmtree(eroot)
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
                        proof = record['executions'].get(eid) or completed.get(eid)
                        if proof:
                            record['executions'][eid] = proof
                            remote.write(terminal, record)
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
                mounts = mounted_paths(root)
                if mounts - {str(root / 'snapshot'), str(root / 'storage')}:
                    raise ValueError('unexpected workspace mount')
                if root.exists():
                    for name in ('snapshot', 'storage'):
                        mount = root / name
                        if mount.is_symlink():
                            raise ValueError('linked mount')
                        if mount.exists():
                            if str(mount) in mounts:
                                controller.mount_bounds(mount)
                                remote.command(['umount', str(mount)])
                            if str(mount) in mounted_paths(root):
                                raise ValueError('mount remains')
                            mount.rmdir()
                    if state:
                        state['phase'] = 'deleted'
                        controller.state_write(root, state)
                if mounted_paths(root):
                    raise ValueError('workspace mounts remain')
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
