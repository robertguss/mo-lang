"""restartmem.py run|bin N [ROUNDS], with MO (the mo to run), JOBQ_DIR (the change 3 jobq folder), and JOBQ (its
built binary, default JOBQ_DIR/zig-out/mo-build/jobq/jobq): a jobq log of N jobs, serve --crash-every 1 --max-restarts 1000, ROUNDS creates each
followed by /health; prints resident memory before and after, growth per restart, restart time, stderr bytes."""
import http.client, json, os, shutil, signal, socket, subprocess, sys, tempfile, threading, time
SP = os.path.dirname(os.path.abspath(__file__))
MO = os.environ.get("MO", "toolchain/zig-out/bin/mo")
JOBQ_DIR = os.environ.get("JOBQ_DIR", "jobq")
runtime, N = sys.argv[1], int(sys.argv[2]); ROUNDS = int(sys.argv[3]) if len(sys.argv) > 3 else 30
cmd = [MO, "run", JOBQ_DIR + "/main.mo", "--"] if runtime == "run" else [os.environ.get("JOBQ", JOBQ_DIR + "/zig-out/mo-build/jobq/jobq")]
d = tempfile.mkdtemp(prefix="rmem-")
with open(os.path.join(d, "jobq.log"), "w") as f:
    f.write(f"SET ids {N + 1}\n")
    for i in range(1, N + 1):
        j = {"id": f"j_{i}", "queue": f"q{i % 8}", "state": "queued", "payload": f"payload number {i} " + "x" * 60, "tries": 0, "max_tries": 3, "backoff_ms": 0, "created_at": "2026-09-16T09:00:00.000Z", "updated_at": "2026-09-16T09:00:00.000Z"}
        f.write(f"SET j_{i} {json.dumps(j)}\n")
s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close()
err = open(os.path.join(d, "stderr"), "w")
p = subprocess.Popen(cmd + ["serve", d, "--port", str(port), "--crash-every", "1", "--max-restarts", "1000"], stdout=subprocess.DEVNULL, stderr=err)
t0 = time.time()
def rss():
    o = subprocess.run(["ps", "-o", "rss=", "-p", str(p.pid)], capture_output=True, text=True).stdout.strip()
    return int(o) * 1024 if o else 0
def guard():
    while p.poll() is None:
        if rss() > 4 << 30 or time.time() - t0 > 600: p.kill(); print("KILLED by the guard"); return
        time.sleep(0.2)
threading.Thread(target=guard, daemon=True).start()
def req(method, path, body=None):
    try:
        c = http.client.HTTPConnection("127.0.0.1", port, timeout=30)
        c.request(method, path, body=json.dumps(body) if body is not None else None, headers={"authorization": "Bearer t"})
        r = c.getresponse(); b = r.read(); c.close()
        return r.status, (json.loads(b) if b else None)
    except (OSError, http.client.HTTPException, ValueError): return 0, None
while req("GET", "/health")[0] != 200:
    if p.poll() is not None or time.time() - t0 > 120: print("did not start", p.poll(), open(os.path.join(d, "stderr")).read()[:400]); sys.exit(1)
    time.sleep(0.02)
up = time.time() - t0
time.sleep(0.5); before = rss(); times = []; rows = []
for i in range(ROUNDS):
    st, h = req("GET", "/health"); n0 = h["restarts"] if h else -1
    t = time.time(); st, _ = req("POST", "/jobs", {"queue": "q", "payload": "x", "max_tries": 1})
    while True:
        st, h = req("GET", "/health")
        if st == 200 and h and h.get("restarts", -1) > n0: break
        if p.poll() is not None or time.time() - t > 60: print("no restart", st, h); break
        time.sleep(0.002)
    times.append(time.time() - t); rows.append(rss())
time.sleep(0.5); after = rss()
if os.environ.get('VMMAP'): print(subprocess.run(['vmmap', '--summary', str(p.pid)], capture_output=True, text=True).stdout)
p.send_signal(signal.SIGTERM)
try: p.wait(10)
except subprocess.TimeoutExpired: p.kill()
err.close()
eb = os.path.getsize(os.path.join(d, "stderr"))
print(f"{runtime} N={N}: up {up:.2f}s, rss before {before/2**20:.1f} MiB, after {ROUNDS} restarts {after/2**20:.1f} MiB, growth/restart {(after-before)/ROUNDS/2**20:.2f} MiB, "
      f"restart best {min(times):.3f}s median {sorted(times)[len(times)//2]:.3f}s, stderr {eb/2**20:.1f} MiB, rss after 1st {rows[0]/2**20:.1f} MiB")
print("ROWS", " ".join(f"{r/2**20:.1f}" for r in rows))
shutil.rmtree(d, ignore_errors=True)
