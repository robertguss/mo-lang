"""Local workspace controls; no machine access."""
import os
import base64
import copy
import json
import time
import uuid
from unittest.mock import patch
from pathlib import Path
import tempfile
import unittest

import workspace_files as files


class Files(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.fd = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY)

    def tearDown(self):
        os.close(self.fd)
        self.temp.cleanup()

    def test_repair_and_inventory(self):
        files.replace_file(self.fd, 'src/a', b'wrong\n', create=True)
        files.exact_edit(self.fd, 'src/a', 'wrong', 'right')
        self.assertEqual(files.read_file(self.fd, 'src/a'), 'right\n')
        self.assertEqual(files.search(self.fd, 'right')['items'], [{'path': 'src/a', 'offset': 0}])
        self.assertEqual(files.inventory(self.fd)[0]['length'], 6)

    def test_paths(self):
        for path in ('', '/', '/a', '../a', 'a/../b', 'a//b', './a', 'a/', 'a\0b', 'a' * 256, '.'):
            with self.subTest(path=path), self.assertRaises(files.Refusal):
                files.path_parts(path)
        self.assertEqual(files.path_parts('.', root=True), [])

    def test_hostile_entries(self):
        (self.root / 'a').write_text('safe')
        os.symlink('a', self.root / 'link')
        os.symlink('.', self.root / 'dirlink')
        os.link(self.root / 'a', self.root / 'hard')
        os.mkfifo(self.root / 'fifo')
        for path in ('link', 'dirlink/a', 'hard', 'fifo'):
            with self.subTest(path=path), self.assertRaises((OSError, files.Refusal)):
                files.read_file(self.fd, path)
        with self.assertRaises((OSError, files.Refusal)):
            files.inventory(self.fd)

    def test_edit_refusals_preserve_bytes(self):
        files.replace_file(self.fd, 'a', b'aaa')
        for old, new in (('aa', 'b'), ('', 'b'), ('missing', 'b'), ('aaa', 'x' * 65537)):
            with self.subTest(old=old), self.assertRaises(files.Refusal):
                files.exact_edit(self.fd, 'a', old, new)
            self.assertEqual((self.root / 'a').read_bytes(), b'aaa')
        self.assertEqual(sorted(os.listdir(self.root)), ['a'])

    def test_utf8_and_modes(self):
        files.replace_file(self.fd, 'a', b'\xff')
        with self.assertRaises(files.Refusal):
            files.read_file(self.fd, 'a')
        with self.assertRaises(files.Refusal):
            files.write_file(self.fd, 'a', '\ud800')
        os.chmod(self.root / 'a', 0o4755)
        with self.assertRaises(files.Refusal):
            files.inventory(self.fd)

    def test_import_and_result_bounds(self):
        for entries in ([('a', b'a'), ('a', b'b')], [('a', b'a'), ('a/b', b'b')], [('a', b'x' * 65537)]):
            with self.assertRaises(files.Refusal):
                files.validate_import(entries)
        files.replace_file(self.fd, 'a', b'x' * 1000)
        result = files.search(self.fd, 'x')
        self.assertEqual(len(result['items']), 200)
        self.assertTrue(result['truncated'])


