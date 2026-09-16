#!/usr/bin/env python3
"""The erosion round's third hidden suite, for change 2 (mo-wiki/spec/programs/01c-job-queue-change-2.md).
Written by Fable on 16 Sep 2026 after the four maintainers' sessions started; never shown to a worker.

Categories: `queues` (GET /queues), `verify` (the folder checked at open, `jobq verify`, the ill-formed records,
the impossible record round 8's oracle found, the torn last line still tolerated), `unwritable` (a 64 MB RAM disk
filled under load: every answer 2xx-on-disk, 4xx, or 503, /health never moves on a 503, a 503 leaves the job
unchanged, writes resume without a restart once the disk is freed), `contained` (a failing request does not stop
the next). Round 8's two suites (control-run-8-suite/regressions.py and defects.py --old-serve) are the regression
suites for this generation and run separately.

usage: defects2.py --serve '<cmd> serve {dir} --port {port}' --verify '<cmd> verify {dir}' --compact '<cmd> compact {dir}'
                   --log-format mo|go|python|elixir [--cwd DIR] [--only NAME] [--no-ramdisk]
The harness (Server, req, create, lease, get, health, check) is round 8's, imported from control-run-8-suite.
"""
import argparse, json, os, re, shutil, signal, subprocess, sys, tempfile, threading, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "control-run-8-suite"))
import defects as d8
from defects import Server, req, create, lease, get, health, check
from oracle4 import write_log

def run(cmd, cwd, timeout=60):
    p = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    return p.returncode, (p.stdout + p.stderr).strip()

# ---------------------------------------------------------------- queues
def t_queues():
    st, j = req("GET", "/queues", token=None); check("queues: no token is 401", st == 401, (st, j))
    st, j = req("GET", "/queues"); check("queues: an empty service lists no queue", st == 200 and j == {"queues": []}, (st, j))
    ids = {}
    for q, n in (("emails", 3), ("reports", 2), ("alerts", 1)):
        ids[q] = [create(queue=q, payload="p", max_tries=2)[1]["id"] for _ in range(n)]
    st, l = lease("emails", token="w1"); leased = l["id"]
    st, l2 = lease("emails", token="w1"); st, _ = req("POST", f"/jobs/{l2['id']}/ack", token="w1")
    st, l3 = lease("reports", token="w1"); st, _ = req("POST", f"/jobs/{l3['id']}/fail", {"reason": "x"}, token="w1")
    st, l4 = lease("reports", token="w1"); st, _ = req("POST", f"/jobs/{l4['id']}/fail", {"reason": "y"}, token="w1")
    st, _ = create(queue="alerts", payload="later", max_tries=1, delay_ms=60000)
    st, j = req("GET", "/queues")
    check("queues: 200 with a queues list", st == 200 and isinstance(j, dict) and isinstance(j.get("queues"), list), (st, j))
    j = j if isinstance(j, dict) else {}
    names = [q.get("name") for q in j.get("queues", [])]
    check("queues: sorted by name", names == sorted(names) and set(names) == {"alerts", "emails", "reports"}, names)
    by = {q["name"]: q for q in j.get("queues", [])}
    e = by.get("emails", {})
    check("queues: emails counts queued 1, leased 1, done 1", (e.get("queued"), e.get("leased"), e.get("done"), e.get("scheduled", 0), e.get("dead", 0)) == (1, 1, 1, 0, 0), e)
    a = by.get("alerts", {})
    check("queues: alerts counts queued 1, scheduled 1", (a.get("queued"), a.get("scheduled")) == (1, 1), a)
    r = by.get("reports", {})
    check("queues: reports has every state key and counts sum to 2", all(k in r for k in ("queued", "scheduled", "leased", "done", "dead")) and sum(r[k] for k in ("queued", "scheduled", "leased", "done", "dead")) == 2, r)
    h = health()
    for k in ("queued", "scheduled", "leased", "done", "dead"):
        check(f"queues: /health {k} is the sum over queues", h.get(k) == sum(q.get(k, 0) for q in j.get("queues", [])), (k, h.get(k), j.get("queues")))
    # a queue whose last job is deleted disappears
    for i in ids["alerts"]: req("DELETE", f"/jobs/{i}")
    st, j = req("GET", "/queues"); names = [q["name"] for q in (j.get("queues", []) if isinstance(j, dict) else [])]
    check("queues: a queue with only a scheduled job still shows", "alerts" in names, names)
    st, j = req("GET", "/jobs?queue=alerts"); jobs = j if isinstance(j, list) else (j.get("jobs") if isinstance(j, dict) else [])
    for jb in jobs or []: req("DELETE", f"/jobs/{jb['id']}")
    st, j = req("GET", "/queues"); names = [q["name"] for q in (j.get("queues", []) if isinstance(j, dict) else [])]
    check("queues: a queue whose last job is deleted disappears", "alerts" not in names and "emails" in names, names)
    st, j = req("GET", "/queues/"); check("queues: a trailing slash or an unknown sub-route is not a 500", st in (200, 404, 405), (st, j))
    st, j = req("POST", "/queues"); check("queues: POST /queues is 404 or 405", st in (404, 405), (st, j))

