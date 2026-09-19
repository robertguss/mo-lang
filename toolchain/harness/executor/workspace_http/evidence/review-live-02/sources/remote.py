"""Trusted machine-side supervisor. Candidate text is only Docker argv data."""
import base64
from contextlib import contextmanager, nullcontext
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import subprocess
import sys
import time

IMAGE = 'sha256:debdba9954b1065ab1ce723c6c1f2f22e52a78c164f863b938d58cc2c9f0d337'
CAP = 64 * 1024
POLICY = 'mo-executor-r01-v1'
WORKSPACE_POLICY = 'mo-executor-workspace-v1'
APPLICATION_POLICY = 'application-build-v1'


def selection(policy=WORKSPACE_POLICY, image=IMAGE, toolchain=None):
    """Only trusted workspace creation selects an immutable application image."""
    if policy == WORKSPACE_POLICY and image == IMAGE and toolchain is None:
        return {}
    if (policy != APPLICATION_POLICY or not isinstance(image, str) or
            not re.fullmatch(r'sha256:[0-9a-f]{64}', image) or image == IMAGE or
            not isinstance(toolchain, str) or not re.fullmatch(r'[0-9a-f]{64}', toolchain)):
        raise ValueError('invalid policy/image/toolchain selection')
    return {'policy': policy, 'image': image, 'toolchain': toolchain}


def workspace_selection(workspace):
    w = workspace or {}
    return selection(w.get('policy', WORKSPACE_POLICY), w.get('image', IMAGE), w.get('toolchain'))


def application_environment():
    return ['PATH=/opt/mo:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
            'HOME=/build', 'TMPDIR=/tmp', 'ZIG_GLOBAL_CACHE_DIR=/build/zig-global',
            'ZIG_LOCAL_CACHE_DIR=/build/zig-local']


def application_tmpfs():
    return {'/build': 'rw,exec,nosuid,nodev,size=536870912,nr_inodes=16384,mode=1777',
            '/tmp': 'rw,noexec,nosuid,nodev,size=16777216,mode=1777'}


def manifest_policy(manifest):
    selected = workspace_selection(manifest.get('workspace'))
    expected = selected or {'policy': WORKSPACE_POLICY if manifest.get('workspace') else POLICY, 'image': IMAGE}
    if any(manifest.get(k) != v for k, v in expected.items()):
        raise ValueError('manifest policy differs from registered workspace')
    maximum = 120 if selected else 10
    seconds = manifest['seconds']
    if type(seconds) not in (int, float) or not .5 <= seconds <= maximum:
        raise ValueError('deadline outside registered policy')
    return selected


def command(args, timeout=3, check=True):
    p = subprocess.run(args, capture_output=True, timeout=timeout)
    if check and p.returncode:
        raise RuntimeError(f'{args[0:2]} exited {p.returncode}: {p.stderr[:2048]!r}')
    return p


def write(path, data):
    temp = path.with_suffix('.new')
    temp.write_text(json.dumps(data, sort_keys=True))
    temp.replace(path)


def inspect(name):
    p = command(['docker', 'inspect', name], check=False)
    if p.returncode:
        raise RuntimeError(f'inspect failed: {p.stderr[:1024]!r}')
    return json.loads(p.stdout)[0]


