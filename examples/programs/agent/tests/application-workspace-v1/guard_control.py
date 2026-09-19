"""Finding 7 control: an outer interruption keeps the child's actual return code, separate from
the wrapper's own outcome and reason. The inner guard is paused (SIGSTOP) so the outer wait
expires; the wrapper then kills the owned group and must report the observed exit (-9)."""
import json
import os
import signal
import subprocess
import threading
import time
import uuid

import common

marker = 'app-guard-control-' + uuid.uuid4().hex
result = {}
worker = threading.Thread(target=lambda: result.update(
    common.invoke(['python3', '-c', 'import time; time.sleep(60)', marker], 2)))
started = time.monotonic()
worker.start()
guard = None
while guard is None and time.monotonic() - started < 5:
    found = subprocess.run(['pgrep', '-f', 'guard[.]py 2 -- .*' + marker],
                           capture_output=True, text=True).stdout.split()
    guard = int(found[0]) if found else None
    time.sleep(.05)
if guard is not None:
    os.kill(guard, signal.SIGSTOP)
worker.join(30)
row = {k: v for k, v in result.items() if k not in ('stdout', 'stderr')}
checks = dict(guard_paused=guard is not None,
              observed_child_exit=result.get('exit_code') == -signal.SIGKILL,
              outcome_separate=result.get('outcome') == 'outer_timeout' and bool(result.get('reason')))
print(json.dumps(dict(result=row, checks=checks)))
leftover = subprocess.run(['pgrep', '-f', marker], capture_output=True, text=True).stdout.split()
print(json.dumps(dict(leftover_processes=len(leftover))))
raise SystemExit(0 if all(checks.values()) and not leftover else 1)