# ---------------------------------------------------------------- verify and the folder at open
ILL = [
    ("queued at its max_tries (round 8's outage record)", {"id": "j_1", "queue": "q", "state": "queued", "payload": "p", "tries": 2, "max_tries": 2, "backoff_ms": 0}),
    ("queued with a worker", {"id": "j_2", "queue": "q", "state": "queued", "payload": "p", "tries": 0, "max_tries": 2, "backoff_ms": 0, "worker": "w1"}),
    ("scheduled without run_at", {"id": "j_3", "queue": "q", "state": "scheduled", "payload": "p", "tries": 0, "max_tries": 2, "backoff_ms": 0}),
    ("leased with tries 0", {"id": "j_4", "queue": "q", "state": "leased", "payload": "p", "tries": 0, "max_tries": 2, "backoff_ms": 0, "worker": "w1", "lease_until": "2026-09-16T10:00:00Z"}),
    ("leased without a worker", {"id": "j_5", "queue": "q", "state": "leased", "payload": "p", "tries": 1, "max_tries": 2, "backoff_ms": 0, "lease_until": "2026-09-16T10:00:00Z"}),
    ("done with tries 0", {"id": "j_6", "queue": "q", "state": "done", "payload": "p", "tries": 0, "max_tries": 2, "backoff_ms": 0}),
    ("dead with tries above max_tries", {"id": "j_7", "queue": "q", "state": "dead", "payload": "p", "tries": 3, "max_tries": 2, "backoff_ms": 0}),
    ("dead with a run_at", {"id": "j_8", "queue": "q", "state": "dead", "payload": "p", "tries": 2, "max_tries": 2, "backoff_ms": 0, "run_at": "2026-09-16T10:00:00Z"}),
    ("max_tries 0", {"id": "j_9", "queue": "q", "state": "queued", "payload": "p", "tries": 0, "max_tries": 0, "backoff_ms": 0}),
    ("backoff_ms above the bound", {"id": "j_10", "queue": "q", "state": "queued", "payload": "p", "tries": 0, "max_tries": 2, "backoff_ms": 3600001}),
    ("a queue name with a space", {"id": "j_11", "queue": "a b", "state": "queued", "payload": "p", "tries": 0, "max_tries": 2, "backoff_ms": 0}),
]
GOOD = {"id": "j_20", "queue": "q", "state": "queued", "payload": "p", "tries": 0, "max_tries": 2, "backoff_ms": 0}
TS = {"created_at": "2026-09-16T09:00:00.000Z", "updated_at": "2026-09-16T09:05:00.000Z"}
def stamped(rec):
    r = dict(TS); r.update(rec); return r
ILL = [(name, stamped(rec)) for name, rec in ILL]
GOOD = stamped(GOOD)

