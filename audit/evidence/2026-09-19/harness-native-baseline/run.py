from pathlib import Path
import subprocess, json, os, signal
from datetime import datetime
from zoneinfo import ZoneInfo
root=Path(__file__).resolve().parents[4]
out=Path(__file__).resolve().parent
commands=[("build",["zig","build","-j2"]),("test",["zig","build","test","-j2","--summary","all"])]
for name,command in commands:
 args=["python3","bench/step36/guard.py","300","--",*command]
 started=datetime.now(ZoneInfo("America/New_York")).isoformat()
 with (out/(name+".stdout.txt")).open("w") as stdout, (out/(name+".stderr.txt")).open("w") as stderr:
  process=subprocess.Popen(args,cwd=root/"toolchain",stdout=stdout,stderr=stderr,start_new_session=True)
  try: code=process.wait(timeout=315)
  except subprocess.TimeoutExpired:
   os.killpg(process.pid,signal.SIGKILL);process.wait();code=124
 result={"argv":args,"cwd":str(root/"toolchain"),"started_et":started,"finished_et":datetime.now(ZoneInfo("America/New_York")).isoformat(),"exit_code":code}
 (out/(name+".status.json")).write_text(json.dumps(result,indent=2)+"\n")
 print(name+": exit "+str(code),flush=True)
 if code: raise SystemExit(code)
