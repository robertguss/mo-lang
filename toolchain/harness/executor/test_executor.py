import base64
import copy
import tempfile
import json
import subprocess
import unittest
from pathlib import Path
from contextlib import nullcontext
import threading
from unittest.mock import patch

from adapter import Run, validate_checks, verify
from remote import CAP, IMAGE, REAP_ATTEMPTS, cgroup_path, cleanup, policy_errors, reap, finalize, run_name

NAME = 'mo-executor-' + 'a' * 32


def check(expected='ok\n', name='output', mode='exact', stream='stdout'):
    return {'id': name, 'expected': expected, 'stream': stream, 'mode': mode}


class ExecutorTests(unittest.TestCase):
    def test_rejects_empty_missing_duplicate_and_vacuous_checks(self):
        for checks in (None, [], [{}], [check('')], [check(), check()], [check('x' * (CAP + 1))]):
            with self.subTest(checks=str(checks)[:60]), self.assertRaises(ValueError):
                validate_checks(checks)

    def test_rejects_bad_fixtures_and_deadlines(self):
        with tempfile.TemporaryDirectory() as root:
            for script, seconds in (('', 1), ('x\0', 1), ('x' * 32769, 1), ('ok', 0), ('ok', 11), ('ok', float('nan'))):
                with self.subTest(script=script[:10], seconds=seconds), self.assertRaises(ValueError):
                    Run(script, [check()], Path(root) / 'run', seconds)

    def observation(self, manifest):
        return {**{k: manifest[k] for k in ('run_id', 'name', 'candidate_sha256', 'image', 'policy')},
                'effective': {'Id': 'container'}, 'container_id': 'container',
                'stdout': base64.b64encode(b'ok\n').decode(), 'stderr': '',
                'status': 'completed', 'exit_code': 0, 'signal': None,
                'timed_out': False, 'cancelled': False, 'truncated': False,
                'cleanup': {'absent': True, 'cgroup_absent': True, 'host_confirmed': True, 'services_absent': True, 'host_cgroup_absent': True}}

    @patch('adapter.policy_errors', return_value=[])
    def test_external_verifier_rejects_missing_observations_stale_forged_and_wrong_results(self, _):
        with tempfile.TemporaryDirectory() as root:
            run = Run('echo ok', [check()], Path(root) / 'run')
            m = run.manifest
            obs = self.observation(m)
            self.assertTrue(verify(m, obs)['passed'])
            mutations = [('run_id', 'stale'), ('candidate_sha256', 'stale'), ('name', 'stale'),
                         ('image', 'other'), ('policy', 'other'), ('container_id', 'other'),
                         ('stdout', base64.b64encode(b'{"passed":true}\n').decode()),
                         ('exit_code', 1), ('status', 'timeout'), ('truncated', True),
                         ('cancelled', True), ('timed_out', True), ('cleanup', {}), ('controller_error', 'failed'),
                         ('stdout', base64.b64encode(b'x'*(CAP+1)).decode())]
            for key, value in mutations:
                bad = copy.deepcopy(obs); bad[key] = value
                with self.subTest(key=key): self.assertFalse(verify(m, bad)['passed'])
            for key in obs:
                bad = copy.deepcopy(obs); del bad[key]
                with self.subTest(missing=key): self.assertFalse(verify(m, bad)['passed'])

    @patch('adapter.policy_errors', return_value=[])
    def test_absent_fault_stimulus_and_prior_success_do_not_pass(self, _):
        with tempfile.TemporaryDirectory() as root:
            a = Run('echo ok', [check()], Path(root) / 'a')
            b = Run('echo ok', [check()], Path(root) / 'b')
            obs = self.observation(a.manifest)
            self.assertFalse(verify(b.manifest, obs)['passed'])
            a.manifest['checks'].append(check('fault-ran', 'fault-stimulus', 'contains'))
            self.assertFalse(verify(a.manifest, obs)['passed'])

    def test_policy_rejects_effective_security_drift(self):
        # Real effective Docker record, retained from the successful fixture smoke.
        path = Path(__file__).parent / 'evidence/smoke-02/positive/result.json'
        baseline = json.loads(path.read_text())['observation']['effective']
        script, name = 'echo ok', baseline['Name'][1:]
        self.assertEqual(policy_errors(baseline, script, name), [])
        changes = {'ReadonlyRootfs': False, 'Privileged': True, 'NetworkMode': 'bridge',
                   'NanoCpus': 0, 'Memory': 0, 'MemorySwap': -1, 'PidsLimit': 0,
                   'CgroupParent': '', 'CapDrop': [], 'CapAdd': ['SYS_ADMIN'],
                   'Binds': ['/tmp:/tmp'], 'Devices': ['device'], 'SecurityOpt': [],
                   'PidMode': 'host', 'IpcMode': 'host', 'CgroupnsMode': 'host',
                   'LogConfig': {'Type': 'json-file'}, 'Tmpfs': {},
                   'VolumesFrom': ['other'], 'DeviceRequests': ['device'],
                   'RestartPolicy': {'Name': 'always'}, 'AutoRemove': True}
        for key, value in changes.items():
            bad = copy.deepcopy(baseline); bad['HostConfig'][key] = value
            with self.subTest(key=key): self.assertIn(key, policy_errors(bad, script, name))
        for key, value in {'User': '0', 'Cmd': ['echo', 'other'], 'Env': ['SECRET=x'],
                           'Entrypoint': ['other'], 'WorkingDir': '/'}.items():
            bad = copy.deepcopy(baseline); bad['Config'][key] = value
            with self.subTest(key=key): self.assertIn(key, policy_errors(bad, script, name))

    @patch('remote.command')
    def test_cgroup_path_uses_systemd_hierarchy(self, command):
        command.return_value = subprocess.CompletedProcess([], 0, b'/mo.slice/mo-executor.slice\n', b'')
        self.assertEqual(cgroup_path('abc'), '/sys/fs/cgroup/mo.slice/mo-executor.slice/docker-abc.scope')

    def reaper_root(self, directory, populated=None):
        root = Path(directory)
        (root / 'manifest.json').write_text(json.dumps({'name': NAME}))
        group = root / 'candidate-cgroup'
        if populated is not None:
            group.mkdir()
            (group / 'cgroup.events').write_text(f'populated {int(populated)}\nfrozen 0\n')
        (root / 'registration.json').write_text(json.dumps({'container_id': 'abc', 'cgroup': str(group)}))
        return root

    @patch('remote.command')
    def test_reaper_cleanup_timeout_reports_unconfirmed_without_poweroff(self, command):
        def machine(args, **kwargs):
            if args[0] == 'docker': raise subprocess.TimeoutExpired(args, kwargs.get('timeout'))
            return subprocess.CompletedProcess(args, 0, b'', b'')
        command.side_effect = machine
        with tempfile.TemporaryDirectory() as directory:
            root = self.reaper_root(directory, populated=False)
            reap(root)
            record = json.loads((root / 'reaped.json').read_text())
        calls = [c.args[0] for c in command.call_args_list]
        self.assertNotIn(['systemctl', 'poweroff'], calls)
        self.assertEqual(record['containment'], 'cleanup_unconfirmed')
        self.assertFalse(record['absent'])
        self.assertTrue(1 < len(record['attempts']) <= REAP_ATTEMPTS)
        self.assertEqual(len([c for c in calls if c[:3] == ['docker', 'rm', '-f']]), len(record['attempts']))
        self.assertNotIn(['systemctl', 'stop', NAME + '-deadline.timer'], calls)

    @patch('remote.cleanup', return_value={'absent': False, 'removed_rc': 1})
    @patch('remote.command')
    def test_reaper_powers_off_only_on_proven_containment_failure(self, command, cleanup):
        command.return_value = subprocess.CompletedProcess([], 0, b'', b'')
        with tempfile.TemporaryDirectory() as directory:
            root = self.reaper_root(directory, populated=True)
            reap(root)
            record = json.loads((root / 'reaped.json').read_text())
        self.assertEqual(record['containment'], 'failed')
        self.assertIn(['systemctl', 'poweroff'], [c.args[0] for c in command.call_args_list])

    @patch('remote.cleanup', side_effect=RuntimeError('programming error'))
    @patch('remote.command')
    def test_reaper_unknown_error_is_unconfirmed_not_poweroff(self, command, cleanup):
        command.return_value = subprocess.CompletedProcess([], 0, b'', b'')
        with tempfile.TemporaryDirectory() as directory:
            root = self.reaper_root(directory)
            reap(root)
            record = json.loads((root / 'reaped.json').read_text())
        self.assertEqual(record['containment'], 'cleanup_unconfirmed')
        self.assertIn('programming error', record['attempts'][0]['error'])
        self.assertNotIn(['systemctl', 'poweroff'], [c.args[0] for c in command.call_args_list])

    @patch('remote.command')
    def test_cleanup_timeout_is_a_result_not_an_exception(self, command):
        command.side_effect = subprocess.TimeoutExpired(['docker'], 2)
        result = cleanup(NAME)
        self.assertFalse(result['absent'])
        self.assertIn('TimeoutExpired', result['error'])

    @patch('adapter.py', side_effect=RuntimeError('machine unavailable'))
    @patch('adapter.subprocess.run')
    def test_host_cleanup_unknown_fails_closed_without_stopping_machine(self, command, remote_python):
        with tempfile.TemporaryDirectory() as root:
            run = Run('echo ok', [check()], Path(root) / 'run')
            result = run.collect()
            self.assertFalse(result['passed'])
            self.assertEqual(result['observation']['status'], 'infrastructure_failure')
            self.assertIn('cleanup_error', result['observation'])
            command.assert_not_called()

    @patch('adapter.subprocess.run')
    def test_host_stops_only_named_machine_on_proven_containment_failure(self, command):
        command.return_value = subprocess.CompletedProcess([], 0, b'', b'')
        with tempfile.TemporaryDirectory() as root:
            run = Run('echo ok', [check()], Path(root) / 'run')
            def machine(source, *args, **kwargs):
                if 'observation.json' in source: return b'{"status": "infrastructure_failure"}'
                return json.dumps({'host_confirmed': False, 'containment_failed': True}).encode()
            with patch('adapter.py', side_effect=machine): result = run.collect()
            self.assertFalse(result['passed'])
            self.assertEqual(command.call_args.args[0], ['orbctl', 'stop', 'mo-executor-r01'])

    def test_machine_rejects_run_names_before_systemd(self):
        bad = ['mo-executor-' + 'a' * 31, 'mo-executor-' + 'A' * 32, 'mo-executor-' + 'a' * 32 + '\n',
               'mo-executor-' + 'a' * 32 + ' /bin/sh -c id', 'x', None]
        for name in bad:
            with self.subTest(name=name), self.assertRaises(ValueError):
                run_name(name)
        self.assertEqual(run_name(NAME), NAME)

    def test_bootstrap_refuses_invalid_name_before_lock_or_systemd(self):
        import builtins, io, sys
        import adapter
        manifest = {'name': 'mo-executor-' + 'a' * 32 + ' /bin/sh -c id', 'seconds': 1}
        payload = json.dumps({'sources': {'remote': Path(adapter.__file__).with_name('remote.py').read_text()},
                              'manifest': manifest})
        opened = []
        def fake_open(path, *args, **kwargs):
            opened.append(path)
            return io.StringIO()
        namespace = {'__name__': '__main__', '__builtins__': {**builtins.__dict__, 'open': fake_open}}
        saved = {name: sys.modules.get(name) for name in ('remote',)}
        try:
            with tempfile.TemporaryDirectory() as directory, \
                    patch.object(sys, 'argv', ['-c', str(Path(directory) / 'root')]), \
                    patch.object(sys, 'stdin', io.StringIO(payload)), \
                    patch('subprocess.run') as run, patch('fcntl.flock'):
                with self.assertRaises(ValueError):
                    exec(adapter.BOOTSTRAP, namespace)
                self.assertFalse((Path(directory) / 'root').exists())
            run.assert_not_called()
            self.assertEqual(opened, [])
        finally:
            for name, module in saved.items():
                if module is None: sys.modules.pop(name, None)
                else: sys.modules[name] = module

    @patch('remote.command')
    def test_reaper_refuses_invalid_name_before_systemd(self, command):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'manifest.json').write_text(json.dumps({'name': 'x; poweroff'}))
            with self.assertRaises(ValueError): reap(root)
        command.assert_not_called()

    def test_caller_check_mutation_does_not_change_registered_inventory(self):
        with tempfile.TemporaryDirectory() as root:
            checks = [check()]
            run = Run('echo ok', checks, Path(root) / 'run')
            checks[0]['expected'] = 'forged'
            self.assertEqual(run.manifest['checks'][0]['expected'], 'ok\n')

    @patch('adapter.subprocess.run')
    def test_collector_never_unconditionally_stops_deadline_before_proof(self, command):
        command.return_value = subprocess.CompletedProcess([], 0, b'', b'')
        with tempfile.TemporaryDirectory() as root:
            run = Run('echo ok', [check()], Path(root) / 'run')
            observation = self.observation(run.manifest)
            unsafe = []
            def machine(source, *args, **kwargs):
                if 'observation.json' in source: return json.dumps(observation).encode()
                if "'stop'" in source and '-deadline.timer' in source: unsafe.append(source)
                return json.dumps({'host_confirmed': True, 'host_cgroup_absent': True,
                                   'services_absent': True}).encode()
            with patch('adapter.py', side_effect=machine): run.collect()
            self.assertEqual(unsafe, [], 'collector disarmed deadline without cleanup proof')

    @patch('remote.registration_lock', return_value=nullcontext())
    @patch('remote.cleanup', return_value={'absent': False, 'removed_rc': 1})
    @patch('remote.command')
    def test_finalizer_keeps_reaper_armed_when_removal_is_uncertain(self, command, cleanup, lock):
        command.return_value = subprocess.CompletedProcess([], 0, b'', b'')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / NAME; root.mkdir()
            with self.assertRaisesRegex(RuntimeError, 'reaper remains armed'):
                finalize(root)
            self.assertFalse((root / 'cleanup-confirmed.json').exists())
        stopped = [c.args[0] for c in command.call_args_list if c.args[0][:2] == ['systemctl', 'stop']]
        self.assertEqual(len(stopped), 1)
        self.assertNotIn('-deadline', ' '.join(stopped[0]))

    @patch('remote.registration_lock', return_value=nullcontext())
    @patch('remote.cleanup', return_value={'absent': True, 'removed_rc': 0})
    @patch('remote.command')
    def test_finalizer_proves_cgroup_absence_before_disarming(self, command, cleanup, lock):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / NAME; root.mkdir(); group = root / 'candidate-cgroup'; group.mkdir()
            (root / 'registration.json').write_text(json.dumps({'container_id': 'abc'}))
            def machine(args, **kwargs):
                if args[:2] == ['systemctl', 'stop'] and '-deadline' in args[2]:
                    proof = json.loads((root / 'cleanup-confirmed.json').read_text())
                    self.assertEqual(proof['ordering'], ['supervisor_stopped', 'container_absent', 'cgroup_absent'])
                    self.assertFalse(group.exists())
                return subprocess.CompletedProcess(args, 0, b'', b'')
            command.side_effect = machine
            with patch('remote.cgroup_path', return_value=str(group)):
                with self.assertRaisesRegex(RuntimeError, 'reaper remains armed'): finalize(root)
                self.assertFalse((root / 'cleanup-confirmed.json').exists())
                group.rmdir()
                result = finalize(root)
            self.assertEqual(result['ordering'], ['supervisor_stopped', 'container_absent', 'cgroup_absent', 'deadline_units_stopped', 'units_absent'])

    def test_start_claim_is_one_shot_even_when_dispatch_reply_is_lost(self):
        with tempfile.TemporaryDirectory() as root:
            run = Run('echo ok', [check()], Path(root) / 'run')
            with patch.object(run, '_start', side_effect=RuntimeError('lost reply')):
                with self.assertRaisesRegex(RuntimeError, 'lost reply'): run.start()
                with self.assertRaisesRegex(RuntimeError, 'one-shot'): run.start()

    def test_collect_and_dispose_serialize_with_start_and_close_future_start(self):
        with tempfile.TemporaryDirectory() as root:
            run = Run('echo ok', [check()], Path(root) / 'run')
            entered, release, collected = threading.Event(), threading.Event(), threading.Event()
            def starting():
                entered.set()
                self.assertTrue(release.wait(2))
            with patch.object(run, '_start', side_effect=starting), patch.object(run, '_collect', side_effect=collected.set):
                starter = threading.Thread(target=run.start); starter.start()
                self.assertTrue(entered.wait(1))
                collector = threading.Thread(target=run.collect); collector.start()
                self.assertFalse(collected.wait(.1))
                release.set(); starter.join(2); collector.join(2)
                self.assertFalse(starter.is_alive() or collector.is_alive())
                self.assertTrue(collected.is_set())
                with self.assertRaisesRegex(RuntimeError, 'one-shot'): run.start()
            other = Run('echo ok', [check()], Path(root) / 'other')
            with patch('adapter.py', side_effect=RuntimeError('active reaper')):
                with self.assertRaisesRegex(RuntimeError, 'active reaper'): other.dispose()
            with self.assertRaisesRegex(RuntimeError, 'one-shot'): other.start()
            unopened = Run('echo ok', [check()], Path(root) / 'unopened')
            with patch.object(unopened, '_collect', return_value={}): unopened.collect()
            with self.assertRaisesRegex(RuntimeError, 'one-shot'): unopened.start()

    def test_collect_after_confirmed_disposal_rejects_locally_without_machine_shutdown(self):
        with tempfile.TemporaryDirectory() as root:
            run = Run('echo ok', [check()], Path(root) / 'run')
            with patch('adapter.py', return_value=b'') as machine:
                run.dispose()
                run.dispose()
                self.assertEqual(machine.call_count, 1)
                with self.assertRaisesRegex(RuntimeError, 'already disposed'): run.collect()
                self.assertEqual(machine.call_count, 1)


if __name__ == '__main__': unittest.main(verbosity=2)
