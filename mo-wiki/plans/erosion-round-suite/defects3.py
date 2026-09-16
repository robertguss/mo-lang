#!/usr/bin/env python3
"""The erosion round's fourth hidden suite, for change 3 (mo-wiki/spec/programs/01d-job-queue-change-3.md).
Written by Fable on 16 Sep 2026 after the four maintainers' sessions started (10:22); never shown to a worker.

Categories: `flags` (the new serve options and /health's `restarts`), `restart` (the chaos switch under load:
every answer 2xx, 4xx, 503, or a closed connection; /health 200 within one second of every gap; every 2xx write
on the board after, and again after a stop and start; restarts counted), `leases` (a lease held across a
restart keeps its holder and its lease_until; ids never repeat), `budget` (failures faster than the window:
exit 70 with the log whole and `verify` exit 0; failures slower than the window: no exit), `count` (restarts
goes up by exactly one per failure). Round 8's two suites and the third suite are the regressions for this
generation and run separately.

usage: defects3.py --serve '<cmd> serve {dir} --port {port}' --verify '<cmd> verify {dir}' [--cwd DIR] [--only NAME]
The serve template gets the change's options appended (" --crash-every N" and so on).
The harness (Server, req, create, lease, get, health, check) is round 8's, imported from control-run-8-suite.
"""
import argparse, json, os, shutil, signal, subprocess, sys, tempfile, threading, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "control-run-8-suite"))
import defects as d8
from defects import Server, req, create, lease, get, health, check

def run(cmd, cwd, timeout=60):
    p = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    return p.returncode, (p.stdout + p.stderr).strip()

def safe(method, path, body=None, token="ada", timeout=5.0):
    """a request whose connection the failure may close: -1 stands for a closed or refused connection"""
    try: return req(method, path, body, token=token, timeout=timeout)
    except Exception as e: return -1, type(e).__name__

def wait_health(deadline_s=5.0):
    """seconds until /health answers 200, or None"""
    t0 = time.time()
    while time.time() - t0 < deadline_s:
        st, _ = safe("GET", "/health", token=None, timeout=1.0)
        if st == 200: return time.time() - t0
        time.sleep(0.01)
    return None

def restarts_of():
    st, h = safe("GET", "/health", token=None)
    return h.get("restarts") if st == 200 and isinstance(h, dict) else None

def fresh_dir(prefix):
    base = tempfile.mkdtemp(prefix=prefix); d = os.path.join(base, "dir"); os.mkdir(d); return base, d

def serve_with(a, d, opts):
    s = Server(a.serve + opts, a.cwd, d); took = s.start(); d8.PORT = s.port; return s, took

# ---------------------------------------------------------------- flags
def t_flags(a):
    base, d = fresh_dir("flags-")
    for opts, why in ((" --crash-every 0", "crash-every 0"), (" --max-restarts 3 --restart-window 10", "a budget"), (" --crash-every 1000 --max-restarts 5 --restart-window 60", "every option")):
        try:
            s, took = serve_with(a, d, opts)
            st, h = safe("GET", "/health", token=None)
            check(f"flags: serve accepts {why} and answers /health", st == 200, (st, h))
            check(f"flags: /health carries restarts 0 at start ({why})", isinstance(h, dict) and h.get("restarts") == 0, h)
            s.stop()
        except Exception as e:
            check(f"flags: serve accepts {why}", False, f"{type(e).__name__}: {e}")
    for opts in (" --crash-every -1", " --crash-every abc", " --max-restarts 0.5", " --restart-window x"):
        port = d8.free_port(); cmd = (a.serve + opts).format(dir=d, port=port)
        p = subprocess.Popen(cmd, shell=True, cwd=a.cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, preexec_fn=os.setsid)
        try: p.wait(timeout=10); rc = p.returncode
        except subprocess.TimeoutExpired: os.killpg(os.getpgid(p.pid), signal.SIGKILL); p.wait(); rc = "still serving"
        check(f"flags: `{opts.strip()}` is a usage error, exit 2", rc == 2, rc)
    rc, out = run(a.verify.format(dir=d) + " --crash-every 5", a.cwd)
    check("flags: verify does not take --crash-every (exit 2)", rc == 2, (rc, out[:120]))
    shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------- restart under load