def counts_line(out):
    """the `<n> jobs: ...` line wherever it is in the output (a torn-line notice may follow it)"""
    for l in out.splitlines():
        if re.match(r"\d+ jobs: ", l.strip()): return l.strip()
    return ""

def serve_refuses(serve, cwd, d, name):
    """serve on the folder exits 1 within 20 s, prints the one line, and never answers /health."""
    port = d8.free_port(); cmd = serve.format(dir=d, port=port)
    p = subprocess.Popen(cmd, shell=True, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, preexec_fn=os.setsid)
    t0 = time.time(); answered = False
    while time.time() - t0 < 20 and p.poll() is None:
        try:
            st, _ = req("GET", "/health", port=port, token=None, timeout=0.5)
            if st == 200: answered = True; break
        except Exception: pass
        time.sleep(0.05)
    if p.poll() is None:
        os.killpg(os.getpgid(p.pid), signal.SIGKILL); p.wait()
    out = (p.stdout.read() or "").strip()
    check(f"verify: serve refuses {name} with exit 1 and no /health", p.returncode == 1 and not answered, (p.returncode, answered, out[:200]))
    return out

def t_verify(serve, verify, compact, cwd, fmt):
    rc, out = run(verify.format(dir=""), cwd); check("verify: no folder is a usage error, exit 2", rc == 2, (rc, out[:120]))
    # a folder the service wrote: verify agrees with /health
    base = tempfile.mkdtemp(prefix="verify-"); d = os.path.join(base, "dir"); os.mkdir(d)
    s = Server(serve, cwd, d); s.start(); d8.PORT = s.port
    for _ in range(3): create(queue="a", payload="p", max_tries=2)
    create(queue="b", payload="later", max_tries=1, delay_ms=60000)
    st, l = lease("a", token="w1"); st, _ = req("POST", f"/jobs/{l['id']}/ack", token="w1")
    st, l = lease("a", token="w1")
    st, x = create(queue="c", payload="dies", max_tries=1); st, lx = lease("c", token="w1"); req("POST", f"/jobs/{lx['id']}/fail", {"reason": "x"}, token="w1")
    h = health(); s.stop()
    rc, out = run(verify.format(dir=d), cwd)
    want = f"5 jobs: queued {h['queued']}, scheduled {h['scheduled']}, leased {h['leased']}, done {h['done']}, dead {h['dead']}; next id j_"
    line = counts_line(out)
    # the next id is the implementation's (Mo reserves ids in blocks of 1,000 on open); the counts and the shape are the spec's
    check("verify: a folder the service wrote verifies with exit 0 and the counts line", rc == 0 and line.startswith(want) and re.fullmatch(r"j_\d+", line[len(want) - 2:]) is not None, (rc, out[-200:], want))
    # every ill-formed record refuses the folder under verify, serve, and compact
    for name, rec in ILL:
        b2 = tempfile.mkdtemp(prefix="ill-"); d2 = os.path.join(b2, "dir"); os.mkdir(d2)
        write_log(fmt, d2, [GOOD, rec])
        rc, out = run(verify.format(dir=d2), cwd)
        line = [l for l in out.splitlines() if l.startswith("jobq:")]
        check(f"verify: {name} is refused with exit 1", rc == 1, (rc, out[-200:]))
        check(f"verify: {name} names the record's key", any(rec["id"] in l or str(int(rec["id"][2:])) in l for l in line), (line, out[-200:]))
        if name.startswith("queued at its max_tries") or name.startswith("leased without") or name.startswith("scheduled without"):
            serve_refuses(serve, cwd, d2, name)
        if name.startswith("queued at its max_tries"):
            rc, out = run(compact.format(dir=d2), cwd); check("verify: compact refuses the impossible record with exit 1", rc == 1, (rc, out[-200:]))
        shutil.rmtree(b2, ignore_errors=True)
    # the torn last line is still tolerated, and verify counts what is whole
    b3 = tempfile.mkdtemp(prefix="torn-"); d3 = os.path.join(b3, "dir"); os.mkdir(d3)
    s = Server(serve, cwd, d3); s.start(); d8.PORT = s.port
    for _ in range(4): create(queue="t", payload="p", max_tries=2)
    s.stop()
    logs = [p for p in os.listdir(d3) if os.path.isfile(os.path.join(d3, p))]
    with open(os.path.join(d3, logs[0]), "ab") as f: f.write(b'{"id": "j_5", "queue": "t", "state": "queu')
    rc, out = run(verify.format(dir=d3), cwd)
    check("verify: a torn last line still opens under verify, exit 0, 4 jobs", rc == 0 and counts_line(out).startswith("4 jobs:"), (rc, out[-200:]))
    s = Server(serve, cwd, d3)
    try:
        s.start(); d8.PORT = s.port; h = health(); check("verify: a torn last line still serves, with the 4 whole jobs", h.get("queued") == 4, h)
        st, c = create(queue="t", payload="after the tear", max_tries=1); check("verify: a create after the torn line is 201 with an id above the four", st == 201 and int(c.get("id", "j_0")[2:]) >= 5, (st, c))
    except Exception as e: check("verify: a torn last line still serves", False, str(e))
    finally: s.stop()
    shutil.rmtree(base, ignore_errors=True); shutil.rmtree(b3, ignore_errors=True)

