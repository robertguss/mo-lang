"""Positive read-only runtime identity and raw transport probes; no candidates."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from remote import IMAGE
from live import IMAGE as APP_IMAGE, TOOLCHAIN
out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=False)
prefix=['orbctl','run','-m','mo-executor-r01','-u','root']

def run(name,args,input=None):
    started=time.time()
    p=subprocess.run(args,input=input,capture_output=True,timeout=20)
    (out/(name+'.stdout')).write_bytes(p.stdout)
    (out/(name+'.stderr')).write_bytes(p.stderr)
    (out/(name+'.json')).write_text(json.dumps({'argv':args,'rc':p.returncode,'started':started,'finished':time.time()}))
    if p.returncode:raise RuntimeError((name,p.returncode))
    return p.stdout

run('orbctl-status',['orbctl','list'])
if len(sys.argv)>2:
    assert sys.argv[2:] == ['--activate-existing']
    activation = """import hashlib,json,subprocess
names=['mo-executor.slice','mo-application.slice']
def contents():
 result={}
 for name in names:
  p=subprocess.run(['systemctl','cat',name],capture_output=True,check=True,timeout=5)
  result[name]={'sha256':hashlib.sha256(p.stdout).hexdigest(),'unit':p.stdout.decode()}
 return result
before=contents()
subprocess.run(['systemctl','start',*names],check=True,timeout=15)
after=contents()
print(json.dumps({'before':before,'after':after,'unchanged':before==after}))
assert before==after
"""
    run('slice-activation', [*prefix,'python3','-c',activation])
source='''import hashlib,json,pathlib,subprocess,sys
def cmd(args):
 p=subprocess.run(args,capture_output=True,text=True,timeout=5)
 if p.returncode:raise RuntimeError((args,p.returncode,p.stderr))
 return p.stdout
parents={}
for name in ('mo-executor.slice','mo-application.slice'):
 props=dict(line.split('=',1) for line in cmd(['systemctl','show',name,'-p','ControlGroup','-p','ActiveState','-p','MemoryMax','-p','MemorySwapMax','-p','TasksMax','-p','CPUQuotaPerSecUSec']).splitlines())
 expected='/mo.slice/'+name
 if props['ControlGroup']!=expected or props['ActiveState']!='active':raise RuntimeError('parent not execution-ready')
 root=pathlib.Path('/sys/fs/cgroup'+expected)
 if not root.is_dir():raise RuntimeError('active parent missing')
 props['effective']={key:(root/key).read_text().strip() for key in ('memory.max','memory.swap.max','cpu.max','pids.max')}
 props['unit_sha256']=hashlib.sha256(cmd(['systemctl','cat',name]).encode()).hexdigest()
 props['expected_path']=str(root)
 props['path_exists']=root.exists()
 props['tasks']={str(p):p.read_text() for p in root.rglob('cgroup.procs')}
 props['children']=[str(p) for p in root.rglob('docker-*.scope')]
 parents[name]=props
manifest=pathlib.Path('/opt/mo-harness/application-build-v1/lead-package-attempt-01/package/manifest.json').read_bytes()
print(json.dumps({'parents':parents,'images':{image:json.loads(cmd(['docker','image','inspect',image]))[0]['Id'] for image in sys.argv[1:]},'package_sha256':hashlib.sha256(manifest).hexdigest(),'containers':cmd(['docker','ps','-aq']),'units':cmd(['systemctl','list-units','--all','--no-legend','mo-executor-*']),'boot':pathlib.Path('/proc/sys/kernel/random/boot_id').read_text()}))
'''
raw=run('readiness',[*prefix,'python3','-c',source,IMAGE,APP_IMAGE])
r=json.loads(raw)
assert r['images']=={IMAGE:IMAGE,APP_IMAGE:APP_IMAGE}
assert r['package_sha256']==TOOLCHAIN
assert not r['containers'].strip() and not r['units'].strip()
for name,memory,tasks in [('mo-executor.slice',536870912,128),('mo-application.slice',1610612736,192)]:
    p=r['parents'][name]
    assert int(p['MemoryMax'])==memory and int(p['MemorySwapMax'])==0 and int(p['TasksMax'])==tasks,p
    assert p['CPUQuotaPerSecUSec']=='1s',p
    effective=p['effective']
    assert effective['memory.max']==str(memory) and effective['memory.swap.max']=='0' and effective['pids.max']==str(tasks),p
    quota,period=map(int,effective['cpu.max'].split())
    assert quota==period and period>0,p
    assert not p['children'] and all(not v.strip() for v in p['tasks'].values()),p
# Same inherited snapshot function, with exact raw transport bytes retained by
# a test-only replacement of its py transport; no production method is edited.
import selftest
from types import SimpleNamespace
counter=0

def observed(source,*args,data=None):
    global counter
    raw=run('probe-'+str(counter).zfill(2),[*prefix,'python3','-c',source,*args],data)
    counter+=1
    return raw
selftest.py=observed
for _ in range(20):
    result=selftest.snapshot(SimpleNamespace(name='mo-executor-c6dac6e58cfd4a119cdcf20afb2e46c2'))
    assert result['containers']['rc']==0 and not result['containers']['stdout'].strip(),result
    assert result['units']['rc']==0 and not result['units']['stdout'].strip(),result
print(json.dumps({'probes':counter,'valid_json':counter,'identity_and_limits':True,'runtime_absent':True,'boot':r['boot']}))
