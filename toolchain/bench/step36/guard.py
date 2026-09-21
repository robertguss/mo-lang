#!/usr/bin/env python3
"""guard.py SECONDS -- cmd...: runs cmd, kills its group past SECONDS or 4 GB direct-child resident; forwards TERM/INT to the group; exits as the child did."""
import os, signal, subprocess, sys, threading, time
limit = float(sys.argv[1]); cmd = sys.argv[sys.argv.index("--") + 1:]
p = None; pending = []
def group(sig):
    if p is None:
        pending.append(sig); return
    try: os.killpg(p.pid, sig)
    except Exception: pass
def fwd(sig, _): group(sig)
for s in (signal.SIGTERM, signal.SIGINT): signal.signal(s, fwd)
p = subprocess.Popen(cmd, start_new_session=True)
for sig in pending: group(sig)
def watch():
    t0 = time.time()
    while p.poll() is None:
        out = subprocess.run(["ps", "-o", "rss=", "-p", str(p.pid)], capture_output=True, text=True).stdout.strip()
        rss = int(out) * 1024 if out else 0
        if rss > 4 << 30 or time.time() - t0 > limit:
            sys.stderr.write(f"guard: killed {p.pid} (rss {rss >> 20} MB, {time.time()-t0:.0f} s)\n"); group(signal.SIGKILL); return
        time.sleep(0.5)
threading.Thread(target=watch, daemon=True).start()
while True:
    try: rc = p.wait(); break
    except InterruptedError: pass
group(signal.SIGKILL)
if rc < 0:
    sys.exit(128 - rc)
sys.exit(rc)