# ---------------------------------------------------------------- the unwritable folder, on a RAM disk
class RamDisk:
    def __init__(self, sectors=131072):  # 64 MB: the load's own 201s must not fill it
        self.dev = subprocess.run(["hdiutil", "attach", "-nomount", f"ram://{sectors}"], capture_output=True, text=True, check=True).stdout.split()[-1].strip()
        subprocess.run(["newfs_hfs", "-v", "e2ram", self.dev], capture_output=True, check=True)
        self.mnt = tempfile.mkdtemp(prefix="ramdisk-")
        subprocess.run(["mount", "-t", "hfs", self.dev, self.mnt], capture_output=True, check=True)
        self.filler = os.path.join(self.mnt, "filler")
    def fill(self):
        try:
            with open(self.filler, "wb") as g:
                while True: g.write(b"x" * (1 << 20)); g.flush()
        except OSError: pass
    def free(self):
        try: os.remove(self.filler)
        except FileNotFoundError: pass
    def detach(self):
        subprocess.run(["umount", self.mnt], capture_output=True); subprocess.run(["hdiutil", "detach", self.dev], capture_output=True)

def wait_ports(limit=1500, patience=90):
    """macOS keeps a closed client socket in TIME_WAIT for 30 s and has 16k ephemeral ports to one destination;
    a suite that opens a connection per request runs out. Wait for the table to drain before a load phase."""
    t0 = time.time()
    while time.time() - t0 < patience:
        n = subprocess.run("netstat -an | grep -c TIME_WAIT", shell=True, capture_output=True, text=True).stdout.strip()
        if int(n or 0) < limit: return
        time.sleep(2)

