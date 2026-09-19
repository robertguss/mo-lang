"""Actual controller validation using numeric server-local deadlines; no candidate."""
import hashlib
import json
from pathlib import Path
import uuid
from adapter import py
from .owner import private_write


def check(output):
    root = Path(__file__).resolve().parents[1]
    sources = {name: (root / (name + '.py')).read_text()
               for name in ('remote', 'workspace_files', 'workspace_controller')}
    payload = {'sources': sources, 'run_id': uuid.uuid4().hex, 'workspace_id': uuid.uuid4().hex}
    script = '''import json,sys,time,types,pathlib
p=json.load(sys.stdin)
for name,source in p['sources'].items():
 m=types.ModuleType(name);sys.modules[name]=m;exec(compile(source,name+'.py','exec'),m.__dict__)
controller=sys.modules['workspace_controller'];rows=[]
root=controller.root_for(p['workspace_id'])
assert not root.exists()
for offset in (60.05,55.0):
 now=time.time();deadline=now+offset
 request={'run_id':p['run_id'],'workspace_id':p['workspace_id'],'call_id':('1' if offset>60 else '2')*32,
          'operation':'list_files','args':{},'deadline':deadline}
 row={'request':request,'server_now_before':now,'deadline_minus_now':deadline-now}
 try:row['response']=controller.handle(request)
 except Exception as exc:row['raised']={'type':type(exc).__name__,'message':str(exc)}
 row['server_now_after']=time.time();row['root_absent']=not root.exists();rows.append(row)
print(json.dumps(rows))
'''
    raw = py(script, data=json.dumps(payload).encode())
    (output / 'controller-deadline.raw.json').write_bytes(raw)
    private_write(output / 'controller-deadline-source.json', {
        'sources': {name: hashlib.sha256(source.encode()).hexdigest() for name, source in sources.items()},
        'script': script, 'payload_sha256': hashlib.sha256(json.dumps(payload).encode()).hexdigest()})
    rows = json.loads(raw)
    assert rows[0]['raised'] == {'type': 'Refusal', 'message': 'deadline'}, rows
    assert rows[0]['deadline_minus_now'] > 60, rows
    # Missing workspace refuses only after deadline validation. No root is created.
    assert rows[1]['response']['error'] == 'filesystem_refusal', rows
    assert rows[1]['deadline_minus_now'] == 55, rows
    assert all(row['root_absent'] for row in rows), rows