class Controller(unittest.TestCase):
    def setUp(self):
        import workspace_controller as controller
        self.c = controller
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.base_patch = patch.object(controller, 'BASE', self.root)
        self.base_patch.start()
        self.workspace_id = uuid.uuid4().hex
        self.run_id = uuid.uuid4().hex
        self.admin = controller.root_for(self.workspace_id)
        self.admin.mkdir()
        (self.admin / 'storage/data').mkdir(parents=True)
        controller.state_write(self.admin, {'run_id': self.run_id, 'workspace_id': self.workspace_id,
                                           'phase': 'ready', 'active': None})

    def tearDown(self):
        self.base_patch.stop()
        self.temp.cleanup()

    def request(self, operation, args=None, **changes):
        request = {'run_id': self.run_id, 'workspace_id': self.workspace_id,
                   'call_id': uuid.uuid4().hex, 'deadline': time.time() + 10,
                   'operation': operation, 'args': args or {}}
        request.update(changes)
        return request

    def test_claim_foreign_and_active_exclusion(self):
        request = self.request('list_files')
        self.assertEqual(self.c.handle(request)['state'], 'success')
        first = (self.admin / 'calls' / (request['call_id'] + '.result')).read_bytes()
        self.assertEqual(self.c.handle(request)['error'], 'duplicate_call')
        self.assertEqual((self.admin / 'calls' / (request['call_id'] + '.result')).read_bytes(), first)
        foreign = self.request('list_files', run_id=uuid.uuid4().hex)
        self.assertEqual(self.c.handle(foreign)['error'], 'foreign_run')
        reserve = self.c.handle(self.request('reserve', {'execution_id': uuid.uuid4().hex, 'readonly': False}))
        self.assertEqual(reserve['state'], 'success')
        self.assertEqual(self.c.handle(self.request('list_files'))['error'], 'cleanup_required')
        self.assertEqual(self.c.handle(self.request('freeze'))['error'], 'cleanup_required')
        self.assertEqual(self.c.handle(self.request('delete'))['error'], 'cleanup_required')

    def test_snapshot_copies_modes_and_closes_dispatch(self):
        (self.admin / 'storage/data/a').write_bytes(b'right')
        os.chmod(self.admin / 'storage/data/a', 0o711)
        def fake_mount(path):
            path.mkdir()
            return {'local_test_only': True}
        with patch.object(self.c, 'mount', side_effect=fake_mount):
            result = self.c.handle(self.request('freeze'))
        self.assertEqual(result['state'], 'success', result)
        target = self.admin / 'snapshot/data/a'
        self.assertEqual(target.read_bytes(), b'right')
        self.assertEqual(target.stat().st_mode & 0o777, 0o755)
        self.assertNotEqual(target.stat().st_ino, (self.admin / 'storage/data/a').stat().st_ino)
        self.assertEqual(self.c.handle(self.request('write_file', {'path': 'a', 'text': 'wrong'}))['error'], 'closed')
        execution = uuid.uuid4().hex
        reserve = self.c.handle(self.request('reserve', {'execution_id': execution, 'readonly': True}))
        target.write_bytes(b'mutated')
        from remote import IMAGE, WORKSPACE_POLICY
        manifest = {'run_id': execution, 'workspace': reserve['result']['workspace'],
                    'image': IMAGE, 'policy': WORKSPACE_POLICY, 'seconds': 10}
        with patch.object(self.c, 'mount_bounds', return_value={}):
            with self.assertRaisesRegex(files.Refusal, 'stale_snapshot'):
                self.c.authorize(manifest)
            target.write_bytes(b'right')
            os.chmod(target, 0o700)
            with self.assertRaisesRegex(files.Refusal, 'snapshot_mode'):
                self.c.authorize(manifest)

    def test_json_result_limit_and_timeout_quarantine(self):
        (self.admin / 'storage/data/a').write_bytes(b'\x01' * 20000)
        result = self.c.handle(self.request('read_file', {'path': 'a'}))
        self.assertEqual(result['error'], 'result_too_large')
        self.assertTrue(result['truncated'])
        self.assertLess(len(json.dumps(result).encode()), files.CAP)
        with patch.object(self.c, 'dispatch', side_effect=TimeoutError):
            result = self.c.handle(self.request('list_files'))
        self.assertEqual(result['execution'], 'unknown')
        self.assertEqual(self.c.state_read(self.admin)['phase'], 'quarantined')


class Feedback(unittest.TestCase):
    def test_feedback_has_no_fake_checks_and_run_stays_strict(self):
        from workspace import WorkspaceRun, execution_result
        from adapter import Run
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                Run('true', [], Path(directory) / 'invalid')
            run = WorkspaceRun('true', Path(directory) / 'feedback', 1, {'readonly': False})
            self.assertIsNone(run.manifest['checks'])
            result = execution_result(run.manifest, {})
            self.assertEqual(result['state'], 'failure')
            self.assertNotIn('passed', result)
            self.assertFalse(result['execution_valid'])

    def test_command_refusal_is_structured_without_dispatch(self):
        from workspace import Workspace
        with tempfile.TemporaryDirectory() as directory:
            w = Workspace(uuid.uuid4().hex, Path(directory) / 'workspace')
            result = w.command('')
            self.assertEqual(result['state'], 'refusal')
            self.assertEqual(result['execution'], 'not_started')
            self.assertEqual(result['workspace_id'], w.workspace_id)
            self.assertIsNone(result['exit_code'])
            previous = object()
            w.active = previous
            self.assertEqual(w.command('true')['state'], 'refusal')
            self.assertIs(w.active, previous)

    def test_exact_mount_policy(self):
        from remote import policy_errors
        path = Path(__file__).parent / 'evidence/smoke-02/positive/result.json'
        baseline = json.loads(path.read_text())['observation']['effective']
        w = {'source': '/var/lib/mo-harness/mo-workspace-' + 'a' * 32 + '/storage/data', 'readonly': False}
        baseline['Config']['WorkingDir'] = '/workspace'
        baseline['HostConfig']['Binds'] = [w['source'] + ':/workspace:rw']
        baseline['Mounts'] = [{'Type': 'bind', 'Source': w['source'], 'Destination': '/workspace',
                               'Mode': 'rw', 'RW': True, 'Propagation': 'rprivate'}]
        self.assertEqual(policy_errors(baseline, 'echo ok', baseline['Name'][1:], w), [])
        for key, value in (('Source', '/tmp'), ('Destination', '/'), ('RW', False), ('Propagation', 'rshared')):
            bad = copy.deepcopy(baseline)
            bad['Mounts'][0][key] = value
            self.assertIn('Mounts', policy_errors(bad, 'echo ok', baseline['Name'][1:], w))


if __name__ == '__main__':
    unittest.main(verbosity=2)
