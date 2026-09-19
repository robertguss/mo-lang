"""Read-only check for remaining owned run processes, excluding this check's group."""
import json, os, subprocess
from run import ROOT
rows = subprocess.check_output(['ps','-axo','pid=,ppid=,pgid=,command='],text=True).splitlines()
remaining=[]
for row in rows:
    parts=row.strip().split(None,3)
    if len(parts)!=4 or int(parts[2])==os.getpgrp(): continue
    command=parts[3]
    if str(ROOT) not in command: continue
    executable=command.split()[0]
    if executable.endswith(('/mo','/Python','/python3','/zig')) or '/zig-out/mo-build/' in executable:
        remaining.append(dict(pid=int(parts[0]),ppid=int(parts[1]),pgid=int(parts[2]),command=command))
print(json.dumps(dict(remaining_owned_run_processes=remaining,passed=not remaining),indent=2))
raise SystemExit(int(bool(remaining)))