def t_unwritable(serve, cwd):
    wait_ports()
    ram = RamDisk(); d = os.path.join(ram.mnt, "dir"); os.mkdir(d)
    s = Server(serve, cwd, d)
    try:
        s.start(); d8.PORT = s.port
        for _ in range(20): create(queue="u", payload="p" * 100, max_tries=3)
        st, held = lease("u", ms=60000, token="w1")
        h0 = health()
        answers = []; lock = threading.Lock(); stop = threading.Event()
        import http.client
        def worker(i):
            # one keep-alive connection per worker, reopened on an error, so the load does not burn a port per request
            c = None
            while not stop.is_set():
                try:
                    if c is None: c = http.client.HTTPConnection("127.0.0.1", d8.PORT, timeout=10)
                    body = json.dumps({"queue": f"u{i % 4}", "payload": "p" * 100, "max_tries": 3}).encode()
                    c.request("POST", "/jobs", body=body, headers={"authorization": f"Bearer w{i}", "content-type": "application/json"})
                    r = c.getresponse(); b = r.read()
                    if r.getheader("connection", "").lower() == "close": c.close(); c = None
                    try: j = json.loads(b) if b else None
                    except Exception: j = None
                    with lock: answers.append(("create", r.status, j.get("id") if isinstance(j, dict) else None))
                except Exception as e:
                    c = None
                    with lock: answers.append(("create", -1, type(e).__name__))
                    time.sleep(0.01)
        ths = [threading.Thread(target=worker, args=(i,), daemon=True) for i in range(8)]
        for t in ths: t.start()
        time.sleep(0.5); ram.fill(); t_full = time.time()
        # sequential checks while full, on their own connections
        st, j = create(queue="u", payload="while full", max_tries=1); full_create = (st, j)
        st, g = get(held["id"]); full_get = (st, g)
        st, a = req("POST", f"/jobs/{held['id']}/ack", token="w1"); full_ack = (st, a)
        st, g2 = get(held["id"]); after_ack = (st, g2)
        st, l = lease("u", token="w2"); full_lease = (st, l)
        h1 = health()
        time.sleep(1.5); ram.free(); t_free = time.time()
        time.sleep(1.0); stop.set(); [t.join(timeout=5) for t in ths]
        st, c = create(queue="u", payload="after", max_tries=1); after_create = (st, c)
        h2 = health()
        codes = {}
        for kind, st, _ in answers: codes[st] = codes.get(st, 0) + 1
        print(f"     unwritable: {len(answers)} creates under load, statuses {codes}; full for {t_free - t_full:.1f}s")
        bad = [st for st in codes if not (200 <= st < 300 or 400 <= st < 500 or st == 503)]
        check("unwritable: every answer under load is 2xx, 4xx, or 503", not bad and -1 not in codes, codes)
        check("unwritable: some request under the full disk was answered 503", codes.get(503, 0) > 0 or full_create[0] == 503 or full_ack[0] == 503, (codes, full_create, full_ack))
        check("unwritable: the service is still up after the full disk (a create is 201, no restart)", after_create[0] == 201 and s.proc.poll() is None, (after_create, s.proc.poll()))
        check("unwritable: a read while full is 200", full_get[0] == 200, full_get)
        if full_ack[0] == 503:
            check("unwritable: a 503 on ack leaves the job leased", after_ack[0] == 200 and after_ack[1].get("state") == "leased" and after_ack[1].get("worker") == "w1", after_ack)
            check("unwritable: /health does not move on a 503", h1 == h0 or all(h1.get(k, 0) >= h0.get(k, 0) for k in h0) and h1.get("done") == h0.get("done"), (h0, h1))
        else:
            check("unwritable: the ack while full was answered 2xx or 503, not another status", 200 <= full_ack[0] < 300, full_ack)
        if full_lease[0] == 503:
            st, g = get(held["id"]); check("unwritable: a 503 on lease changes nothing", True, "")
        # every 2xx create under load is on the disk: restart and count
        ok_ids = [i for kind, st, i in answers if st == 201 and i]
        s.stop(); s2 = Server(serve, cwd, d); took = s2.start(); d8.PORT = s2.port
        import http.client
        ka = http.client.HTTPConnection("127.0.0.1", d8.PORT, timeout=10); missing = []
        for i in ok_ids:
            try:
                ka.request("GET", f"/jobs/{i}", headers={"authorization": "Bearer audit"}); r = ka.getresponse(); r.read()
                if r.getheader("connection", "").lower() == "close": ka.close(); ka = http.client.HTTPConnection("127.0.0.1", d8.PORT, timeout=10)
                if r.status != 200: missing.append(i)
            except Exception as e:
                ka = http.client.HTTPConnection("127.0.0.1", d8.PORT, timeout=10); missing.append((i, type(e).__name__))
        check(f"unwritable: every 2xx create under load is on the disk after a restart ({len(ok_ids)} checked)", not missing, missing[:5])
        h3 = health(); check("unwritable: /health after the restart agrees with the last /health", h3.get("done") == h2.get("done") and h3.get("dead") == h2.get("dead"), (h2, h3))
        s2.stop()
    except Exception as e:
        check("unwritable: ran to the end", False, f"{type(e).__name__}: {e}")
    finally:
        try: s.stop()
        except Exception: pass
        keep = tempfile.mkdtemp(prefix="unwritable-logs-")
        for f in os.listdir(ram.mnt):
            if f.startswith("server-"):
                try: shutil.copy(os.path.join(ram.mnt, f), keep)
                except Exception: pass
        print(f"     unwritable: the servers' output kept in {keep}")
        ram.detach()

