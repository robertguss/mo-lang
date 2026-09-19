"""Small, single-candidate executor for the dedicated mo-executor-r01 machine."""
import base64
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import uuid

from remote import CAP, IMAGE, POLICY, Invalid, policy_errors, manifest_policy, workspace_selection

MACHINE = 'mo-executor-r01'
VERIFIER = 'mo-executor-external-checks-v1'
HERE = Path(__file__).resolve().parent

# The one machine-side loader: trusted module sources arrive on stdin as
# {'sources': {name: text}, ...}; each becomes an importable module.
LOAD = '''import json,sys,types
p=json.load(sys.stdin)
for name,source in p['sources'].items():
 m=types.ModuleType(name);sys.modules[name]=m;exec(compile(source,name+'.py','exec'),m.__dict__)
'''


def sources(*names):
    return {name: (HERE / (name + '.py')).read_text() for name in names}


def machine_call(modules, call, payload, timeout):
    """Load trusted modules on the machine, then print the JSON of `call`, an
    expression over p (the payload). Returns the raw reply bytes."""
    data = json.dumps({**payload, 'sources': modules}).encode()
    return remote(['python3', '-c', LOAD + 'print(json.dumps(' + call + '))'], data=data, timeout=timeout)


def remote(args, data=None, timeout=6):
    p = subprocess.run(['orbctl', 'run', '-m', MACHINE, '-u', 'root', *args],
                       input=data, capture_output=True, timeout=timeout)
    if p.returncode:
        raise RuntimeError(f'remote rc={p.returncode}: {p.stderr[:2048]!r}')
    return p.stdout


def py(source, *args, data=None):
    return remote(['python3', '-c', source, *args], data=data)


def validate_checks(checks):
    if not isinstance(checks, list) or not checks:
        raise Invalid('a nonempty external check inventory is required')
    names = set()
    for c in checks:
        if set(c) != {'id', 'stream', 'mode', 'expected'} or not isinstance(c['id'], str) or not c['id']:
            raise Invalid('invalid check')
        if c['id'] in names or c['stream'] not in ('stdout', 'stderr') or c['mode'] not in ('exact', 'contains'):
            raise Invalid('invalid/duplicate check')
        if not isinstance(c['expected'], str) or not c['expected'] or len(c['expected'].encode()) > CAP:
            raise Invalid('empty or oversized expectation')
        names.add(c['id'])


def verify(manifest, observation):
    """Never reuse a candidate's verdict; every expected check is external."""
    validate_checks(manifest['checks'])
    identity = all(observation.get(k) == manifest[k] for k in
                   ('run_id', 'name', 'candidate_sha256', 'image', 'policy'))
    script = base64.b64decode(manifest['script']).decode()
    try:
        manifest_policy(manifest)
        if manifest.get('toolchain') != observation.get('toolchain'):
            raise ValueError('toolchain identity mismatch')
        policy = not policy_errors(observation['effective'], script, manifest['name'], manifest.get('workspace'))
        policy = policy and observation['container_id'] == observation['effective']['Id']
        outputs = {s: base64.b64decode(observation[s], validate=True) for s in ('stdout', 'stderr')}
        bounded = sum(map(len, outputs.values())) <= CAP
    except (KeyError, ValueError, TypeError):
        policy, bounded, outputs = False, False, {'stdout': b'', 'stderr': b''}
    checks = []
    for c in manifest['checks']:
        expected, actual = c['expected'].encode(), outputs[c['stream']]
        ok = expected == actual if c['mode'] == 'exact' else expected in actual
        checks.append({**c, 'passed': ok})
    cleanup = observation.get('cleanup', {})
    complete = all(key in observation for key in ('exit_code', 'signal', 'timed_out', 'cancelled', 'truncated'))
    passed = (identity and policy and bounded and complete and
              observation.get('status') == 'completed' and observation.get('exit_code') == 0 and
              not any(observation.get(k) for k in ('timed_out', 'cancelled', 'truncated', 'error', 'controller_error', 'cleanup_error')) and
              cleanup.get('absent') is True and cleanup.get('cgroup_absent') is True and cleanup.get('host_confirmed') is True and cleanup.get('services_absent') is True and cleanup.get('host_cgroup_absent') is True and
              all(c['passed'] for c in checks))
    return {'passed': bool(passed), 'verifier': VERIFIER, 'identity_valid': identity,
            'policy_valid': policy, 'checks': checks, 'observation': observation,
            'manifest': manifest}


