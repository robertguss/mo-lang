import base64
import copy
import tempfile
import json
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch

from adapter import Run, validate_checks, verify
from remote import CAP, IMAGE, cgroup_path, policy_errors, reap


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

    @patch('remote.cleanup', side_effect=RuntimeError('unconfirmed cleanup'))
    @patch('remote.command')
    def test_independent_reaper_requests_dedicated_machine_poweroff_if_cleanup_unknown(self, command, cleanup):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'manifest.json').write_text(json.dumps({'name': 'mo-executor-unit'}))
            reap(root)
            self.assertFalse(json.loads((root / 'reaped.json').read_text())['absent'])
            self.assertIn((['systemctl', 'poweroff'],), [c.args for c in command.call_args_list])

    @patch('adapter.py', side_effect=RuntimeError('machine unavailable'))
    @patch('adapter.subprocess.run')
    def test_host_cleanup_failure_stops_only_named_machine_and_fails_closed(self, command, remote_python):
        command.return_value = subprocess.CompletedProcess([], 0, b'', b'')
        with tempfile.TemporaryDirectory() as root:
            run = Run('echo ok', [check()], Path(root) / 'run')
            result = run.collect()
            self.assertFalse(result['passed'])
            self.assertEqual(result['observation']['status'], 'infrastructure_failure')
            self.assertEqual(command.call_args.args[0], ['orbctl', 'stop', 'mo-executor-r01'])

    def test_caller_check_mutation_does_not_change_registered_inventory(self):
        with tempfile.TemporaryDirectory() as root:
            checks = [check()]
            run = Run('echo ok', checks, Path(root) / 'run')
            checks[0]['expected'] = 'forged'
            self.assertEqual(run.manifest['checks'][0]['expected'], 'ok\n')


if __name__ == '__main__': unittest.main(verbosity=2)
