#!/usr/bin/env python3
"""The evidence folder's replay.py, parameterized and kept in scratch: 200 accounts with a large
overdraft, N transfers from 32 clients with a fresh idempotency key each, the rate and resident memory
after; then, with --replays K, K restarts on the log timed to /health with their peak.
usage: ledger_load.py BIN DATA_DIR N PORT [--cores C] [--replays K] [--keep]"""
import subprocess, time, sys, os, json, http.client, threading, signal, shutil

BIN, D, N, PORT = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
CORES = sys.argv[sys.argv.index("--cores") + 1] if "--cores" in sys.argv else None
REPLAYS = int(sys.argv[sys.argv.index("--replays") + 1]) if "--replays" in sys.argv else 0
assert "scratch" in D or "step30" in D, "data only in a scratch folder"
env = dict(os.environ)
if CORES: env["MO_CORES"] = CORES

def rss(pid):
    try: return int(subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True).stdout.split()[0]) // 1024  # KiB to MiB, Linux and Mac
    except Exception: return 0

def health():
    try:
        c = http.client.HTTPConnection("127.0.0.1", PORT, timeout=2); c.request("GET", "/health"); r = c.getresponse(); r.read(); c.close(); return r.status
    except Exception: return 0

def start():
    return subprocess.Popen([BIN, "serve", D, "--port", str(PORT)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, env=env)

def wait_ready(p, limit=900, cap=9000):
    t = time.time(); peak = 0
    while time.time() - t < limit:
        peak = max(peak, rss(p.pid))
        if health() == 200: return time.time() - t, peak
        if p.poll() is not None: print("server died", p.stderr.read()[:500]); sys.exit(1)
        if peak > cap: p.kill(); print(f"killed past {cap} MiB"); sys.exit(1)
        time.sleep(0.02)
    p.kill(); print("not ready in time"); sys.exit(1)

def post(c, path, body, key):
    c.request("POST", path, body, {"authorization": "Bearer ada", "idempotency-key": key, "content-type": "application/json"})
    r = c.getresponse(); return r.status, r.read().decode()

if os.path.exists(D): shutil.rmtree(D)
os.makedirs(D)
p = start(); t0, _ = wait_ready(p)
c = http.client.HTTPConnection("127.0.0.1", PORT)
ids = []
for i in range(200):
    st, b = post(c, "/accounts", json.dumps({"name": f"acct{i}", "currency": "USD", "overdraft": 1000000000}), f"open-{i}")
    ids.append(json.loads(b)["id"] if st == 201 else None)
if None in ids: print("account creation failed"); p.kill(); sys.exit(1)

def worker(w):
    cc = http.client.HTTPConnection("127.0.0.1", PORT)
    i = w
    while i < N:
        st, b = post(cc, "/transfers", json.dumps({"from": ids[i % 200], "to": ids[(i * 7 + 1) % 200], "amount": 1 + i % 50}), f"t-{i}")
        if st != 201: print("transfer", i, st, b[:200]); os._exit(1)
        i += 32

t = time.time(); ths = [threading.Thread(target=worker, args=(w,)) for w in range(32)]
[th.start() for th in ths]; [th.join() for th in ths]
dt = time.time() - t
print(f"{N} transfers in {dt:.1f}s, {N/dt:.0f}/s, rss {rss(p.pid)} MiB (cores {CORES or 'machine'})")
p.send_signal(signal.SIGKILL); p.wait()
size = sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(D) for f in fs)
print(f"log {size/1e6:.1f} MB")
for run in range(REPLAYS):
    p = start(); took, peak = wait_ready(p); print(f"replay {N}: run {run+1} {took:.1f}s peak {peak} MiB"); p.kill(); p.wait()
if "--keep" not in sys.argv: shutil.rmtree(D)
