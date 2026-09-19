"""Read-only diagnostic after the retained regression runtime interruption."""
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from adapter import remote
output=Path(sys.argv[1]);output.mkdir(parents=True,exist_ok=False)
commands={
 'first-shutdown':['journalctl','-b','6309a5fab8fe40199701eebe2b486fb6','--since','2026-09-19 07:35:30 UTC','-n','400','--no-pager'],
 'boots':['journalctl','--list-boots','--no-pager'],
 'recent':['journalctl','--since','2026-09-19 07:30:00 UTC','-n','600','--no-pager'],
 'kernel':['journalctl','-k','--since','2026-09-19 07:30:00 UTC','-n','200','--no-pager'],
 'inventory':['python3','-c',"import json,pathlib,subprocess; print(json.dumps({'boot':pathlib.Path('/proc/sys/kernel/random/boot_id').read_text(),'units':subprocess.run(['systemctl','list-units','--all','--no-legend','mo-executor-*'],capture_output=True,text=True).stdout,'containers':subprocess.run(['docker','ps','-a','--no-trunc'],capture_output=True,text=True).stdout,'mountinfo':pathlib.Path('/proc/self/mountinfo').read_text()}))"]}
for name,args in commands.items():
 try:
  raw=remote(args,timeout=20)
  (output/(name+'.txt')).write_bytes(raw)
  print(name,len(raw),flush=True)
 except Exception as exc:
  (output/(name+'.error')).write_text(repr(exc))
  print(name,'failed',flush=True)
