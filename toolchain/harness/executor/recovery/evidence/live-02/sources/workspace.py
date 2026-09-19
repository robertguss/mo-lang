"""Trusted caller API for bounded session workspaces on mo-executor-r01."""
import base64
import hashlib
import json
from pathlib import Path
import time
import uuid
import threading
import os
from contextlib import contextmanager

from adapter import Run, remote, validate_checks, verify
from remote import CAP, IMAGE, WORKSPACE_POLICY, policy_errors, selection, workspace_selection, manifest_policy
import workspace_files as files
from workspace_controller import digest


def execution_result(manifest, observation):
    identity = all(observation.get(k) == manifest[k] for k in
                   ('run_id', 'name', 'candidate_sha256', 'image', 'policy', 'workspace'))
    try:
        manifest_policy(manifest)
        if manifest.get('toolchain') != observation.get('toolchain'):
            raise ValueError('toolchain identity mismatch')
        script = base64.b64decode(manifest['script']).decode()
        valid = not policy_errors(observation['effective'], script, manifest['name'], manifest['workspace'])
        valid = valid and observation['container_id'] == observation['effective']['Id']
        streams = {key: base64.b64decode(observation[key], validate=True) for key in ('stdout', 'stderr')}
        valid = valid and sum(map(len, streams.values())) <= CAP
    except (KeyError, ValueError, TypeError):
        valid, streams = False, {'stdout': b'', 'stderr': b''}
    cleanup = observation.get('cleanup', {})
    cleaned = all(cleanup.get(k) is True for k in
                  ('absent', 'cgroup_absent', 'host_confirmed', 'host_cgroup_absent', 'services_absent'))
    complete = all(k in observation for k in ('exit_code', 'signal', 'timed_out', 'cancelled', 'truncated'))
    valid = bool(identity and valid and cleaned and complete and not any(observation.get(k) for k in ('error', 'controller_error', 'cleanup_error')))
    state = ('refusal' if observation.get('status') == 'refusal' and
             observation.get('execution') == 'not_started' and cleanup.get('host_confirmed') is True and
             cleanup.get('services_absent') is True else 'failure')
    if valid:
        if observation['cancelled']:
            state = 'cancellation'
        elif observation['timed_out']:
            state = 'timeout'
        elif observation.get('status') == 'completed' and observation['exit_code'] == 0 and not observation['truncated']:
            state = 'success'
    return {'run_id': manifest['workspace'].get('workspace_run_id'),
            'workspace_id': manifest['workspace'].get('workspace_id'),
            'call_id': manifest.get('workspace_call_id'), 'state': state, 'execution': 'completed' if valid else ('not_started' if observation.get('execution') == 'not_started' and cleaned else 'unknown'),
            'exit_code': observation.get('exit_code'), 'signal': observation.get('signal'),
            'stdout': base64.b64encode(streams['stdout']).decode(),
            'stderr': base64.b64encode(streams['stderr']).decode(), 'encoding': 'base64',
            'truncated': observation.get('truncated', False),
            'elapsed_seconds': observation.get('elapsed_seconds'),
            'execution_valid': valid, 'manifest': manifest, 'observation': observation}


class WorkspaceRun(Run):
    """Existing Run lifecycle, with separate feedback and behavioral results."""
    def __init__(self, script, result_dir, seconds, workspace, checks=None):
        if checks is not None:
            validate_checks(checks)
        self._initialize(script, checks, result_dir, seconds, workspace)
        self.manifest.update(policy=workspace_selection(workspace).get('policy', WORKSPACE_POLICY), workspace=workspace,
                             workspace_verifier='mo-workspace-verifier-v1',
                             workspace_verifier_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                             check_inventory_sha256=digest(checks) if checks is not None else None)
        self.persist()

    def persist(self):
        (self.directory / 'manifest.json').write_text(json.dumps(self.manifest, indent=2))

    def _verify_result(self, observation):
        result = execution_result(self.manifest, observation)
        if self.manifest['checks'] is not None:
            behavioral = verify(self.manifest, observation)
            result['checks'] = behavioral['checks']
            result['passed'] = bool(behavioral['passed'] and result['execution_valid'] and
                                    self.manifest['workspace']['readonly'] and self.manifest['workspace']['snapshot'] and
                                    self.manifest['check_inventory_sha256'] == digest(self.manifest['checks']))
        return result