def t_restart(a):
    base, d = fresh_dir("restart-")
    s, took = serve_with(a, d, " --crash-every 40 --max-restarts 1000 --restart-window 60")
    stop = threading.Event(); lock = threading.Lock()
    created, acked, leased_open, statuses = {}, {}, {}, {}
    def worker(i):
        q = f"q{i % 4}"; tok = f"w{i}"
        while not stop.is_set():
            st, b = safe("POST", "/jobs", {"queue": q, "payload": "p", "max_tries": 3}, token=tok)
            with lock: statuses[st] = statuses.get(st, 0) + 1
            if st == 201: created[b["id"]] = True
            st, b = safe("POST", f"/queues/{q}/lease", {"lease_ms": 30000}, token=tok)
            with lock: statuses[st] = statuses.get(st, 0) + 1
            if st == 200 and isinstance(b, dict) and b.get("id"):
                jid = b["id"]
                with lock: leased_open[jid] = tok
                st2, _ = safe("POST", f"/jobs/{jid}/ack", token=tok)
                with lock: statuses[st2] = statuses.get(st2, 0) + 1
                if st2 == 200:
                    with lock: acked[jid] = True; leased_open.pop(jid, None)
            if st in (-1, 503): time.sleep(0.02)
    gaps = []  # (start, length) of every run of non-200 health answers
    def poller():
        bad_since = None
        while not stop.is_set():
            st, _ = safe("GET", "/health", token=None, timeout=1.0)
            now = time.time()
            if st != 200 and bad_since is None: bad_since = now
            if st == 200 and bad_since is not None: gaps.append((bad_since, now - bad_since)); bad_since = None
            time.sleep(0.02)
        if bad_since is not None: gaps.append((bad_since, time.time() - bad_since))
    ths = [threading.Thread(target=worker, args=(i,), daemon=True) for i in range(8)] + [threading.Thread(target=poller, daemon=True)]
    t0 = time.time()
    for t in ths: t.start()
    time.sleep(6.0); stop.set(); time.sleep(0.5)
    back = wait_health(5.0)
    check("restart: the service answers /health after 6 s of load with a failure every 40 writes", back is not None, back)
    ok_statuses = {200, 201, 204, 400, 401, 404, 409, 503, -1}
    check("restart: every answer is 2xx, 4xx, 503, or a closed connection", all(st in ok_statuses for st in statuses), statuses)
    check("restart: the load got through (over 500 creates acknowledged)", len(created) > 500, len(created))
    longest = max((g[1] for g in gaps), default=0.0)
    check("restart: /health is 200 within one second of every failure (longest gap)", longest <= 1.0, f"{longest:.2f}s over {len(gaps)} gaps")
    r = restarts_of()
    n_writes = statuses.get(201, 0) + statuses.get(200, 0)
    check("restart: /health counts at least one restart", isinstance(r, int) and r >= 1, r)
    check("restart: restarts is no more than one per 40 writes plus one", isinstance(r, int) and r <= n_writes // 40 + 2, (r, n_writes))
    # what survived, on the running service
    def audit(where):
        lost_ack, lost_create, bad_lease = [], [], []
        for jid in list(acked):
            st, b = safe("GET", f"/jobs/{jid}")
            if st != 200 or b.get("state") != "done": lost_ack.append((jid, st, b.get("state") if isinstance(b, dict) else b))
        for jid in list(created):
            st, b = safe("GET", f"/jobs/{jid}")
            if st != 200: lost_create.append((jid, st))
        for jid, tok in list(leased_open.items()):
            st, b = safe("GET", f"/jobs/{jid}")
            if st != 200 or b.get("state") not in ("leased", "queued", "scheduled", "done"): bad_lease.append((jid, st, b))
        check(f"restart: every acked job is done ({where})", not lost_ack, lost_ack[:3])
        check(f"restart: every created job is present ({where})", not lost_create, lost_create[:3])
        check(f"restart: every open lease is leased, queued, or scheduled ({where})", not bad_lease, bad_lease[:3])
    audit("running")
    # the disk's view
    s.stop(); rc, out = run(a.verify.format(dir=d), a.cwd)
    check("restart: verify exits 0 on the folder after the run", rc == 0, (rc, out[:160]))
    s, took = serve_with(a, d, "")
    check("restart: the folder reopens without the switch", took < 20, took)
    audit("after a stop and start")
    check("restart: restarts is 0 after a fresh start", restarts_of() == 0, restarts_of())
    s.stop(); shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------- leases and ids across a restart
def t_leases(a):
    base, d = fresh_dir("leases-")
    s, took = serve_with(a, d, " --crash-every 5 --max-restarts 100 --restart-window 60")
    st, j1 = create(queue="q", payload="p", max_tries=2); st, j2 = create(queue="q", payload="p", max_tries=2)
    st, l = lease("q", ms=60000, token="w1"); check("leases: a lease before the failure", st == 200, (st, l))
    held = l.get("id") if isinstance(l, dict) else None; until = l.get("lease_until") if isinstance(l, dict) else None
    seen = {j1.get("id"), j2.get("id"), held}
    # the 5th write fails: creates until a 503 or a closed connection
    failed_at = None
    for i in range(12):
        st, b = safe("POST", "/jobs", {"queue": "x", "payload": "p", "max_tries": 1})
        if st == 201: seen.add(b["id"])
        if st in (503, -1): failed_at = i; break
    check("leases: the fifth write fails with 503 or a closed connection", failed_at is not None, failed_at)
    back = wait_health(5.0); check("leases: /health 200 within one second", back is not None and back <= 1.0, back)
    st, b = get(held)
    check("leases: the job leased before the failure is still leased to its worker", st == 200 and b.get("state") == "leased" and b.get("worker") == "w1", (st, b))
    check("leases: with the same lease_until", st == 200 and b.get("lease_until") == until, (b.get("lease_until") if isinstance(b, dict) else b, until))
    st, _ = req("POST", f"/jobs/{held}/ack", token="w1"); check("leases: the holder acks it after the restart", st == 200, st)
    st, _ = req("POST", f"/jobs/{j2['id']}/ack", token="w1"); check("leases: an ack without a lease is still 409", st == 409, st)
    # ids never repeat: create past another failure and compare
    new = []
    for i in range(12):
        st, b = safe("POST", "/jobs", {"queue": "y", "payload": "p", "max_tries": 1})
        if st == 201: new.append(b["id"])
        if st in (503, -1): wait_health(5.0)
    nums = lambda ids: [int(i.split("_")[1]) for i in ids if isinstance(i, str) and "_" in i]
    check("leases: no id handed out twice across restarts", not (set(new) & seen) and len(set(new)) == len(new), (sorted(set(new) & seen), len(new)))
    check("leases: ids keep rising across restarts", nums(new) == sorted(nums(new)) and (not nums(new) or min(nums(new)) > max(nums(seen))), (nums(new)[:5], max(nums(seen), default=0)))
    r = restarts_of(); check("leases: restarts counted at least twice", isinstance(r, int) and r >= 2, r)
    s.stop(); shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------- the budget
def t_budget(a):
    # faster than the window: exit 70, the log whole
    base, d = fresh_dir("budget-")
    s, took = serve_with(a, d, " --crash-every 1 --max-restarts 2 --restart-window 30")
    statuses = []; t0 = time.time(); acked_ids = []
    while time.time() - t0 < 20 and s.proc.poll() is None:
        st, b = safe("POST", "/jobs", {"queue": "b", "payload": "p", "max_tries": 1})
        statuses.append(st)
        if st == 201: acked_ids.append(b["id"])
        if st in (503, -1): wait_health(3.0)
    try: s.proc.wait(timeout=5)
    except subprocess.TimeoutExpired: pass
    check("budget: the third failure inside the window ends the service", s.proc.poll() is not None, f"still running after {len(statuses)} writes: {statuses[-6:]}")
    check("budget: with exit code 70", s.proc.returncode == 70, s.proc.returncode)
    check("budget: it took no more than five failures to get there", sum(1 for st in statuses if st in (503, -1)) <= 5, statuses)
    rc, out = run(a.verify.format(dir=d), a.cwd); check("budget: verify exits 0 on the folder it left", rc == 0, (rc, out[:160]))
    s.kill()
    s2, took = serve_with(a, d, ""); check("budget: the folder reopens", took < 20, took)
    check("budget: every 201 job is on the reopened board", all(get(i)[0] == 200 for i in acked_ids), acked_ids[:3])
    check("budget: restarts is 0 on the fresh start", restarts_of() == 0, restarts_of())
    s2.stop(); shutil.rmtree(base, ignore_errors=True)
    # slower than the window: a fresh count each time, no exit
    base, d = fresh_dir("budget2-")
    s, took = serve_with(a, d, " --crash-every 1 --max-restarts 1 --restart-window 1")
    fails = 0
    for i in range(4):
        st, b = safe("POST", "/jobs", {"queue": "b", "payload": "p", "max_tries": 1})
        if st in (503, -1): fails += 1
        back = wait_health(3.0)
        time.sleep(1.6)
    check("budget: four failures 1.6 s apart under a window of 1 s and the service is still serving", s.proc.poll() is None and fails >= 3, (s.proc.poll(), fails))
    check("budget: and /health answers", wait_health(2.0) is not None, None)
    s.stop(); shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------- the count
def t_count(a):
    base, d = fresh_dir("count-")
    s, took = serve_with(a, d, " --crash-every 1 --max-restarts 100 --restart-window 60")
    check("count: restarts 0 before any failure", restarts_of() == 0, restarts_of())
    for n in (1, 2, 3):
        st, b = safe("POST", "/jobs", {"queue": "c", "payload": "p", "max_tries": 1})
        check(f"count: write {n} fails with 503 or a closed connection", st in (503, -1), st)
        back = wait_health(3.0)
        check(f"count: restarts is {n} after failure {n}", restarts_of() == n, restarts_of())
        if st == 201 or st == -1 or st == 503:
            # the record the failure interrupted is on the board after the restart: j_n exists
            st2, b2 = get(f"j_{n}")
            check(f"count: the write the failure interrupted is on the board (j_{n})", st2 == 200, (st2, b2))
    st, h = safe("GET", "/health", token=None)
    check("count: /health's other counts agree with three creates", isinstance(h, dict) and h.get("queued") == 3, h)
    s.stop(); shutil.rmtree(base, ignore_errors=True)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--serve", required=True); ap.add_argument("--verify", required=True)
    ap.add_argument("--cwd", default=None); ap.add_argument("--only", default=None)
    a = ap.parse_args()
    for name, fn in (("flags", t_flags), ("count", t_count), ("leases", t_leases), ("restart", t_restart), ("budget", t_budget)):
        if a.only and name != a.only: continue
        try: fn(a)
        except Exception as e: check(f"{name}: ran to the end", False, f"{type(e).__name__}: {e}")
    print(f"\n{len(d8.PASSES)} passed, {len(d8.DEFECTS)} defects")
    for name, detail in d8.DEFECTS: print(f"  - {name}: {str(detail)[:300]}")

if __name__ == "__main__": main()
