"""Fixed local registry. Subprocess doubles prove bridge behavior, not isolation."""
import argparse
import json
import os
from pathlib import Path
import secrets
import shlex
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cases import choose
from workspace_http import Bridge, client
from workspace_http import protocol as p
from workspace_http.client import GROUPS
from remote import IMAGE, WORKSPACE_POLICY

# `--target CMD`: the command of another server of the same wire; None is the Python bridge.
TARGET = None


class Served:
    """The Bridge surface the groups use, for a server started as `CMD DIRECTORY`.

    The operator lays out DIRECTORY before start: config.json and capability.json
    (0600), and the source under workspace/data. The server writes ready.json
    (port, operator_port), its journal owner.json and delivery.json there, and
    answers one line per operator connection: `TOKEN COMMAND`, with close,
    status or freeze. Scenario names map to operator settings or to the
    server's scripted double; nothing here is patched into the server.
    """
    LEASES = {'near-lease': 300, 'lease-active': 1000}
    LATE = ('slow', 'partial-ipc', 'fragmented-valid', 'fragmented-incomplete')

    def __init__(self, run_id, directory, source, *, selection, verifier):
        self.run_id, self.workspace_id = run_id, secrets.token_hex(16)
        self.token, self.operator_token = secrets.token_hex(32), secrets.token_hex(32)
        self.directory = Path(directory).absolute()
        self.directory.mkdir(mode=0o700, parents=True)
        self.directory = self.directory.resolve()
        scenario = source.get('scenario', b'').decode()
        data = self.directory / 'workspace/data'
        data.mkdir(mode=0o700, parents=True)
        for name, value in source.items():
            (data / name).parent.mkdir(parents=True, exist_ok=True)
            (data / name).write_bytes(value)
        if scenario == 'links':
            (self.directory / 'workspace/outside').write_bytes(b'secret\n')
            os.symlink(self.directory / 'workspace/outside', data / 'link')
            os.symlink(self.directory / 'workspace', data / 'dirlink')
        config = dict(run_id=run_id, workspace_id=self.workspace_id, verifier=verifier,
                      lease_ms=self.LEASES.get(scenario, 900000),
                      journal_cap=524288 + 8192 + 300 if scenario == 'journal-full' else 4 * 1024 * 1024,
                      late_ms=2300 if scenario in self.LATE else 0)
        for name, value in (('config.json', config), ('capability.json',
                            {'token': self.token, 'operator_token': self.operator_token})):
            fd = os.open(self.directory / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, 'wb') as out:
                out.write(p.encode(value))
        self.process = None
        self.ipc, self.deadline = None, 0

    def start(self, owner_module=None):
        log = (self.directory / 'server.log').open('xb')
        self.process = subprocess.Popen(shlex.split(TARGET) + [str(self.directory)], stdout=log, stderr=log)
        log.close()
        deadline = time.monotonic() + 40
        while not (self.directory / 'ready.json').exists():
            if self.process.poll() is not None or time.monotonic() > deadline:
                raise EOFError('no readiness')
            time.sleep(.02)
        ready = json.loads((self.directory / 'ready.json').read_bytes())
        self.port, self.operator_port = ready['port'], ready['operator_port']
        return self

    def operate(self, command, timeout=5):
        with socket.create_connection(('127.0.0.1', self.operator_port), timeout=timeout) as conn:
            conn.sendall(f'{self.operator_token} {command}\n'.encode())
            raw = bytearray()
            while not raw.endswith(b'\n'):
                part = conn.recv(65536)
                if not part:
                    break
                raw.extend(part)
        return json.loads(raw)

    def status(self):
        if self.process.poll() is not None:
            return {'admission': 'closed', 'connections': 0}
        return self.operate('status')

    @property
    def closed(self):
        return self.status()['admission'] == 'closed'

    @property
    def connections(self):
        return range(self.status()['connections'])

    def freeze(self):
        return self.operate('freeze')

    def close(self, seconds=60):
        if self.process.poll() is None:
            try:
                self.operate('close', timeout=seconds)
            except (OSError, ValueError):
                pass  # An unanswered close is judged by whether the server exits.
        try:
            self.process.wait(timeout=seconds)
        except subprocess.TimeoutExpired:
            return False
        return True

    def stop_owner(self):
        # The target may be a guard that forwards TERM to the server but cannot forward KILL.
        if self.process is not None and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=2)