def policy_errors(info, script, name, workspace=None):
    selected = workspace_selection(workspace)
    h, c = info['HostConfig'], info['Config']
    expected = {'ReadonlyRootfs': True, 'Privileged': False,
                'NetworkMode': 'none', 'NanoCpus': 250000000,
                'Memory': 67108864, 'MemorySwap': 67108864, 'PidsLimit': 16,
                'CgroupParent': 'mo-executor.slice', 'CapDrop': ['ALL'],
                'CapAdd': None, 'Binds': None, 'Devices': [],
                'PidMode': '', 'IpcMode': 'private', 'AutoRemove': False,
                'CgroupnsMode': 'private', 'VolumesFrom': None, 'DeviceRequests': None,
                'RestartPolicy': {'Name': 'no', 'MaximumRetryCount': 0}}
    if workspace:
        expected['Binds'] = [workspace['source'] + ':/workspace:' + ('ro' if workspace['readonly'] else 'rw')]
    if selected:
        expected.update(NanoCpus=1000000000, Memory=1073741824, MemorySwap=1073741824,
                        PidsLimit=128, CgroupParent='mo-application.slice')
    errors = [k for k, v in expected.items() if k not in h or h[k] != v]
    if h.get('SecurityOpt') != ['no-new-privileges']: errors.append('SecurityOpt')
    if h.get('LogConfig', {}).get('Type') != 'none': errors.append('LogConfig')
    tmpfs = application_tmpfs() if selected else {'/work': 'rw,noexec,nosuid,size=8388608,mode=1777',
                                                 '/tmp': 'rw,noexec,nosuid,size=8388608,mode=1777'}
    if h.get('Tmpfs') != tmpfs:
        errors.append('Tmpfs')
    image = selected.get('image', IMAGE)
    if info['Image'] != image or c['Image'] != image: errors.append('Image')
    if c['User'] != '65534:65534': errors.append('User')
    if c['Cmd'] != ['/bin/sh', '-c', script]: errors.append('Cmd')
    if info['Name'] != '/' + name: errors.append('Name')
    if workspace:
        mounts = info.get('Mounts', [])
        if len(mounts) != 1 or any(mounts[0].get(k) != v for k, v in {
                'Type': 'bind', 'Source': workspace['source'], 'Destination': '/workspace',
                'Mode': 'ro' if workspace['readonly'] else 'rw',
                'RW': not workspace['readonly'], 'Propagation': 'rprivate'}.items()):
            errors.append('Mounts')
    elif info.get('Mounts') != []: errors.append('Mounts')
    if c.get('Entrypoint') is not None: errors.append('Entrypoint')
    if c.get('WorkingDir') != ('/workspace' if workspace else '/work'): errors.append('WorkingDir')
    environment = application_environment() if selected else ['PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin']
    actual_environment = c.get('Env')
    if (sorted(actual_environment or []) != sorted(environment) if selected else actual_environment != environment):
        errors.append('Env')
    return errors


def cgroup_path(container_id, application=False):
    parent = command(['systemctl', 'show', '--property=ControlGroup', '--value',
                      'mo-application.slice' if application else 'mo-executor.slice']).stdout.decode().strip()
    if not parent.startswith('/') or '..' in parent:
        raise RuntimeError('missing slice control group')
    return '/sys/fs/cgroup' + parent + '/docker-' + container_id + '.scope'


def cleanup(name, deadline=None):
    deadline = deadline or time.monotonic() + 3
    removal = command(['docker', 'rm', '-f', name], check=False, timeout=max(.01, min(2, deadline - time.monotonic())))
    # A successful daemon query, not an inspect failure, proves absence.
    listing = command(['docker', 'ps', '-aq', '--filter', 'name=^/' + name + '$'],
                      timeout=max(.01, deadline - time.monotonic()))
    return {'removed_rc': removal.returncode, 'absent': not listing.stdout.strip()}


@contextmanager
def registration_lock(deadline=None):
    # Shared with bootstrap: no late supervisor can appear after cleanup proof.
    with open('/tmp/mo-executor-registration.lock', 'a') as lock:
        if deadline is None:
            fcntl.flock(lock, fcntl.LOCK_EX)
        else:
            while True:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if time.time() >= deadline:
                        raise TimeoutError('registration busy')
                    time.sleep(.01)
        yield


def finalize(root, *, locked=False):
    """Leave the independent reaper armed until writers and candidate are gone."""
    with (nullcontext() if locked else registration_lock()):
        name = root.name
        command(['systemctl', 'stop', name + '.service'], check=False)
        active = command(['systemctl', 'list-units', '--all', '--no-legend',
                          '--state=activating,active,reloading,deactivating', name + '.service'])
        if active.stdout.strip(): raise RuntimeError('supervisor may still create candidate writers')
        registration = root / 'registration.json'
        if registration.exists():
            cid = json.loads(registration.read_text())['container_id']
        else:
            cid = command(['docker', 'ps', '-aq', '--no-trunc', '--filter', 'name=^/' + name + '$']).stdout.decode().strip()
        manifest = json.loads((root / 'manifest.json').read_text()) if (root / 'manifest.json').exists() else {}
        group = cgroup_path(cid, bool(workspace_selection(manifest.get('workspace')))) if cid else None
        removed = cleanup(name)
        if not removed['absent'] or (group and Path(group).exists()):
            raise RuntimeError('candidate cleanup unconfirmed; deadline reaper remains armed')
        result = {'host_confirmed': True, 'host_cgroup': group,
                  'host_cgroup_absent': bool(group and not Path(group).exists()),
                  'ordering': ['supervisor_stopped', 'container_absent', 'cgroup_absent']}
        if not group and (root / 'manifest.json').exists() and json.loads((root / 'manifest.json').read_text()).get('workspace'):
            result['host_cgroup_absent'] = True
            result['execution_not_started'] = True
        # Persist proof before disarming. A collector death before this point
        # cannot unload the timer; after this point no candidate can be created.
        write(root / 'cleanup-confirmed.json', result)
        command(['systemctl', 'stop', name + '-deadline.timer', name + '-deadline.service'], check=False)
        result['ordering'].append('deadline_units_stopped')
        end = time.monotonic() + 3
        while True:
            units = command(['systemctl', 'list-units', '--all', '--no-legend', name + '*'])
            if not units.stdout.strip(): break
            if time.monotonic() >= end: raise RuntimeError('run units remain after confirmed cleanup')
            time.sleep(.05)
        result['services_absent'] = True
        result['ordering'].append('units_absent')
        write(root / 'cleanup-confirmed.json', result)
        return result


