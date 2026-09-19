"""Cleanup-only controls; local tests never contact a machine."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
import uuid
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from workspace import Workspace


class Ownership(unittest.TestCase):
    def test_receipt_precedes_create(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = Workspace(uuid.uuid4().hex, Path(tmp) / 'workspace')
            receipt = json.loads((ws.directory / 'ownership.json').read_text())
            self.assertEqual(receipt['workspace_id'], ws.workspace_id)
            self.assertEqual(receipt['run_id'], ws.run_id)

    def test_lost_reserve_retains_unbound_identity(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = Workspace(uuid.uuid4().hex, Path(tmp) / 'workspace')
            with patch.object(ws, 'require', side_effect=TimeoutError('lost reserve response')):
                with self.assertRaises(TimeoutError):
                    ws._prepare_command('echo never-retry')
            receipt = json.loads((ws.directory / 'ownership.json').read_text())
            self.assertEqual(len(receipt['executions']), 1)
            intent = receipt['executions'][0]
            manifest = json.loads((ws.directory / intent['directory'] / 'manifest.json').read_text())
            self.assertEqual(intent['execution_id'], manifest['run_id'])
            self.assertIsNone(ws.active)




class Validation(unittest.TestCase):
    def setUp(self):
        import recovery
        self.r = recovery
        self.temp = tempfile.TemporaryDirectory()
        self.ws = Workspace(uuid.uuid4().hex, Path(self.temp.name) / 'workspace')
        self.path = self.ws.directory / 'ownership.json'

    def tearDown(self):
        self.temp.cleanup()

    def test_invalid_receipts_before_transport(self):
        import copy
        original = json.loads(self.path.read_text())
        mutations = [dict(version='unknown'), dict(run_id='../bad'), dict(directory='/foreign'),
                     dict(selection={}), dict(executions=[{}] * 1001)]
        with patch('adapter.remote') as transport:
            for mutation in mutations:
                bad = copy.deepcopy(original)
                bad.update(mutation)
                self.path.write_text(json.dumps(bad))
                with self.assertRaises((ValueError, OSError)):
                    self.r.recover(self.path)
            transport.assert_not_called()

    def test_symlink_hardlink_and_nonprivate(self):
        import os
        original = self.path.read_bytes()
        self.path.unlink()
        target = self.path.with_name('other')
        target.write_bytes(original)
        for link in (os.symlink, os.link):
            link(target, self.path)
            with self.assertRaises((ValueError, OSError)):
                self.r.recover(self.path)
            self.path.unlink()
        self.path.write_bytes(original)
        os.chmod(self.ws.directory, 0o755)
        with self.assertRaises(ValueError):
            self.r.recover(self.path)

    def test_owner_contention_never_steals(self):
        import time
        with patch('adapter.remote') as transport:
            result = self.r.recover(self.path, seconds=.5)
            self.assertEqual(result['cleanup'], 'unresolved')
            self.assertEqual(result['error'], 'ownership_busy')
            transport.assert_not_called()
        self.assertFalse((self.ws.directory / 'recovery-requested').exists())

    def test_transport_unknown_closes_original_owner(self):
        self.ws.__del__()
        with patch('adapter.remote', side_effect=TimeoutError):
            result = self.r.recover(self.path)
        self.assertEqual(result['execution'], 'unknown')
        self.assertEqual(result['cleanup'], 'unresolved')
        with self.assertRaisesRegex(ValueError, 'recovery_closed'):
            self.ws.list_files()

    def test_selection_rejected_before_output_or_transport(self):
        import subprocess
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / 'must-not-exist'
            for args in (['--groups'], ['--groups','unknown'], ['--groups','create-before','create-before']):
                result = subprocess.run([sys.executable,'-B',str(Path(__file__).with_name('live.py')),str(output),*args],capture_output=True,timeout=5)
                self.assertEqual(result.returncode,2)
                self.assertFalse(output.exists())

    def lost_reserve(self, ws):
        with patch.object(ws, 'require', side_effect=TimeoutError):
            with self.assertRaises(TimeoutError):
                ws._prepare_command('true')
        ws.__del__()
        return ws.ownership['executions'][0]

    def test_conflicting_local_manifest_refused_before_transport(self):
        # Control: the same unmodified record reaches the machine and is confirmed.
        own = Workspace(uuid.uuid4().hex, Path(self.temp.name) / 'control')
        row = self.lost_reserve(own)
        confirmed = {'run_id': own.run_id, 'workspace_id': own.workspace_id, 'cleanup': 'confirmed',
                     'execution': 'unknown', 'completed': ['terminal_barrier', row['execution_id'], 'workspace_deleted'],
                     'unresolved': []}
        with patch('adapter.machine_call', return_value=json.dumps(confirmed).encode()) as transport:
            self.assertEqual(self.r.recover(own.directory / 'ownership.json')['cleanup'], 'confirmed')
            transport.assert_called_once()
        row = self.lost_reserve(self.ws)
        path = self.ws.directory / row['directory'] / 'manifest.json'
        manifest = json.loads(path.read_text())
        manifest['run_id'] = uuid.uuid4().hex
        path.write_text(json.dumps(manifest))
        with patch('adapter.machine_call') as transport:
            result = self.r.recover(self.path)
            self.assertEqual((result['cleanup'], result['error']), ('unresolved', 'recovery_unknown'))
            transport.assert_not_called()
        self.assertFalse((self.ws.directory / 'recovery-requested').exists())


class Machine(unittest.TestCase):
    def setUp(self):
        from recovery import machine
        import workspace_controller as controller
        self.m = machine
        self.c = controller
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.ws = Workspace(uuid.uuid4().hex, self.directory / 'host')
        self.receipt = self.ws.ownership
        self.patches = [patch.object(controller, 'BASE', self.directory / 'machine'),
                        patch.object(machine, 'EXECUTION_BASE', self.directory / 'executions'),
                        patch.object(machine, 'mounted_paths', return_value=set())]
        for p in self.patches:
            p.start()
        self.c.BASE.mkdir()
        self.m.EXECUTION_BASE.mkdir()

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self.temp.cleanup()

    def test_before_create_retired_and_late_create(self):
        result = self.m.recover(self.receipt, 2)
        self.assertEqual(result['cleanup'], 'confirmed', result)
        request = {'run_id': self.ws.run_id, 'workspace_id': self.ws.workspace_id,
                   'call_id': uuid.uuid4().hex, 'args': {'files': []}, 'deadline': __import__('time').time() + 2}
        with self.assertRaisesRegex(ValueError, 'recovery_closed'):
            self.c.create(request, self.c.root_for(self.ws.workspace_id))
        self.assertEqual(self.m.recover(self.receipt, 2)['cleanup'], 'confirmed')
        self.assertFalse(self.c.root_for(self.ws.workspace_id).exists())

    def test_late_bootstrap_barrier_before_storage(self):
        self.assertEqual(self.m.recover(self.receipt, 2)['cleanup'], 'confirmed')
        with self.assertRaisesRegex(ValueError, 'recovery_closed'):
            self.c.bootstrap_barrier({'workspace': {'workspace_id': self.ws.workspace_id}})

    def owned(self):
        """A second receipt with its own machine root, for a same-shape control."""
        return Workspace(uuid.uuid4().hex, self.directory / ('host-' + uuid.uuid4().hex)).ownership

    def ready(self, receipt, **changes):
        root = self.c.root_for(receipt['workspace_id'])
        root.mkdir()
        state = {'run_id': receipt['run_id'], 'workspace_id': receipt['workspace_id'],
                 'phase': 'ready', 'active': None, **changes}
        self.c.state_write(root, state)
        return root, state

    def execution(self, receipt, dispatched):
        eid = uuid.uuid4().hex
        receipt['executions'].append({'execution_id': eid, 'call_id': uuid.uuid4().hex,
            'directory': 'execution-' + eid, 'readonly': False, 'dispatch_requested': dispatched})
        return eid

    def absent_runtime(self):
        from types import SimpleNamespace
        return patch.object(self.m.remote, 'command', return_value=SimpleNamespace(stdout=b'', returncode=0))

    def test_foreign_state_retained(self):
        # Control: the same state, owned by the receipt, is read and cleaned.
        own = self.owned()
        root, _ = self.ready(own)
        self.assertEqual(self.m.recover(own, 2)['cleanup'], 'confirmed')
        self.assertFalse(root.exists())
        root, state = self.ready(self.receipt, run_id=uuid.uuid4().hex)
        result = self.m.recover(self.receipt, 2)
        self.assertEqual((result['cleanup'], result['completed']), ('unresolved', []))
        self.assertEqual(self.c.state_read(root), state)
        self.assertFalse(self.c.terminal_path(self.ws.workspace_id).exists())

    def test_missing_root_is_not_runtime_absence(self):
        # Control: a missing execution root plus an empty runtime query is absence.
        own = self.owned()
        eid = self.execution(own, dispatched=False)
        with self.absent_runtime():
            self.assertEqual(self.m.recover(own, 2)['completed'], ['terminal_barrier', eid, 'workspace_deleted'])
        eid = self.execution(self.receipt, dispatched=False)
        with patch.object(self.m.remote, 'command', side_effect=RuntimeError('transport')) as command:
            result = self.m.recover(self.receipt, 2)
        self.assertEqual((result['cleanup'], result['completed'], result['unresolved']),
                         ('unresolved', ['terminal_barrier'], [eid]))
        self.assertIn('name=^/mo-executor-' + eid + '$', command.call_args.args[0])

    def test_dispatched_missing_storage_requires_proof(self):
        proof = {'host_confirmed': True, 'host_cgroup_absent': True, 'services_absent': True, 'host_cgroup': None}
        # Control: the same dispatched execution with its retained cleanup proof.
        own = self.owned()
        eid = self.execution(own, dispatched=True)
        self.ready(own, completed_executions={eid: proof})
        with self.absent_runtime():
            self.assertEqual(self.m.recover(own, 2)['completed'], ['terminal_barrier', eid, 'workspace_deleted'])
        eid = self.execution(self.receipt, dispatched=True)
        root, _ = self.ready(self.receipt)
        with self.absent_runtime() as command:
            result = self.m.recover(self.receipt, 2)
        self.assertEqual((result['cleanup'], result['execution'], result['completed'], result['unresolved']),
                         ('unresolved', 'unknown', ['terminal_barrier'], [eid]))
        self.assertEqual(command.call_count, 2)  # absence was proved; only the proof is missing
        terminal = json.loads(self.c.terminal_path(self.ws.workspace_id).read_text())
        self.assertEqual((terminal['phase'], terminal['executions']), ('cleaning', {}))
        self.assertEqual(self.c.state_read(root)['phase'], 'quarantined')

    def test_interrupted_dispose_reuses_retained_proof(self):
        import remote
        from types import SimpleNamespace
        eid, call = uuid.uuid4().hex, uuid.uuid4().hex
        row = {'execution_id':eid, 'call_id':call, 'directory':'execution-'+eid,
               'readonly':False, 'dispatch_requested':True}
        self.receipt['executions'].append(row)
        root = self.c.root_for(self.ws.workspace_id)
        root.mkdir()
        state = {'workspace_id':self.ws.workspace_id, 'run_id':self.ws.run_id,
                 'phase':'ready', 'active':{'execution_id':eid,'call_id':call,'started':True,'readonly':False}}
        self.c.state_write(root,state)
        eroot = self.m.EXECUTION_BASE / ('mo-executor-'+eid)
        eroot.mkdir()
        remote.write(eroot/'manifest.json', {'run_id':eid,'name':eroot.name,
            'workspace':self.c.binding(root,state),'workspace_call_id':call,
            'image':remote.IMAGE,'policy':remote.WORKSPACE_POLICY,'seconds':1})
        proof = {'host_confirmed':True,'host_cgroup_absent':True,'services_absent':True,'host_cgroup':None}
        def interrupted(*args, **kwargs):
            (eroot/'manifest.json').unlink()
            raise TimeoutError('interrupted disposal')
        with patch.object(remote,'finalize',return_value=proof), patch.object(remote,'dispose',side_effect=interrupted):
            first = self.m.recover(self.receipt,2)
        self.assertEqual(first['cleanup'],'unresolved')
        with patch.object(remote,'command',return_value=SimpleNamespace(stdout=b'',returncode=0)):
            second = self.m.recover(self.receipt,2)
        self.assertEqual(second['cleanup'],'confirmed',second)
        self.assertFalse(eroot.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
