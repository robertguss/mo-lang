from pathlib import Path
import subprocess,json,os,signal,time
from datetime import datetime
from zoneinfo import ZoneInfo
root=Path(__file__).resolve().parents[4];out=Path(__file__).resolve().parent
now=lambda:datetime.now(ZoneInfo("America/New_York")).isoformat()
args=["python3","bench/step36/guard.py","1200","--","zig","build","test","-j2","--summary","all"]
started=now();clock_start=time.monotonic()
with (out/"test-longer.stdout.txt").open("w") as stdout,(out/"test-longer.stderr.txt").open("w") as stderr:
 process=subprocess.Popen(args,cwd=root/"toolchain",stdout=stdout,stderr=stderr,start_new_session=True)
 def members():
  rows=subprocess.run(["ps","-eo","pid,pgid,pcpu,rss,command"],capture_output=True,text=True,check=True).stdout.splitlines()[1:]
  return [r.split(None,4) for r in rows if len(r.split(None,4))==5 and r.split(None,4)[1]==str(process.pid)]
 while True:
  try:code=process.wait(timeout=15);break
  except subprocess.TimeoutExpired:
   with (out/"test-longer.progress.jsonl").open("a") as f:f.write(json.dumps({"at_et":now(),"members":members()})+"\n")
   if time.monotonic()-clock_start>1220:
    os.killpg(process.pid,signal.SIGKILL);process.wait();code=124;break
 before=members()
 if before:
  try:os.killpg(process.pid,signal.SIGTERM)
  except ProcessLookupError:pass
  time.sleep(2)
  if members():
   try:os.killpg(process.pid,signal.SIGKILL)
   except ProcessLookupError:pass
  time.sleep(.2)
 result={"argv":args,"cwd":str(root/"toolchain"),"started_et":started,"finished_et":now(),"exit_code":code,"pgid":process.pid,"cleanup_before":before,"cleanup_after":members()}
 (out/"test-longer.status.json").write_text(json.dumps(result,indent=2)+"\n")
 print("test-longer: exit "+str(code),flush=True)
 raise SystemExit(code)