class Workspace:
    def __init__(self, run_id, result_dir, *, policy=WORKSPACE_POLICY, image=IMAGE, toolchain=None):
        from workspace_controller import identity
        self.run_id = identity(run_id)
        self.selection = selection(policy, image, toolchain)
        self.workspace_id = uuid.uuid4().hex
        self.directory = Path(result_dir)
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=False)
        self.active = None
        self.snapshot = None
        self._calls = set()
        self._owner_mutex = threading.RLock()
        from recovery import initialize
        initialize(self)

    def __del__(self):
        fd = getattr(self, '_ownership_fd', None)
        if fd is not None:
            os.close(fd)
            self._ownership_fd = None

    @contextmanager
    def _ownership(self):
        # The file lock belongs to the object lifetime, including the interval
        # between start_command and collect. The mutex serializes its threads.
        with self._owner_mutex:
            if self._ownership_fd is None or (self.directory / 'recovery-requested').exists():
                raise files.Refusal('recovery_closed')
            yield

    def call(self, operation, args=None, *, call_id=None, seconds=30):
        with self._ownership():
            from workspace_controller import identity
            call_id = identity(call_id or uuid.uuid4().hex)
            if call_id in self._calls:
                raise files.Refusal('duplicate_call')
            if not isinstance(seconds, (int, float)) or not .5 <= seconds <= 60:
                raise files.Refusal('deadline')
            self._calls.add(call_id)
            request = {'run_id': self.run_id, 'workspace_id': self.workspace_id, 'call_id': call_id,
                       'operation': operation, 'args': args or {}, 'deadline': time.time() + seconds}
            attempt = self.directory / ('call-' + call_id)
            attempt.mkdir(mode=0o700)
            (attempt / 'request.json').write_text(json.dumps(request))
            sources = {name: Path(__file__).with_name(name + '.py').read_text()
                       for name in ('remote', 'workspace_files', 'workspace_controller')}
            bootstrap = """import json,sys,types
    payload=json.load(sys.stdin)
    for name,source in payload['sources'].items():
     module=types.ModuleType(name); sys.modules[name]=module; exec(compile(source,name+'.py','exec'),module.__dict__)
    print(json.dumps(sys.modules['workspace_controller'].handle(payload['request'])))
    """
            try:
                raw = remote(['python3', '-c', bootstrap], data=json.dumps({'sources': sources, 'request': request}).encode(), timeout=seconds + 5)
                result = json.loads(raw)
                if any(result.get(k) != request[k] for k in ('run_id', 'workspace_id', 'call_id')):
                    raise RuntimeError('mismatched response identity')
            except Exception:
                result = {k: request[k] for k in ('run_id', 'workspace_id', 'call_id')}
                result.update(state='failure', execution='unknown', error='transport_unknown')
                (attempt / 'result.json').write_text(json.dumps(result, indent=2))
                raise
            (attempt / 'result.json').write_text(json.dumps(result, indent=2))
            return result

    def require(self, operation, args=None, **kwargs):
        result = self.call(operation, args, **kwargs)
        if result['state'] != 'success':
            raise files.Refusal(result.get('error', result['state']))
        return result['result']

    def create(self, mapping, **kwargs):
        entries = list(mapping.items()) if isinstance(mapping, dict) else mapping
        files.validate_import(entries)
        args = {'files': [(path, base64.b64encode(data).decode()) for path, data in entries]}
        if self.selection:
            args['selection'] = dict(self.selection)
        return self.require('create', args, **kwargs)

    def list_files(self, path='.', **kwargs):
        return self.require('list_files', {'path': path}, **kwargs)

    def read_file(self, path, **kwargs):
        return self.require('read_file', {'path': path}, **kwargs)['text']

    def search(self, text, path='.', **kwargs):
        return self.require('search', {'path': path, 'text': text}, **kwargs)

    def write_file(self, path, text, **kwargs):
        return self.require('write_file', {'path': path, 'text': text}, **kwargs)

    def exact_edit(self, path, old, new, **kwargs):
        return self.require('exact_edit', {'path': path, 'old': old, 'new': new}, **kwargs)

    def _prepare_command(self, script, *, checks=None, seconds=10, call_id=None):
        with self._ownership():
            call_id = call_id or uuid.uuid4().hex
            readonly = checks is not None
            if readonly:
                validate_checks(checks)
            if self.active:
                raise files.Refusal('cleanup_required')
            # Initialize identity before reserving dispatch; no dummy behavioral checks.
            run = WorkspaceRun(script, self.directory / ('execution-' + uuid.uuid4().hex), seconds, self.selection, checks)
            from recovery import intent
            intent(self, run, call_id, readonly)
            reserved = self.require('reserve', {'execution_id': run.manifest['run_id'], 'readonly': readonly,
                                             'selection': self.selection}, call_id=call_id)
            run.manifest['workspace'] = reserved['workspace']
            # A changed local selection cannot widen a previously registered workspace.
            manifest_policy(run.manifest)
            run.manifest['workspace_call_id'] = call_id
            run.persist()
            self.active = run
            return run

    def start_command(self, script, *, checks=None, seconds=10, call_id=None):
        with self._ownership():
            run = self._prepare_command(script, checks=checks, seconds=seconds, call_id=call_id)
            from recovery import persist
            self.ownership['executions'][-1]['dispatch_requested'] = True
            persist(self)
            run.start()
            return run

    def collect(self):
        with self._ownership():
            if not self.active:
                raise files.Refusal('not_started')
            run = self.active
            result = run.collect()
            self.require('complete', {'execution_id': run.manifest['run_id']})
            run.dispose()
            self.active = None
            return result

    def command(self, script, *, seconds=10, call_id=None):
        call_id = call_id or uuid.uuid4().hex
        previous = self.active
        try:
            self.start_command(script, seconds=seconds, call_id=call_id)
        except ValueError:
            if self.active and self.active is not previous:
                return self.collect()
            return {'run_id': self.run_id, 'workspace_id': self.workspace_id, 'call_id': call_id,
                    'state': 'refusal', 'execution': 'not_started', 'error': 'request_refused',
                    'exit_code': None, 'signal': None, 'stdout': '', 'stderr': '',
                    'encoding': 'base64', 'truncated': False, 'elapsed_seconds': 0,
                    'execution_valid': False}
        except Exception:
            if self.active and self.active is not previous:
                return self.collect()
            raise
        return self.collect()

    def cancel(self, **kwargs):
        return self.require('cancel', **kwargs)

    def freeze(self, **kwargs):
        result = self.require('freeze', **kwargs)
        self.snapshot = result['snapshot']
        return result

    def verify(self, script, checks, *, seconds=10, call_id=None):
        validate_checks(checks)
        previous = self.active
        try:
            self.start_command(script, checks=checks, seconds=seconds, call_id=call_id)
        except Exception:
            if self.active and self.active is not previous:
                self.collect()
            raise
        return self.collect()

    def delete(self, **kwargs):
        result = self.require('delete', **kwargs)
        self.__del__()
        return result
