"""Independent bridge acceptance in exact copied source; preserves main evidence."""
from pathlib import Path
from datetime import datetime
import hashlib, json, os, shutil, signal, subprocess, sys, tempfile, time
ROOT=Path(__file__).resolve().parents[4]
HERE=Path(__file__).resolve().parent
OUT=HERE/sys.argv[1];OUT.mkdir()
WORKER='9e2feb8e67d51bae8db3037bd4344b4d336b95d4'
BASE='5494e8fe5bf9c646f50d3a45fa6f485f2333a597'
GUARD=ROOT/'toolchain/bench/step36/guard.py'
paths=subprocess.check_output(['git','diff','--name-only',BASE,WORKER],cwd=ROOT,text=True).splitlines()
assert paths and all(x.startswith('toolchain/harness/provider/bridge/') for x in paths)
for f in paths:assert (ROOT/f).read_bytes()==subprocess.check_output(['git','show',WORKER+':'+f],cwd=ROOT),f
tracked=subprocess.check_output(['git','ls-files','toolchain/harness/provider'],cwd=ROOT,text=True).splitlines()
before={f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in tracked}
copy=Path(tempfile.mkdtemp(prefix='lead-bridge-',dir=ROOT/'toolchain/harness/provider/.cache'))
for f in tracked:
 target=copy/f;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/f,target)
target=copy/'toolchain/bench/step36/guard.py';target.parent.mkdir(parents=True);shutil.copy2(GUARD,target)
bridge=copy/'toolchain/harness/provider/bridge'
(OUT/'source-identity.json').write_text(json.dumps({'integrated':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'worker':WORKER,'exact_changed_files':len(paths),'tracked_files':len(tracked),'copy':str(copy)},indent=2)+'\n')
records=[]
def run(name,seconds,args,expected=0):
 command=['python3',str(GUARD),str(seconds),'--',*map(str,args)]
 started=datetime.now().astimezone().isoformat()
 with (OUT/(name+'.stdout.txt')).open('w') as out,(OUT/(name+'.stderr.txt')).open('w') as err:
  p=subprocess.Popen(command,cwd=ROOT,stdout=out,stderr=err,start_new_session=True)
  try:rc=p.wait(timeout=seconds+5)
  except subprocess.TimeoutExpired:rc=124
  finally:
   try:os.killpg(p.pid,signal.SIGKILL)
   except ProcessLookupError:pass
   p.wait(timeout=5);time.sleep(.1)
 try:os.killpg(p.pid,0);left=True
 except ProcessLookupError:left=False
 record={'command':command,'exit':rc,'expected':expected,'started':started,'finished':datetime.now().astimezone().isoformat(),'remaining_group':left}
 records.append(record);(OUT/(name+'.status.json')).write_text(json.dumps(record,indent=2)+'\n')
 print(json.dumps({'step':name,'exit':rc,'expected':expected,'group_remaining':left}),flush=True)
 assert rc==expected and not left,name
try:
 for name,selected in [('independent','independent'),('mixed-mo','final,mo'),('foundation','foundation')]:
  run(name,600,['python3',bridge/'run.py','lead-'+name,selected])
  receipt=json.loads((bridge/'evidence'/('lead-'+name)/'receipt.json').read_text());assert receipt['exit']==0 and not receipt['outer_group_remaining']
 for name,selected in [('unknown','unknown'),('empty',''),('duplicate','final,final')]:
  run(name,60,['python3',bridge/'run.py','lead-'+name,selected],2)
  receipt=json.loads((bridge/'evidence'/('lead-'+name)/'receipt.json').read_text())
  assert receipt['cases']==0 and receipt['provider_calls']==0 and not receipt['node_started'] and not receipt['dependency_copy_started']
 prepared=bridge/'.cache/lead-independent'
 run('extra',60,['python3',prepared/'run.py','50','node',HERE/'lead-controls.mjs',prepared,OUT/'extra-observations.json'])
finally:
 for name in ['independent','mixed-mo','foundation','unknown','empty','duplicate']:
  directory=bridge/'evidence'/('lead-'+name)
  if directory.exists():shutil.copytree(directory,OUT/('copy-'+name))
 changed=[f for f,digest in before.items() if hashlib.sha256((ROOT/f).read_bytes()).hexdigest()!=digest]
 copied=[f for f,digest in before.items() if hashlib.sha256((copy/f).read_bytes()).hexdigest()!=digest]
 (OUT/'source-after.json').write_text(json.dumps({'files':len(before),'original_tracked_bytes_unchanged':not changed,'changed':changed,'copied_tracked_bytes_unchanged':not copied,'copied_changed':copied},indent=2)+'\n')
 assert not changed and not copied