def dispose(root, *, locked=False):
    with (nullcontext() if locked else registration_lock()):
        name = root.name
        containers = command(['docker', 'ps', '-aq', '--filter', 'name=^/' + name + '$'])
        units = command(['systemctl', 'list-units', '--all', '--no-legend', name + '*'])
        if containers.stdout.strip() or units.stdout.strip():
            raise RuntimeError('cannot dispose an active run or its deadline reaper')
        if not root.exists(): return
        proof = root / 'cleanup-confirmed.json'
        if not proof.exists(): raise RuntimeError('collect cleanup proof before disposal')
        group = json.loads(proof.read_text()).get('host_cgroup')
        if group and Path(group).exists(): raise RuntimeError('candidate cgroup remains')
        import shutil
        shutil.rmtree(root)


def reap(root):
    m = json.loads((root / 'manifest.json').read_text())
    deadline = time.monotonic() + 3
    try:
        command(['systemctl', 'kill', '--kill-whom=main', '--signal=SIGKILL',
                 m['name'] + '.service'], check=False, timeout=.5)
        result = cleanup(m['name'], deadline)
        registration = root / 'registration.json'
        if registration.exists():
            group = json.loads(registration.read_text())['cgroup']
            result['cgroup'] = group
            result['cgroup_absent'] = not Path(group).exists()
            result['absent'] = result['absent'] and result['cgroup_absent']
        if not result['absent']: raise RuntimeError('deadline cleanup not confirmed')
        write(root / 'reaped.json', result)
        command(['systemctl', 'stop', m['name'] + '-deadline.timer'], check=False)
    except Exception as exc:
        write(root / 'reaped.json', {'absent': False, 'error': repr(exc)})
        # This runs inside the dedicated machine, never on macOS or another VM.
        command(['systemctl', 'poweroff'], check=False)


def counters(pid):
    try:
        group = Path(f'/proc/{pid}/cgroup').read_text().strip().split('::', 1)[1]
        path = Path('/sys/fs/cgroup' + group)
        data = {}
        for file in ('cpu.stat', 'memory.events', 'pids.events'):
            for line in (path / file).read_text().splitlines():
                key, value = line.split()
                data[file + ':' + key] = int(value)
        if (path / 'memory.peak').exists():
            data['memory.peak'] = int((path / 'memory.peak').read_text())
        return str(path), data
    except (OSError, ValueError, IndexError):
        return None, {}


