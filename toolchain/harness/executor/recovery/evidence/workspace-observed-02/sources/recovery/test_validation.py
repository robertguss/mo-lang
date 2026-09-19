"""Malformed trusted-record/transport controls from independent identity review."""
import json
from pathlib import Path
import sys
from types import SimpleNamespace
from unittest.mock import patch
import uuid
sys.path.insert(0,str(Path(__file__).resolve().parent))
from test_recovery import Machine, Validation


class Proofs(Machine):
    def test_incomplete_nonboolean_proofs_never_confirm(self):
        eid,call=uuid.uuid4().hex,uuid.uuid4().hex
        self.receipt['executions'].append({'execution_id':eid,'call_id':call,'directory':'execution-'+eid,
                                           'readonly':False,'dispatch_requested':True})
        root=self.c.root_for(self.ws.workspace_id)
        root.mkdir()
        good={'host_confirmed':True,'host_cgroup_absent':True,'services_absent':True,'host_cgroup':None}
        for source in ('terminal','completed'):
            for key in ('host_confirmed','host_cgroup_absent','services_absent'):
                for value in ('missing',False,1,'true',None):
                    with self.subTest(source=source,key=key,value=value):
                        bad=dict(good)
                        if value=='missing':bad.pop(key)
                        else:bad[key]=value
                        state={'run_id':self.ws.run_id,'workspace_id':self.ws.workspace_id,'phase':'ready','active':None}
                        terminal=self.c.terminal_path(self.ws.workspace_id)
                        if terminal.exists():terminal.unlink()
                        if source=='completed':state['completed_executions']={eid:bad}
                        else:self.m.remote.write(terminal,{'ownership':self.receipt,'phase':'cleaning','executions':{eid:bad}})
                        if not root.exists():root.mkdir()
                        self.c.state_write(root,state)
                        with patch.object(self.m.remote,'command',return_value=SimpleNamespace(stdout=b'',returncode=0)):
                            result=self.m.recover(self.receipt,2)
                        self.assertEqual(result['cleanup'],'unresolved',result)


class Responses(Validation):
    def test_matching_ids_do_not_authorize_malformed_response(self):
        self.ws.__del__()
        good={'run_id':self.ws.run_id,'workspace_id':self.ws.workspace_id,'cleanup':'confirmed','execution':'unknown',
              'completed':['terminal_barrier','workspace_deleted'],'unresolved':[]}
        for changes in ({'passed':True},{'execution':'completed'},{'cleanup':'success'},
                        {'completed':['execute']},{'unresolved':[uuid.uuid4().hex]},
                        {'error':'arbitrary secret text'},{'completed':'terminal_barrier'},
                        {'completed':[]},{'unresolved':None}):
            with self.subTest(changes=changes),patch('adapter.remote',return_value=json.dumps({**good,**changes}).encode()):
                result=self.r.recover(self.path)
            self.assertEqual(result['cleanup'],'unresolved',result)
            self.assertEqual(result['execution'],'unknown',result)
            self.assertNotIn('passed',result)
        with patch('adapter.remote',return_value=b' '*(self.r.MAX_RECORD+1)):
            self.assertEqual(self.r.recover(self.path)['cleanup'],'unresolved')

if __name__=='__main__':
    import unittest
    suite=unittest.TestSuite(cls(name) for cls in (Proofs,Responses) for name in cls.__dict__ if name.startswith('test_'))
    sys.exit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
