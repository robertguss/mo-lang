#!/usr/bin/env python3
"""guard.py SECONDS -- cmd...: runs cmd, kills it past SECONDS or 4 GB resident; forwards TERM/INT; exits as it did."""
import os, signal, subprocess, sys, threading, time
limit = float(sys.argv[1]); cmd = sys.argv[sys.argv.index("--") + 1:]
p = subprocess.Popen(cmd)
def fwd(sig, _): 
    try: p.send_signal(sig)
    except Exception: pass
for s in (signal.SIGTERM, signal.SIGINT): signal.signal(s, fwd)
def watch():
    t0 = time.time()
    while p.poll() is None:
        out = subprocess.run(["ps", "-o", "rss=", "-p", str(p.pid)], capture_output=True, text=True).stdout.strip()
        rss = int(out) * 1024 if out else 0
        if rss > 4 << 30 or time.time() - t0 > limit:
            sys.stderr.write(f"guard: killed {p.pid} (rss {rss >> 20} MB, {time.time()-t0:.0f} s)\n"); p.kill(); return
        time.sleep(0.5)
threading.Thread(target=watch, daemon=True).start()
while True:
    try: rc = p.wait(); break
    except InterruptedError: pass
if rc < 0:
    sys.exit(128 - rc)
sys.exit(rc)