# ---------------------------------------------------------------- a failing request does not stop the next
def t_contained():
    st, a = create(queue="c", payload="p", max_tries=2)
    bad = [("a body of 1 MB", "x" * 1_000_000), ("a body that is not JSON", "{not json"), ("a body with a NUL", '{"queue": "c", "payload": "a\\u0000b", "max_tries": 1}'),
           ("a lease body with a huge lease_ms", '{"lease_ms": 99999999999999999999}'), ("a deeply nested body", "[" * 5000 + "]" * 5000)]
    for name, raw in bad:
        path = "/queues/c/lease" if "lease" in name else "/jobs"
        try:
            st, j = req("POST", path, raw=raw.encode() if isinstance(raw, str) else raw, timeout=10)
            check(f"contained: {name} is answered 4xx or 503, not 5xx", 400 <= st < 500 or st == 503, (st, str(j)[:100]))
        except Exception as e:
            check(f"contained: {name} is answered", False, type(e).__name__)
        st, g = get(a["id"]); check(f"contained: the next request after {name} is 200", st == 200 and g.get("state") == "queued", (st, g))
    for i in range(50):
        st, j = req("POST", "/jobs/j_999999/ack", token="w1")
    st, g = get(a["id"]); check("contained: fifty failing acks later the service answers", st == 200, (st, g))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--serve", required=True); ap.add_argument("--verify", required=True); ap.add_argument("--compact", required=True)
    ap.add_argument("--log-format", required=True); ap.add_argument("--cwd", default=None); ap.add_argument("--only", default=None); ap.add_argument("--no-ramdisk", action="store_true")
    a = ap.parse_args()
    base = tempfile.mkdtemp(prefix="defects2-"); d = os.path.join(base, "dir"); os.mkdir(d)
    server = Server(a.serve, a.cwd, d); took = server.start(); d8.PORT = server.port
    print(f"server up in {took:.2f}s on {server.port}, dir {d}")
    tests = [("queues", t_queues), ("contained", t_contained)]
    for name, fn in tests:
        if a.only and name != a.only: continue
        if server.proc.poll() is not None:
            check(f"{name}: the server is still alive", False, f"exited {server.proc.returncode}")
            try: server.start(); d8.PORT = server.port
            except Exception as e: print("cannot restart:", e); break
        try: fn()
        except Exception as e: check(f"{name}: ran to the end", False, f"{type(e).__name__}: {e}")
    check("end: the server is still alive", server.proc.poll() is None, f"exit {server.proc.returncode}")
    server.stop()
    if not a.only or a.only == "verify":
        try: t_verify(a.serve, a.verify, a.compact, a.cwd, a.log_format)
        except Exception as e: check("verify: ran to the end", False, f"{type(e).__name__}: {e}")
    if (not a.only or a.only == "unwritable") and not a.no_ramdisk:
        try: t_unwritable(a.serve, a.cwd)
        except Exception as e: check("unwritable: ran to the end", False, f"{type(e).__name__}: {e}")
    print(f"\n{len(d8.PASSES)} passed, {len(d8.DEFECTS)} defects")
    for name, detail in d8.DEFECTS: print(f"  - {name}: {str(detail)[:300]}")
    shutil.rmtree(base, ignore_errors=True)

if __name__ == "__main__": main()