def supervise(root):
    m = json.loads((root / 'manifest.json').read_text())
    script = base64.b64decode(m['script']).decode('utf-8')
    name = m['name']
    r = {'run_id': m['run_id'], 'name': name, 'candidate_sha256': hashlib.sha256(script.encode()).hexdigest(),
         'image': m['image'], 'policy': m['policy'], 'status': 'infrastructure_failure',
         'exit_code': None, 'signal': None, 'timed_out': False, 'cancelled': False,
         'truncated': False, 'stdout': '', 'stderr': '', 'counters': {}, 'cgroup': None}
    if m.get('workspace'): r['workspace'] = m['workspace']
    if m.get('toolchain'): r['toolchain'] = m['toolchain']
    streams = {'stdout': bytearray(), 'stderr': bytearray()}
    p = None
    start = time.monotonic()
    try:
        selected = manifest_policy(m)
        args = ['docker', 'create', '--name', name, '--pull=never', '--user', '65534:65534',
                '--read-only', '--cap-drop=ALL', '--security-opt=no-new-privileges',
                '--network=none', '--cpus=1' if selected else '--cpus=.25',
                '--memory=1g' if selected else '--memory=64m',
                '--memory-swap=1g' if selected else '--memory-swap=64m',
                '--pids-limit=128' if selected else '--pids-limit=16',
                '--cgroup-parent=mo-application.slice' if selected else '--cgroup-parent=mo-executor.slice', '--log-driver=none',
                '--ipc=private', '--workdir=' + ('/workspace' if m.get('workspace') else '/work')]
        environment = application_environment() if selected else ['PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin']
        args += ['--env=' + value for value in environment]
        tmpfs = application_tmpfs() if selected else {path: 'rw,noexec,nosuid,size=8388608,mode=1777' for path in ('/work', '/tmp')}
        for path, options in tmpfs.items():
            args += ['--tmpfs', path + ':' + options]
        if m.get('workspace'):
            w = m['workspace']
            args += ['--volume', w['source'] + ':/workspace:' + ('ro' if w['readonly'] else 'rw')]
        args += [m['image'], '/bin/sh', '-c', script]
        r['container_id'] = command(args).stdout.decode().strip()
        r['cgroup'] = cgroup_path(r['container_id'], bool(selected))
        write(root / 'registration.json', {'container_id': r['container_id'], 'cgroup': r['cgroup']})
        r['effective'] = inspect(name)
        r['policy_errors'] = policy_errors(r['effective'], script, name, m.get('workspace'))
        if r['policy_errors']: raise RuntimeError('effective policy mismatch')
        if time.time() >= m['deadline']: raise RuntimeError('deadline expired before start')
        p = subprocess.Popen(['docker', 'start', '-a', name], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        sel = selectors.DefaultSelector()
        sel.register(p.stdout, selectors.EVENT_READ, 'stdout')
        sel.register(p.stderr, selectors.EVENT_READ, 'stderr')
        r['status'] = 'completed'
        next_sample = 0
        while sel.get_map():
            now = time.monotonic()
            if (root / 'cancel').exists():
                r.update(status='cancelled', cancelled=True)
                break
            if time.time() >= m['deadline']:
                r.update(status='timeout', timed_out=True)
                break
            if now >= next_sample:
                state = inspect(name)['State']
                path, values = counters(state['Pid'])
                if path: r['cgroup'] = path
                for key, value in values.items():
                    r['counters'][key] = max(value, r['counters'].get(key, 0))
                next_sample = now + .15
            for key, _ in sel.select(.05):
                chunk = os.read(key.fileobj.fileno(), 8192)
                if not chunk:
                    sel.unregister(key.fileobj)
                    continue
                remaining = CAP - sum(map(len, streams.values()))
                streams[key.data].extend(chunk[:remaining])
                if len(chunk) > remaining:
                    r.update(status='output_overflow', truncated=True)
                    break
            if r['truncated']: break
        if r['status'] != 'completed':
            command(['docker', 'kill', name], check=False)
        # Killing a container does not drain the attach client's pipe buffers.
        # Drain for at most the stop grace, retaining no bytes beyond the cap.
        drain_end = time.monotonic() + 2
        while sel.get_map() and time.monotonic() < drain_end:
            for key, _ in sel.select(.05):
                chunk = os.read(key.fileobj.fileno(), 8192)
                if not chunk:
                    sel.unregister(key.fileobj)
                    continue
                remaining = CAP - sum(map(len, streams.values()))
                streams[key.data].extend(chunk[:remaining])
                if len(chunk) > remaining: r['truncated'] = True
        sel.close()
        if p.poll() is None and time.monotonic() >= drain_end:
            p.kill()
        p.wait(timeout=2)
        r['attach_exit_code'] = p.returncode
        state = inspect(name)['State']
        r['exit_code'] = state['ExitCode'] if not state['Running'] else None
        r['oom_killed'] = state['OOMKilled']
        # Docker reports 128+signal but cannot distinguish it from explicit exit.
        r['signal_hint'] = r['exit_code'] - 128 if r['exit_code'] and 128 < r['exit_code'] <= 192 else None
        if state['Running']: raise RuntimeError('container still running after attach')
    except Exception as exc:
        r['status'] = 'infrastructure_failure'
        r['error'] = repr(exc)
    finally:
        try:
            r['cleanup'] = cleanup(name)
            group = r.get('cgroup')
            r['cleanup']['cgroup_absent'] = bool(group and not Path(group).exists())
            if not r['cleanup']['absent']: r['status'] = 'infrastructure_failure'
        except Exception as exc:
            r['cleanup'] = {'absent': False, 'error': repr(exc)}
            r['status'] = 'infrastructure_failure'
        if p:
            if p.poll() is None: p.kill()
            p.wait(timeout=2)
            p.stdout.close()
            p.stderr.close()
        for key, value in streams.items(): r[key] = base64.b64encode(value).decode()
        r['elapsed_seconds'] = time.monotonic() - start
        write(root / 'observation.json', r)


if __name__ == '__main__':
    mode, directory = sys.argv[1:]
    root = Path(directory)
    if mode == 'supervise': supervise(root)
    elif mode == 'reap': reap(root)
    else: raise SystemExit('unknown mode')
