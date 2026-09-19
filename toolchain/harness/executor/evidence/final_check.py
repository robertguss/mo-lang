import json
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from adapter import py
source = '''import json,pathlib,subprocess
r={}
for key,args in [('containers',['docker','ps','-a','--no-trunc','--format','{{json .}}']),('units',['systemctl','list-units','--all','--no-legend','mo-executor-*'])]:
 p=subprocess.run(args,capture_output=True,text=True,timeout=3);r[key]={'rc':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
r['temporary_run_directories']=[str(p) for p in pathlib.Path('/tmp').glob('mo-executor-*') if p.is_dir()]
print(json.dumps(r))
'''
r = json.loads(py(source))
processes = subprocess.run(['ps', '-axo', 'pid,ppid,command'], capture_output=True, text=True, check=True).stdout
r['host_task_processes'] = [line for line in processes.splitlines() if any('executor/' + name in line for name in ('selftest.py','smoke.py','test_executor.py'))]
print(json.dumps(r, indent=2))
assert all(r[k]['rc']==0 and not r[k]['stdout'].strip() for k in ('containers','units'))
assert not r['temporary_run_directories'] and not r['host_task_processes']