class Run:
    def __init__(self, script, checks, result_dir, seconds=10):
        validate_checks(checks)
        self._initialize(script, checks, result_dir, seconds)

    def _initialize(self, script, checks, result_dir, seconds, workspace=None):
        if not isinstance(script, str) or not script or len(script.encode()) > 32768 or '\0' in script:
            raise Invalid('fixture must be nonempty UTF-8 text, <=32 KiB, without NUL')
        selected = workspace_selection(workspace)
        maximum = 120 if selected else 10
        if type(seconds) not in (int, float) or not .5 <= seconds <= maximum:
            raise Invalid('deadline must be .5..' + str(maximum) + ' seconds')
        self.directory = Path(result_dir)
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=False)
        os.chmod(self.directory, 0o700)
        run_id = uuid.uuid4().hex
        self.name = 'mo-executor-' + run_id
        self.root = '/tmp/' + self.name
        self.manifest = {'run_id': run_id, 'name': self.name, 'image': IMAGE, 'policy': POLICY,
                         'candidate_sha256': hashlib.sha256(script.encode()).hexdigest(),
                         'script': base64.b64encode(script.encode()).decode(), 'checks': json.loads(json.dumps(checks)),
                         'seconds': seconds, 'verifier': VERIFIER,
                         'adapter_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                         'supervisor_sha256': hashlib.sha256(Path(__file__).with_name('remote.py').read_bytes()).hexdigest()}
        self.manifest.update(selected)
        (self.directory / 'manifest.json').write_text(json.dumps(self.manifest, indent=2))

    @contextmanager
    def _lifecycle(self):
        with (self.directory / 'lifecycle.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            yield

    def start(self):
        with self._lifecycle():
            if any((self.directory / p).exists() for p in ('start-requested', 'closed')):
                raise RuntimeError('run is one-shot; start already requested or lifecycle closed')
            (self.directory / 'start-requested').touch()
            return self._start()

    def _start(self):
        # flock covers registration; a prior live run must expire before another starts.
        names = ('remote', 'workspace_files', 'workspace_controller') if 'workspace' in self.manifest else ('remote',)
        payload = json.dumps({'sources': sources(*names), 'manifest': self.manifest}).encode()
        self.manifest = json.loads(py(BOOTSTRAP, self.root, data=payload))
        (self.directory / 'manifest.json').write_text(json.dumps(self.manifest, indent=2))
        return self

    def cancel(self):
        py("from pathlib import Path; import sys; Path(sys.argv[1], 'cancel').touch()", self.root)

    def collect(self):
        with self._lifecycle():
            if (self.directory / 'disposed').exists():
                raise RuntimeError('run already disposed; read the retained host result')
            (self.directory / 'closed').touch()
            return self._collect()

    def _collect(self):
        """Bounded wait, then verify daemon absence before publishing a host verdict."""
        end = time.monotonic() + self.manifest['seconds'] + 10
        observation = None
        try:
            while time.monotonic() < end:
                raw = py("from pathlib import Path; import sys; p=Path(sys.argv[1],'observation.json'); print(p.read_text() if p.exists() else ('{\"status\":\"infrastructure_failure\",\"error\":\"supervisor observation missing\"}' if Path(sys.argv[1], 'reaped.json').exists() else '{}'))", self.root)
                observation = json.loads(raw)
                if observation: break
                time.sleep(.1)
            if not observation:
                observation = {'status': 'infrastructure_failure', 'error': 'supervisor observation missing'}
        except Exception as exc:
            observation = observation or {'status': 'infrastructure_failure'}
            observation['controller_error'] = repr(exc)
        try:
            confirmation = json.loads(py("import sys,json; sys.path.insert(0,sys.argv[1]); from remote import finalize_report; from pathlib import Path; print(json.dumps(finalize_report(Path(sys.argv[1]))))", self.root))
            observation.setdefault('cleanup', {}).update(confirmation)
            if not confirmation['host_confirmed']:
                raise RuntimeError('candidate or run service remains after cleanup')
        except Exception as exc:
            observation['status'] = 'infrastructure_failure'
            observation['cleanup_error'] = repr(exc)
            # Unconfirmed cleanup leaves the evidence and the armed reaper. Only a
            # proven escape stops the dedicated machine; never an unqualified OrbStack stop.
            if observation.get('cleanup', {}).get('containment_failed') is True:
                stopped = subprocess.run(['orbctl', 'stop', MACHINE], capture_output=True, timeout=10)
                observation['machine_stop_rc'] = stopped.returncode
        result = self._verify_result(observation)
        (self.directory / 'result.json').write_text(json.dumps(result, indent=2))
        for stream in ('stdout', 'stderr'):
            (self.directory / (stream + '.bin')).write_bytes(base64.b64decode(observation.get(stream, '')))
        return result

    def _verify_result(self, observation):
        return verify(self.manifest, observation)

    def dispose(self):
        """Delete machine evidence only after collection's positive cleanup proof."""
        with self._lifecycle():
            if (self.directory / 'disposed').exists(): return
            (self.directory / 'closed').touch()
            py("import sys; sys.path.insert(0,sys.argv[1]); from remote import dispose; from pathlib import Path; dispose(Path(sys.argv[1]))", self.root)
            (self.directory / 'disposed').touch()


# Machine-side registration, run as `python3 -c LOAD+BOOTSTRAP /tmp/<name>`. The
# name is validated before the lock, the run directory or any systemd unit.
BOOTSTRAP = LOAD + '''import fcntl,pathlib,subprocess,time
m=p['manifest']; root=pathlib.Path(sys.argv[1]); remote=sys.modules['remote']
name=remote.run_name(m['name'])
if root!=pathlib.Path('/tmp',name): raise remote.Invalid('run directory differs from run name')
with open('/tmp/mo-executor-registration.lock','w') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 if 'workspace' in m:
  sys.modules['workspace_controller'].bootstrap_barrier(m)
 units=subprocess.run(['systemctl','list-units','--all','--no-legend','mo-executor-*.timer'],capture_output=True,check=True).stdout
 containers=subprocess.run(['docker','ps','-aq','--filter','name=^/mo-executor-'],capture_output=True,check=True).stdout
 if units.strip() or containers.strip(): raise RuntimeError('another candidate is registered')
 root.mkdir(mode=0o700)
 for module, source in p['sources'].items(): (root/(module+'.py')).write_text(source)
 if 'workspace' in m:
  (root/'manifest.json').write_text(json.dumps(m))
  try: sys.modules['workspace_controller'].authorize(m)
  except Exception:
   (root/'observation.json').write_text(json.dumps({'status':'refusal','execution':'not_started','error':'workspace_authorization_refused'}))
   raise
 m['deadline']=time.time()+m['seconds']
 (root/'manifest.json').write_text(json.dumps(m))
 subprocess.run(['systemd-run','--quiet','--collect','--unit='+name+'-deadline','--on-active='+str(m['seconds']+2)+'s','--timer-property=AccuracySec=100ms','--property=TimeoutStartSec=8s','/usr/bin/python3',str(root/'remote.py'),'reap',str(root)],check=True)
 if time.time() >= m['deadline']: raise RuntimeError('registration deadline expired before supervisor dispatch')
 subprocess.run(['systemd-run','--quiet','--collect','--unit='+name,'--property=RuntimeMaxSec='+str(m['seconds']+2)+'s','--property=TimeoutStopSec=2s','--property=KillMode=control-group','--property=ExecStopPost=-/usr/bin/docker rm -f '+name,'/usr/bin/python3',str(root/'remote.py'),'supervise',str(root)],check=True)
 print(json.dumps(m))
'''
