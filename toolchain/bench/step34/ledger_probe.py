#!/usr/bin/env python3
"""ledger_probe.py CMD... :: DIR N PORT: step 34's ledger load (interpreter-step-30-suite/ledger_load.py's
client: 200 accounts, N transfers from 32 clients, a fresh key each) against a server this script starts
itself as `CMD serve DIR --port PORT`, in a process group of its own. A watchdog kills the group past
4 GB resident or 600 s; at the end the group gets TERM (so MO_STATS=1 prints), then KILL after 10 s,
and the script checks no process of the group is left. Prints the rate, the peak resident memory, and
the seconds the load spent in each tenth of the transfers (a compaction that stalls shows there)."""
import http.client, json, os, shutil, signal, subprocess, sys, threading, time

cut = sys.argv.index("::")
CMD, (D, N, PORT) = sys.argv[1:cut], sys.argv[cut + 1:cut + 4]
N, PORT = int(N), int(PORT)
assert "scratch" in D, "data only in a scratch folder"
if os.path.exists(D): shutil.rmtree(D)
os.makedirs(D)
p = subprocess.Popen(CMD + ["serve", D, "--port", str(PORT)], stdout=subprocess.DEVNULL, start_new_session=True)
peak = [0]; stop = [False]

def rss():
    out = subprocess.run(["ps", "-o", "rss=", "-g", str(p.pid)], capture_output=True, text=True).stdout.split()
    return sum(int(x) for x in out) // 1024

def watch():
    t0 = time.time()
    while not stop[0] and p.poll() is None:
        peak[0] = max(peak[0], rss())
        if peak[0] > 4096 or time.time() - t0 > 600:
            print(f"watchdog: killed at {peak[0]} MiB, {time.time() - t0:.0f} s", flush=True)
            os.killpg(p.pid, signal.SIGKILL); return
        time.sleep(0.5)

threading.Thread(target=watch, daemon=True).start()

def post(c, path, body, key):
    c.request("POST", path, body, {"authorization": "Bearer ada", "idempotency-key": key, "content-type": "application/json"})
    r = c.getresponse(); return r.status, r.read().decode()

def ready():
    for _ in range(600):
        try:
            c = http.client.HTTPConnection("127.0.0.1", PORT, timeout=2); c.request("GET", "/health")
            r = c.getresponse(); r.read()
            if r.status == 200: return True
        except Exception: pass
        if p.poll() is not None: return False
        time.sleep(0.05)
    return False

def end(code):
    stop[0] = True
    if p.poll() is None:
        os.killpg(p.pid, signal.SIGTERM)
        try: p.wait(timeout=10)
        except subprocess.TimeoutExpired: os.killpg(p.pid, signal.SIGKILL); p.wait()
    try: os.killpg(p.pid, signal.SIGKILL)
    except ProcessLookupError: pass
    left = subprocess.run(["pgrep", "-g", str(p.pid)], capture_output=True, text=True).stdout.split()
    print(f"left after the run: {left or 'none'}")
    shutil.rmtree(D, ignore_errors=True)
    sys.exit(code)

if not ready(): print("server not ready"); end(1)
c = http.client.HTTPConnection("127.0.0.1", PORT)
ids = []
for i in range(200):
    st, b = post(c, "/accounts", json.dumps({"name": f"acct{i}", "currency": "USD", "overdraft": 1000000000}), f"open-{i}")
    ids.append(json.loads(b)["id"] if st == 201 else None)
if None in ids: print("account creation failed"); end(1)
done = [0]; lock = threading.Lock(); failed = []

def worker(w):
    cc = http.client.HTTPConnection("127.0.0.1", PORT, timeout=120)
    i = w
    try:
        while i < N:
            st, b = post(cc, "/transfers", json.dumps({"from": ids[i % 200], "to": ids[(i * 7 + 1) % 200], "amount": 1 + i % 50}), f"t-{i}")
            if st != 201: failed.append((i, st, b[:100])); return
            with lock: done[0] += 1
            i += 32
    except Exception as e: failed.append((i, repr(e)))

t = time.time(); marks = []
ths = [threading.Thread(target=worker, args=(w,), daemon=True) for w in range(32)]
[th.start() for th in ths]
next_mark = N // 10
while any(th.is_alive() for th in ths):
    time.sleep(0.05)
    if done[0] >= next_mark: marks.append(round(time.time() - t, 1)); next_mark += N // 10
dt = time.time() - t
print(f"{done[0]} transfers in {dt:.1f}s, {done[0]/dt:.0f}/s, peak {peak[0]} MiB, tenths at {marks}, failed {failed[:2]}", flush=True)
end(1 if failed or done[0] < N else 0)