class Controls(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.bridges = []

    def tearDown(self):
        for bridge in self.bridges:
            if not bridge.close(seconds=3):
                bridge.stop_owner()
        self.temp.cleanup()

    def bridge(self, scenario='', files=None, **kwargs):
        bridge = (Served if TARGET else Bridge)('run-1', Path(self.temp.name) / str(len(self.bridges)), {'scenario': scenario.encode(), **(files or {})},
                        selection={'policy': WORKSPACE_POLICY, 'image': IMAGE, 'toolchain': None},
                        verifier={'script': 'protected', 'checks': [{'id':'protected','stream':'stdout','mode':'exact','expected':'ok'}], 'seconds': 1}, **kwargs)
        self.bridges.append(bridge)
        bridge.start(owner_module='workspace_http.test_owner')
        return bridge

    def req(self, bridge, operation='list_files', args=None, call_id='call'):
        return client.request(bridge, operation, args, call_id)

    def connect(self, bridge, body, **framing):
        return client.connect(bridge, body, timeout=3, **framing)

    def read(self, conn):
        return client.response(conn, 4)

    def read_keep_open(self, conn):
        return client.first_response(conn)

    def call(self, bridge, **kwargs):
        return self.read(self.connect(bridge, self.req(bridge, **kwargs)))

    def journal(self, bridge):
        return json.loads((bridge.directory / 'owner.json').read_bytes())

    def wait_event(self, bridge, event):
        path = bridge.directory / 'workspace/events'
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if path.exists() and event in path.read_text().splitlines():
                return
            time.sleep(.01)
        self.fail('missing event ' + event)

    def test_six_tools(self):
        b = self.bridge(files={'a': 'héllo'.encode()})
        results = {}
        for op, args in [('list_files', {}), ('read_file', {'path':'a'}), ('search', {'query':'é'}),
                         ('write_file', {'path':'a','text':'b'}), ('exact_edit', {'path':'a','old_text':'b','new_text':'c'}),
                         ('command', {'command':'echo','timeout_ms':120000})]:
            status, response = self.call(b, operation=op, args=args, call_id=op)
            self.assertEqual((status, response['state'], response['execution']), (200, 'success', 'completed'))
            self.assertNotIn('manifest', json.dumps(response))
            results[op] = response['result']
        self.assertEqual([row['path'] for row in results['list_files']['items']], ['a', 'scenario'])
        self.assertEqual(results['read_file'], {'text': 'héllo', 'truncated': False})
        self.assertEqual(results['search']['items'], [{'path': 'a', 'offset': 1}])
        self.assertEqual((results['write_file']['written'], results['exact_edit']['edited']), (True, True))
        self.assertTrue(b.close())
        self.assertEqual(len(self.journal(b)['calls']), 6)

    def test_output_encoding(self):
        b = self.bridge()
        for command in ('binary', 'echo', 'timeout'):
            _, r = self.call(b, operation='command', args={'command':command,'timeout_ms':500}, call_id=command)
            self.assertEqual(r['execution'], 'completed')
            self.assertEqual(r['result']['exit_code'], 7)
            self.assertEqual(r['result']['elapsed_ms'], 123)
            if command == 'binary':
                self.assertEqual(r['error'], 'output_encoding')
                self.assertIsNone(r['result']['stdout'])
            elif command == 'timeout':
                self.assertEqual(r['state'], 'timeout')
            else:
                self.assertEqual(r['result']['stdout'], 'hello 🌊')
        req = self.req(b, 'command', {'command':'x','timeout_ms':500})
        core = dict(state='success', execution='completed', encoding='base64', stdout='!!', stderr='', exit_code=None, signal=9)
        self.assertEqual(p.project(req, core)['error'], 'output_encoding')

    def test_schema(self):
        b = self.bridge()
        for body in (b'{"x":1,"x":2}', b'{"x":NaN}', b'{"x":"\\ud800"}', b'\xff', b'[]'):
            self.assertEqual(self.read(self.connect(b, body))[0], 400)
        req = self.req(b, 'command', {'command':'x', 'timeout_ms':True})
        self.assertEqual(self.read(self.connect(b, req))[0], 400)
        req = self.req(b); req['extra'] = 1
        self.assertEqual(self.read(self.connect(b, req))[0], 400)
        self.assertFalse(self.journal(b)['calls'])
        for args in ({'path':True},{'path':0},{'path':None},{'path':[]}, {'path':'a','extra':'x'}):
            self.assertEqual(self.read(self.connect(b,self.req(b,'read_file',args)))[0],400)

    def test_framing(self):
        b = self.bridge()
        for extra in ('Origin: null\r\n', 'Transfer-Encoding: chunked\r\n', 'Content-Length: 1\r\n', 'X-Other: x\r\n'):
            self.assertEqual(self.read(self.connect(b, self.req(b), extra=extra))[0], 400)
        for first, expected in [('GET /tool HTTP/1.1',405), ('POST /tool?x HTTP/1.1',404), ('POST /tool HTTP/1.0',400)]:
            self.assertEqual(self.read(self.connect(b,self.req(b),first=first))[0], expected)
        self.assertEqual(self.read(self.connect(b,self.req(b),length='01'))[0],400)
        # Four slow header clients consume the fixed capacity; none starts work.
        conns=[socket.create_connection(('127.0.0.1',b.port),timeout=3) for _ in range(4)]
        for conn in conns:conn.sendall(b'POST /tool HTTP/1.1\r\n')
        time.sleep(.1)
        self.assertLessEqual(len(b.connections),4)
        for conn in conns:self.assertEqual(self.read(conn)[0],400)
        self.assertFalse(self.journal(b)['calls'])

    def test_byte_bounds(self):
        b = self.bridge()
        self.assertEqual(self.read(self.connect(b,b'{}',length=p.REQUEST_CAP+1))[0],413)
        # Header cap is reached before the terminating CRLF.
        conn = socket.create_connection(('127.0.0.1', b.port),timeout=3)
        conn.sendall(b'POST /tool HTTP/1.1\r\nX: ' + b'x'*16400)
        self.assertEqual(self.read(conn)[0],413)
        req=self.req(b)
        huge=p.project(req,dict(state='success',execution='completed',result={'items':['x'*p.RESPONSE_CAP]}))
        self.assertEqual(huge['error'],'response_too_large')
        valid=p.encode(self.req(b))
        self.assertEqual(p.request(valid+b' '*(p.REQUEST_CAP-len(valid)),b.run_id,b.workspace_id)['call_id'],'call')
        with self.assertRaises(p.Refused):p.request(valid+b' '*p.REQUEST_CAP,b.run_id,b.workspace_id)
        # Result bounds come from the real controller: a full file is refused whole,
        # and listings and searches are cut short and say so.
        many=self.bridge(files={'large':b'x'*65536,'h/hits':b'x'*1000,**{f'd/{i:03}':b'' for i in range(600)}})
        _,r=self.call(many,operation='read_file',args={'path':'large'},call_id='large')
        self.assertEqual((r['state'],r['execution'],r['error'],r['result']),('refusal','completed','result_too_large',None))
        _,r=self.call(many,operation='search',args={'query':'x','path':'h'},call_id='search')
        self.assertEqual((len(r['result']['items']),r['result']['truncated']),(200,True))
        _,r=self.call(many,call_id='list')
        self.assertTrue(r['result']['truncated'])
        self.assertLess(len(r['result']['items']),602)

    def test_identities_capability(self):
        b=self.bridge()
        self.assertEqual(self.read(self.connect(b,self.req(b),token='wrong'))[0],401)
        req=self.req(b);req['workspace_id']='0'*32
        status,r=self.read(self.connect(b,req));self.assertEqual(status,403);self.assertIsNone(r['run_id'])
        self.assertFalse(self.journal(b)['calls'])
        for path in (b.directory/'config.json',b.directory/'capability.json',b.directory/'owner.json'):
            self.assertEqual(path.stat().st_mode & 0o777,0o600)

    def test_duplicate_calls(self):
        b=self.bridge();self.call(b)
        for args in ({},{'path':'a'}):
            status,r=self.call(b,args=args)
            self.assertEqual((status,r['error']),(409,'conflict'))
        self.assertEqual(len(self.journal(b)['calls']),1)

    def test_concurrent_admission(self):
        b=self.bridge()
        conn=self.connect(b,self.req(b,'command',{'command':'slow','timeout_ms':1000}))
        self.wait_event(b,'command')
        status,r=self.call(b,call_id='second')
        self.assertEqual((status,r['error']),(409,'busy'))
        self.assertEqual(self.read(conn)[0],200)
        self.assertEqual(len(self.journal(b)['calls']),1)

    def test_file_refusals(self):
        b=self.bridge(files={'answer':b'aaa\n'})
        linked=self.bridge('links',files={'answer':b'aaa\n'})
        def refused(bridge,operation,args,error):
            status,r=self.call(bridge,operation=operation,args=args,call_id=f'c{len(self.journal(bridge)["calls"])}')
            self.assertEqual((status,r['state'],r['execution'],r['error'],r['result']),(200,'refusal','completed',error,None),args)
            self.assertNotIn('secret',json.dumps(r))
        # Containment: lexical escapes are refused by name, before any file is opened.
        for path in ('../escape','/etc/passwd','a//b','a/./b','answer/..'):
            refused(b,'read_file',{'path':path},'invalid_path')
        refused(b,'write_file',{'path':'../outside','text':'x'},'invalid_path')
        # Links out of the root, at the last and at a middle component, are never followed;
        # a tree holding a link refuses every write.
        for path in ('link','dirlink/outside'):
            refused(linked,'read_file',{'path':path},'filesystem_refusal')
        refused(linked,'write_file',{'path':'answer','text':'x'},'filesystem_refusal')
        self.assertEqual((linked.directory/'workspace/outside').read_bytes(),b'secret\n')
        # exact_edit matches exactly one occurrence of a non-empty string, or changes nothing.
        for old,error in (('zzz','missing_match'),('a','multiple_matches'),('','empty_old')):
            refused(b,'exact_edit',{'path':'answer','old_text':old,'new_text':'b'},error)
        _,r=self.call(b,operation='read_file',args={'path':'answer'},call_id='after')
        self.assertEqual(r['result']['text'],'aaa\n')

    def test_deadlines(self):
        b=self.bridge('slow')
        status,r=self.call(b)
        self.assertEqual((status,r['execution']),(504,'unknown'))
        self.assertTrue(b.close())
        self.assertEqual(self.journal(b)['calls']['call']['result']['execution'],'completed')
        self.assertEqual(self.journal(b)['cleanup']['cleanup'],'confirmed')
        near=self.bridge('near-lease')
        status,r=self.call(near,operation='command',args={'command':'echo','timeout_ms':120000})
        self.assertEqual((status,r['accepted'],r['execution']),(409,False,'not_started'))
        self.assertFalse(self.journal(near)['calls'])
        self.assertTrue(near.close())
        for scenario in ('partial-ipc','lease-active'):
            with self.subTest(scenario=scenario):
                other=self.bridge(scenario)
                operation='command' if scenario=='lease-active' else 'list_files'
                args={'command':'lease-slow','timeout_ms':2000} if operation=='command' else {}
                if scenario=='lease-active':
                    import select
                    original_select=select.select
                    def expire_before_receive(readers,*rest):
                        if other.ipc in readers and other.deadline-time.monotonic()<.08:
                            time.sleep(max(0,other.deadline-time.monotonic())+.02)
                            other._end('lease_expired')
                            return [other.ipc],[],[]
                        return original_select(readers,*rest)
                    with patch('workspace_http.bridge.select.select',side_effect=expire_before_receive):
                        status,r=self.call(other,operation=operation,args=args)
                else:
                    status,r=self.call(other,operation=operation,args=args)
                self.assertEqual((status,r['error'],r['execution']),(504,'response_timeout','unknown'))
                self.assertTrue(other.closed)
                self.assertTrue(other.close())
                self.assertEqual(len(self.journal(other)['calls']),1)

        for scenario in ('fragmented-valid','fragmented-incomplete'):
            with self.subTest(scenario=scenario):
                other=self.bridge(scenario)
                started=time.monotonic()
                status,r=self.call(other)
                elapsed=time.monotonic()-started
                self.assertEqual((status,r['error'],r['execution']),(504,'response_timeout','unknown'))
                self.assertLess(elapsed,2.3)
                self.assertTrue(other.closed)
                self.assertTrue(other.close())
                journal=self.journal(other)
                self.assertEqual(journal['calls']['call']['result']['execution'],'completed')
                self.assertEqual(journal['cleanup']['cleanup'],'confirmed')

    def test_disconnect(self):
        b=self.bridge()
        conn=self.connect(b,self.req(b,'command',{'command':'slow','timeout_ms':1000}))
        self.wait_event(b,'command');conn.close()
        self.assertTrue(b.process.wait(timeout=3)==0)
        self.assertTrue(b.closed)
        self.assertEqual(self.journal(b)['cleanup']['cleanup'],'confirmed')

    def test_frontend_death(self):
        outer=Path(self.temp.name)/'frontend'
        root=outer/'0'
        env=dict(os.environ,PYTHONPATH=str(Path(__file__).resolve().parents[1]))
        child=subprocess.Popen([sys.executable,'-B','-m','workspace_http.frontend_control',str(outer)],env=env)
        try:
            deadline=time.monotonic()+5
            while not (root/'workspace/events').exists() or 'command' not in (root/'workspace/events').read_text():
                if time.monotonic()>deadline:self.fail('frontend startup')
                time.sleep(.01)
            child.kill();self.assertLess(child.wait(timeout=2),0)
            deadline=time.monotonic()+3
            while time.monotonic()<deadline:
                journal=json.loads((root/'owner.json').read_bytes())
                if journal['cleanup']['cleanup']=='confirmed':break
                time.sleep(.02)
            self.assertEqual(journal['cleanup']['cleanup'],'confirmed')
            self.assertEqual(journal['calls']['call']['result']['execution'],'completed')
        finally:
            if child.poll() is None:child.kill();child.wait()

    def test_owner_death(self):
        b=self.bridge()
        with self.assertRaises(RuntimeError):b.recover()
        b.stop_owner()
        self.assertLess(b.process.returncode,0)
        with patch('recovery.recover', return_value={'cleanup':'confirmed','execution':'unknown'}) as recover:
            self.assertEqual(b.recover()['execution'],'unknown')
            recover.assert_called_once_with(b.directory/'workspace/ownership.json',seconds=60)
        self.assertEqual(self.journal(b)['cleanup']['cleanup'],'unresolved')

    def test_lost_response(self):
        b=self.bridge()
        conn=self.connect(b,self.req(b,'command',{'command':'slow','timeout_ms':1000}))
        self.wait_event(b,'command');conn.close();b.process.wait(timeout=3)
        j=self.journal(b)
        self.assertEqual(len(j['calls']),1)
        self.assertEqual(j['calls']['call']['result']['execution'],'completed')
        self.assertEqual(json.loads((b.directory/'delivery.json').read_bytes())['delivery'],'unknown')

    def test_owner_stall(self):
        b=self.bridge('stall')
        conn=self.connect(b,self.req(b));self.wait_event(b,'list_files')
        self.assertEqual(self.read(conn)[0],504)
        self.assertFalse(b.close(seconds=.05))
        self.assertIsNone(b.process.poll())
        b.stop_owner()
        self.assertEqual(self.journal(b)['cleanup']['cleanup'],'unresolved')

    def test_startup_failure(self):
        with self.assertRaises(EOFError):self.bridge('startup-failure')
        b=self.bridges[-1];b.process.wait(timeout=3)
        self.assertFalse((b.directory/'ready.json').exists())
        self.assertEqual(self.journal(b)['cleanup']['cleanup'],'confirmed')

    def test_shutdown(self):
        b=self.bridge();self.assertTrue(b.close());self.assertIsNotNone(b.process.poll())
        self.assertEqual(self.journal(b)['cleanup']['cleanup'],'confirmed')

        for active in (False,True):
            with self.subTest(active_at_drain_expiry=active):
                other=self.bridge()
                first=self.connect(other,self.req(other,call_id='first'))
                try:
                    self.assertEqual(self.read_keep_open(first)['state'],'success')
                    if active:
                        time.sleep(1.7)
                        status,r=self.call(other,operation='command',args={'command':'slow','timeout_ms':1000},call_id='second')
                        self.assertEqual((status,r['state']),(200,'success'))
                    else:
                        time.sleep(2.2)
                        self.assertFalse(other.closed)
                        self.assertTrue(self.call(other,call_id='second')[1]['accepted'])
                finally:
                    first.close()
        with self.subTest(cleanup_transport_reserve=True):
            budget=self.bridge('cleanup-budget')
            self.assertTrue(budget.close())
            self.assertEqual(self.journal(budget)['cleanup']['cleanup'],'confirmed')

    def test_protected_verifier(self):
        b=self.bridge();self.assertEqual(b.freeze()['snapshot'],'test-only')
        self.assertTrue(b.closed);self.assertTrue(b.verify()['passed'])
        self.assertTrue((b.directory/'verification.json').exists())

    def test_application_binding(self):
        b=self.bridge()
        req=self.req(b);req['args']={'policy':'application-build-v1'}
        self.assertEqual(self.read(self.connect(b,req))[0],400)
        self.assertEqual(json.loads((b.directory/'config.json').read_bytes())['selection']['policy'],WORKSPACE_POLICY)

    def test_cleanup_outcome(self):
        b=self.bridge();self.call(b,operation='command',args={'command':'timeout','timeout_ms':500})
        self.assertTrue(b.close());j=self.journal(b)
        self.assertEqual(j['calls']['call']['result']['state'],'timeout')
        self.assertEqual(j['cleanup']['cleanup'],'confirmed')
        self.assertEqual(j['cleanup']['execution'],'unknown')

    def test_invalid_selection(self):
        target=Path(self.temp.name)/'invalid'
        with self.assertRaises(ValueError):
            Bridge('run',target,{},selection={'policy':'wrong','image':IMAGE,'toolchain':None},
                   verifier={'script':'x','checks':[{'id':'protected','stream':'stdout','mode':'exact','expected':'ok'}],'seconds':1})
        self.assertFalse(target.exists())
        for selected in ('','six-tools,six-tools','unknown'):
            proc=subprocess.run([sys.executable,'-B',__file__,'--groups',selected],capture_output=True,timeout=3)
            self.assertEqual(proc.returncode,2)
            self.assertEqual(proc.stdout,b'')

    def test_journal_order_bound(self):
        b=self.bridge()
        for i in range(16):self.assertTrue(self.call(b,call_id=f'c{i}')[1]['accepted'])
        self.assertEqual(self.call(b,call_id='overflow')[1]['error'],'call_limit')
        j=self.journal(b)
        self.assertEqual(len({row['core_call_id'] for row in j['calls'].values()}),16)
        self.assertTrue(all(row['intent'] and len(row['payload_sha256'])==64 for row in j['calls'].values()))
        self.assertLess((b.directory/'owner.json').stat().st_size,p.JOURNAL_CAP)
        full=self.bridge('journal-full')
        status,r=self.call(full)
        self.assertEqual((status,r['error'],r['accepted']),(409,'journal_full',False))
        self.assertFalse(self.journal(full)['calls'])


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--groups',default=','.join(GROUPS))
    parser.add_argument('--target',default=None,help='command of another server of this wire; its directory is appended')
    args=parser.parse_args()
    groups=choose(parser,GROUPS,args.groups.split(','))
    global TARGET
    TARGET=args.target
    print('LOCAL SUBPROCESS DOUBLES; NOT REAL WORKSPACE ACCEPTANCE',flush=True)
    if TARGET:
        print('target='+TARGET,flush=True)
    print('groups='+','.join(groups),flush=True)
    suite=unittest.TestSuite(Controls('test_'+group.replace('-','_')) for group in groups)
    result=unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(not result.wasSuccessful())

if __name__=='__main__':main()
