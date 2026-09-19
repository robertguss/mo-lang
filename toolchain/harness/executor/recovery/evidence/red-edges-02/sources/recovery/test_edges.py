"""Additional interruptions within the same fixed recovery groups."""
import json
from pathlib import Path
import sys
from types import SimpleNamespace
import uuid
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parent))
from test_recovery import Machine


class Edges(Machine):
    def test_reserved_partial_bootstrap_without_manifest(self):
        eid, call = uuid.uuid4().hex, uuid.uuid4().hex
        self.receipt['executions'].append({'execution_id':eid,'call_id':call,'directory':'execution-'+eid,
                                           'readonly':False,'dispatch_requested':True})
        root=self.c.root_for(self.ws.workspace_id)
        root.mkdir()
        self.c.state_write(root,{'run_id':self.ws.run_id,'workspace_id':self.ws.workspace_id,'phase':'ready',
                                'active':{'execution_id':eid,'call_id':call,'readonly':False,'started':False}})
        eroot=self.m.EXECUTION_BASE / ('mo-executor-'+eid)
        eroot.mkdir()
        (eroot/'remote.py').write_text('not executed')
        with patch.object(self.m.remote,'command',return_value=SimpleNamespace(stdout=b'',returncode=0)):
            result=self.m.recover(self.receipt,2)
        self.assertEqual(result['cleanup'],'confirmed',result)
        self.assertFalse(eroot.exists())

    def test_create_partial_root_uses_precreated_ownership(self):
        root=self.c.root_for(self.ws.workspace_id)
        root.mkdir()
        record={'run_id':self.ws.run_id,'workspace_id':self.ws.workspace_id,'selection':{}}
        (self.c.BASE / ('.owner-'+self.ws.workspace_id)).write_text(json.dumps(record))
        result=self.m.recover(self.receipt,2)
        self.assertEqual(result['cleanup'],'confirmed',result)
        self.assertFalse(root.exists())

    def test_omitted_completed_execution_is_conflict(self):
        root=self.c.root_for(self.ws.workspace_id)
        root.mkdir()
        self.c.state_write(root,{'run_id':self.ws.run_id,'workspace_id':self.ws.workspace_id,'phase':'ready',
                                'active':None,'completed_executions':{uuid.uuid4().hex:{}}})
        result=self.m.recover(self.receipt,2)
        self.assertEqual(result['cleanup'],'unresolved',result)
        self.assertTrue(root.exists())

    def test_healthy_delete_retains_completed_proof(self):
        import time
        eid, call = uuid.uuid4().hex, uuid.uuid4().hex
        self.receipt['executions'].append({'execution_id':eid,'call_id':call,'directory':'execution-'+eid,
                                           'readonly':False,'dispatch_requested':True})
        root=self.c.root_for(self.ws.workspace_id)
        root.mkdir()
        proof={'host_confirmed':True,'host_cgroup_absent':True,'services_absent':True,'host_cgroup':None}
        self.c.state_write(root,{'run_id':self.ws.run_id,'workspace_id':self.ws.workspace_id,'phase':'ready',
                                'active':None,'completed_executions':{eid:proof}})
        deleted=self.c.handle({'run_id':self.ws.run_id,'workspace_id':self.ws.workspace_id,'call_id':uuid.uuid4().hex,
                              'operation':'delete','args':{},'deadline':time.time()+2})
        self.assertEqual(deleted['state'],'success',deleted)
        with patch.object(self.m.remote,'command',return_value=SimpleNamespace(stdout=b'',returncode=0)):
            result=self.m.recover(self.receipt,2)
        self.assertEqual(result['cleanup'],'confirmed',result)

    def test_dispatched_before_bootstrap_has_reserved_authority(self):
        eid, call = uuid.uuid4().hex, uuid.uuid4().hex
        self.receipt['executions'].append({'execution_id':eid,'call_id':call,'directory':'execution-'+eid,
                                           'readonly':False,'dispatch_requested':True})
        root=self.c.root_for(self.ws.workspace_id)
        root.mkdir()
        self.c.state_write(root,{'run_id':self.ws.run_id,'workspace_id':self.ws.workspace_id,'phase':'ready',
                                'active':{'execution_id':eid,'call_id':call,'readonly':False,'started':False}})
        with patch.object(self.m.remote,'command',return_value=SimpleNamespace(stdout=b'',returncode=0)):
            result=self.m.recover(self.receipt,2)
        self.assertEqual(result['cleanup'],'confirmed',result)

if __name__ == '__main__':
    import unittest
    suite=unittest.TestSuite(Edges(name) for name in Edges.__dict__ if name.startswith('test_'))
    sys.exit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
