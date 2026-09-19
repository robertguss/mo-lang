"""Local application policy controls; never contacts a machine."""
import copy
import json
from pathlib import Path
import sys
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import remote
import workspace
import workspace_controller as controller
from test_workspace import Controller

APP = 'application-build-v1'
IMAGE = 'sha256:' + 'a' * 64
TOOLCHAIN = 'b' * 64
SELECTION = {'policy': APP, 'image': IMAGE, 'toolchain': TOOLCHAIN}


class Policy(unittest.TestCase):
    def test_default_stays_busybox_and_requires_explicit_application_identity(self):
        self.assertEqual(remote.selection(), {})
        for args in ({'policy': 'unknown'}, {'policy': APP},
                     {'policy': APP, 'image': 'latest', 'toolchain': TOOLCHAIN},
                     {'policy': APP, 'image': IMAGE, 'toolchain': ''},
                     {'image': IMAGE}):
            with self.subTest(args=args), self.assertRaises(ValueError):
                remote.selection(**args)
        self.assertEqual(remote.selection(**SELECTION), SELECTION)

    def test_application_deadline_and_fixed_identity(self):
        with tempfile.TemporaryDirectory() as root:
            binding = {'source': '/source', **SELECTION}
            run = workspace.WorkspaceRun('true', Path(root) / 'ok', 120, binding)
            for key, value in SELECTION.items():
                self.assertEqual(run.manifest[key], value)
            for seconds, selected in ((121, binding), (11, {}), (float('nan'), binding)):
                with self.assertRaises(ValueError):
                    workspace.WorkspaceRun('true', Path(root) / 'bad', seconds, selected)

    def test_build_mount_explicitly_overrides_docker_noexec_default(self):
        build_options = remote.application_tmpfs()['/build'].split(',')
        self.assertIn('exec', build_options)
        self.assertNotIn('noexec', build_options)
        self.assertIn('noexec', remote.application_tmpfs()['/tmp'].split(','))

    def test_control_selection_refuses_empty_unknown_duplicate_before_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / 'never-created'
            for names in ([], ['unknown'], ['scratch-fresh', 'scratch-fresh']):
                result = subprocess.run([sys.executable, '-B', str(Path(__file__).with_name('controls.py')),
                    str(destination), '--image', IMAGE, '--toolchain', TOOLCHAIN, '--controls', *names],
                    capture_output=True, text=True, timeout=3)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertFalse(destination.exists())

    def test_effective_policy_rejects_every_application_limit_mutation(self):
        effective = json.loads((Path(__file__).resolve().parents[1] /
            'evidence/smoke-02/positive/result.json').read_text())['observation']['effective']
        name = effective['Name'][1:]
        binding = {'source': '/source', 'readonly': False, **SELECTION}
        effective['Image'] = effective['Config']['Image'] = IMAGE
        effective['Config']['WorkingDir'] = '/workspace'
        effective['Config']['Env'] = remote.application_environment()
        effective['HostConfig'].update(Memory=1073741824, MemorySwap=1073741824,
            NanoCpus=1000000000, PidsLimit=128, CgroupParent='mo-application.slice',
            Binds=['/source:/workspace:rw'], Tmpfs=remote.application_tmpfs())
        effective['Mounts'] = [{'Type': 'bind', 'Source': '/source', 'Destination': '/workspace',
                               'Mode': 'rw', 'RW': True, 'Propagation': 'rprivate'}]
        self.assertEqual(remote.policy_errors(effective, 'echo ok', name, binding), [])
        reordered = copy.deepcopy(effective)
        reordered['Config']['Env'].reverse()
        self.assertEqual(remote.policy_errors(reordered, 'echo ok', name, binding), [])
        for values in (effective['Config']['Env'] + [effective['Config']['Env'][0]],
                       effective['Config']['Env'] + ['SECRET=extra']):
            bad = copy.deepcopy(effective)
            bad['Config']['Env'] = values
            self.assertIn('Env', remote.policy_errors(bad, 'echo ok', name, binding))
        for key, value in {'Memory': 0, 'MemorySwap': -1, 'NanoCpus': 0,
                           'PidsLimit': 0, 'CgroupParent': 'mo-executor.slice', 'Tmpfs': {}}.items():
            bad = copy.deepcopy(effective)
            bad['HostConfig'][key] = value
            self.assertIn(key, remote.policy_errors(bad, 'echo ok', name, binding))
        self.assertTrue(remote.policy_errors(effective, 'echo ok', name))


class Registration(Controller):
    # Inherit the existing registry fixture, but only run the named new controls.
    def test_application_registration_rejects_manifest_widening(self):
        state = controller.state_read(self.admin)
        state['selection'] = dict(SELECTION)
        state['active'] = {'execution_id': 'c' * 32, 'readonly': False,
                           'deadline': time.time() + 10, 'started': False}
        controller.state_write(self.admin, state)
        binding = controller.binding(self.admin, state)
        self.assertEqual({k: binding[k] for k in SELECTION}, SELECTION)
        manifest = {'workspace': binding, 'run_id': 'c' * 32, 'seconds': 120, **SELECTION}
        with patch.object(controller, 'mount_bounds', return_value={}):
            for key, value in [('image', remote.IMAGE), ('policy', remote.WORKSPACE_POLICY),
                               ('toolchain', 'd' * 64), ('seconds', 121)]:
                bad = {**manifest, key: value}
                with self.subTest(key=key), self.assertRaises(ValueError):
                    controller.authorize(bad)
            controller.authorize(manifest)
        self.assertTrue(controller.state_read(self.admin)['active']['started'])

    def test_registered_selection_cannot_be_changed_during_reservation(self):
        state = controller.state_read(self.admin)
        state['selection'] = dict(SELECTION)
        controller.state_write(self.admin, state)
        result = controller.handle(self.request('reserve', {'execution_id': 'c' * 32,
                                                           'readonly': False, 'selection': {}}))
        self.assertEqual(result['error'], 'policy_mismatch')
        self.assertIsNone(controller.state_read(self.admin)['active'])

    def test_empty_application_snapshot_refused(self):
        state = controller.state_read(self.admin)
        state['selection'] = dict(SELECTION)
        controller.state_write(self.admin, state)
        result = controller.handle(self.request('freeze'))
        self.assertEqual(result['error'], 'empty_snapshot')


if __name__ == '__main__':
    suite = unittest.TestSuite([unittest.defaultTestLoader.loadTestsFromTestCase(Policy),
        *(Registration(name) for name in ('test_application_registration_rejects_manifest_widening',
            'test_registered_selection_cannot_be_changed_during_reservation', 'test_empty_application_snapshot_refused'))])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    sys.exit(not result.wasSuccessful())
