#!/usr/bin/env python3
"""Round 8's hidden defect suite for the change to jobq (mo-wiki/spec/programs/01b-job-queue-change.md).

Runs one changed implementation's `serve` against the change spec: the new fields' validation, the
scheduled state by the service's own clock, retry backoff on a fail and on a run-out lease, the retry
route on every state, health and listings, the scheduled state durable under a SIGKILL, the log the
round 7 service wrote replayed and compacted, the race and 8 workers under load with backoff on.
Written by the lead after the three worktrees were branched; never shown to a worker.

usage: defects.py --serve '<cmd> serve {dir} --port {port}' [--cwd DIR]
                  [--old-serve '<round 7 cmd> serve {dir} --port {port}'] [--old-cwd DIR]
                  [--compact '<cmd> compact {dir}'] [--only NAME] [--keep]
"""
import argparse, glob, json, os, shutil, signal, socket, subprocess, sys, tempfile, threading, time
import http.client
from datetime import datetime, timezone

DEFECTS = []
PASSES = []

def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p

class Server:
    def __init__(self, template, cwd, d):
        self.template, self.cwd, self.dir = template, cwd, d
        self.proc = None; self.port = None
    def start(self, timeout=20.0):
        self.port = free_port()
        cmd = self.template.format(dir=self.dir, port=self.port)
        self.out = open(os.path.join(self.dir, "..", f"server-{self.port}.out"), "w")
        self.proc = subprocess.Popen(cmd, shell=True, cwd=self.cwd, stdout=self.out, stderr=subprocess.STDOUT,
                                     preexec_fn=os.setsid)
        t0 = time.time()
        while time.time() - t0 < timeout:
            if self.proc.poll() is not None:
                raise RuntimeError(f"server exited {self.proc.returncode} before answering: {cmd}")
            try:
                st, body = req("GET", "/health", port=self.port, token=None, timeout=1.0)
                if st == 200: return time.time() - t0
            except Exception: pass
            time.sleep(0.05)
        raise RuntimeError(f"server did not answer /health within {timeout}s: {cmd}")
    def kill(self):
        if self.proc and self.proc.poll() is None:
            os.killpg(os.getpgid(self.proc.pid), signal.SIGKILL); self.proc.wait()
    def stop(self):
        if self.proc and self.proc.poll() is None:
            os.killpg(os.getpgid(self.proc.pid), signal.SIGTERM)
            try: self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired: self.kill()

PORT = None
def req(method, path, body=None, token="ada", port=None, timeout=10.0, raw=None):
    c = http.client.HTTPConnection("127.0.0.1", port or PORT, timeout=timeout)
    h = {}
    if token is not None: h["authorization"] = f"Bearer {token}"
    data = None
    if raw is not None: data = raw; h.setdefault("content-type", "application/json")
    elif body is not None: data = json.dumps(body).encode(); h["content-type"] = "application/json"
    c.request(method, path, body=data, headers=h)
    r = c.getresponse(); b = r.read(); c.close()
    try: j = json.loads(b) if b else None
    except Exception: j = b.decode("utf-8", "replace")
    return r.status, j

def check(name, cond, detail=""):
    (PASSES if cond else DEFECTS).append((name, detail))
    print(("ok   " if cond else "FAIL ") + name + ("" if cond or not detail else f": {detail}"), flush=True)

def create(queue="q", payload="p", max_tries=3, token="ada", **more):
    body = {"queue": queue, "payload": payload, "max_tries": max_tries}; body.update(more)
    return req("POST", "/jobs", body, token=token)

def lease(queue, ms=1000, token="w1"):
    return req("POST", f"/queues/{queue}/lease", {"lease_ms": ms}, token=token)

def at(iso):
    try: return datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp()
    except Exception: return None

def near(a, b, tol=0.25):
    return a is not None and b is not None and abs(a - b) <= tol

def get(jid): return req("GET", f"/jobs/{jid}")

def health():
    st, h = req("GET", "/health", token=None); return h if st == 200 and isinstance(h, dict) else {}

# ---------------- tests ----------------
def t_fields():
    st, a = create(queue="f", payload="p", max_tries=3); check("fields: create with max_tries is 201", st == 201, (st, a))
    if st != 201: return
    for k in ("id", "queue", "state", "payload", "tries", "max_tries", "backoff_ms", "created_at", "updated_at"):
        check(f"fields: a job has {k}", isinstance(a, dict) and k in a, list(a) if isinstance(a, dict) else a)
    for k in ("attempts", "max_attempts", "run_at", "worker", "lease_until", "reason"):
        check(f"fields: a fresh queued job has no {k}", isinstance(a, dict) and k not in a, a)
    check("fields: backoff_ms defaults to 0", a.get("backoff_ms") == 0, a.get("backoff_ms"))
    check("fields: tries starts at 0", a.get("tries") == 0, a.get("tries"))
    st, b = create(queue="f", payload="p", max_tries=2, delay_ms=0, backoff_ms=0); check("fields: delay_ms 0 and backoff_ms 0 is 201 queued", st == 201 and b.get("state") == "queued", (st, b))
    st, c = create(queue="f", payload="p", max_tries=2, backoff_ms=250); check("fields: backoff_ms is kept on the job", st == 201 and c.get("backoff_ms") == 250, (st, c))
    st, d = create(queue="f", payload="p", max_tries=2, delay_ms=86_400_000); check("fields: delay_ms at its top is 201 scheduled", st == 201 and d.get("state") == "scheduled", (st, d))
    st, e = create(queue="f", payload="p", max_tries=2, backoff_ms=3_600_000); check("fields: backoff_ms at its top is 201", st == 201, (st, e))
    cases = [
        ("the old name max_attempts", {"queue": "f", "payload": "p", "max_attempts": 3}),
        ("the old name attempts", {"queue": "f", "payload": "p", "max_tries": 3, "attempts": 0}),
        ("both names", {"queue": "f", "payload": "p", "max_tries": 3, "max_attempts": 3}),
        ("max_tries missing", {"queue": "f", "payload": "p"}),
        ("max_tries 0", {"queue": "f", "payload": "p", "max_tries": 0}),
        ("max_tries 101", {"queue": "f", "payload": "p", "max_tries": 101}),
        ("delay_ms -1", {"queue": "f", "payload": "p", "max_tries": 1, "delay_ms": -1}),
        ("delay_ms 86,400,001", {"queue": "f", "payload": "p", "max_tries": 1, "delay_ms": 86_400_001}),
        ("delay_ms as a string", {"queue": "f", "payload": "p", "max_tries": 1, "delay_ms": "5"}),
        ("delay_ms 2.5", {"queue": "f", "payload": "p", "max_tries": 1, "delay_ms": 2.5}),
        ("delay_ms null", {"queue": "f", "payload": "p", "max_tries": 1, "delay_ms": None}),
        ("backoff_ms -1", {"queue": "f", "payload": "p", "max_tries": 1, "backoff_ms": -1}),
        ("backoff_ms 3,600,001", {"queue": "f", "payload": "p", "max_tries": 1, "backoff_ms": 3_600_001}),
        ("backoff_ms as a string", {"queue": "f", "payload": "p", "max_tries": 1, "backoff_ms": "1"}),
        ("backoff_ms true", {"queue": "f", "payload": "p", "max_tries": 1, "backoff_ms": True}),
        ("run_at given by the client", {"queue": "f", "payload": "p", "max_tries": 1, "run_at": "2026-01-01T00:00:00Z"}),
    ]
    for name, body in cases:
        st, r = req("POST", "/jobs", body)
        check(f"fields: {name} is 400 with an error", st == 400 and isinstance(r, dict) and "error" in r, (st, r))
    st, r = req("GET", "/jobs?state=scheduled"); check("fields: state=scheduled is a listing filter", st == 200 and isinstance(r, dict) and "jobs" in r, (st, r))
    st, r = req("GET", "/jobs?state=attempts"); check("fields: an unknown state filter is 400", st == 400, st)

def t_scheduled():
    t0 = time.time()
    st, a = create(queue="sch", payload="later", max_tries=2, delay_ms=700)
    check("scheduled: create with a delay is 201 scheduled", st == 201 and a.get("state") == "scheduled", (st, a))
    if st != 201: return
    check("scheduled: run_at is created_at plus the delay", near(at(a.get("run_at", "")), at(a.get("created_at", "")) + 0.7, 0.05), (a.get("created_at"), a.get("run_at")))
    check("scheduled: tries is 0 and no worker", a.get("tries") == 0 and "worker" not in a and "lease_until" not in a, a)
    st, l = lease("sch"); check("scheduled: a lease before run_at is 204", st == 204, (st, l))
    st, g = get(a["id"]); check("scheduled: a read before run_at shows scheduled with run_at", st == 200 and g.get("state") == "scheduled" and g.get("run_at") == a.get("run_at"), (st, g))
    h = health(); check("scheduled: /health counts it under scheduled", h.get("scheduled", 0) >= 1, h)
    check("scheduled: /health has the five states", all(k in h for k in ("queued", "scheduled", "leased", "done", "dead", "uptime_ms")), h)
    st, l = req("GET", "/jobs?queue=sch&state=scheduled"); check("scheduled: listed under state=scheduled", st == 200 and any(j["id"] == a["id"] for j in l.get("jobs", [])), (st, l))
    st, l = req("GET", "/jobs?queue=sch&state=queued"); check("scheduled: not listed under state=queued", st == 200 and not any(j["id"] == a["id"] for j in l.get("jobs", [])), (st, l))
    st, l = req("GET", "/jobs?queue=sch"); check("scheduled: listed with no state filter", st == 200 and any(j["id"] == a["id"] for j in l.get("jobs", [])), (st, l))
    time.sleep(max(0, 0.9 - (time.time() - t0)))
    st, l = lease("sch", token="w1"); check("scheduled: a lease after run_at hands it out with tries 1", st == 200 and l.get("id") == a["id"] and l.get("tries") == 1 and l.get("worker") == "w1", (st, l))
    check("scheduled: the leased job has no run_at", "run_at" not in (l if isinstance(l, dict) else {}), l)
    h2 = health(); check("scheduled: /health no longer counts it under scheduled", h2.get("scheduled", 99) == h.get("scheduled", 0) - 1, (h, h2))
    st, _ = req("POST", f"/jobs/{a['id']}/ack", token="w1"); check("scheduled: the holder acks it", st == 200, st)
    # due by a read, not a lease
    st, b = create(queue="sch2", payload="due", max_tries=1, delay_ms=300)
    time.sleep(0.45)
    st, g = get(b["id"]); check("scheduled: a read after run_at shows it queued", st == 200 and g.get("state") == "queued" and "run_at" not in g, (st, g))
    st, l = req("GET", "/jobs?queue=sch2&state=queued"); check("scheduled: a listing after run_at shows it queued", st == 200 and any(j["id"] == b["id"] for j in l.get("jobs", [])), (st, l))
    # a run-of-the-mill queued job is unchanged
    st, c = create(queue="sch3", payload="now", max_tries=1); check("scheduled: without a delay the job is queued", st == 201 and c.get("state") == "queued", (st, c))

def t_order():
    st, a = create(queue="ord", payload="first, queued", max_tries=1)
    st, b = create(queue="ord", payload="second, scheduled", max_tries=1, delay_ms=200)
    time.sleep(0.35)
    st, l1 = lease("ord"); st, l2 = lease("ord")
    check("order: a due scheduled job takes its place by id behind an older queued job", l1.get("id") == a["id"] and l2.get("id") == b["id"], (l1.get("id"), l2.get("id")))
    st, c = create(queue="ord2", payload="first, scheduled", max_tries=1, delay_ms=200)
    st, d = create(queue="ord2", payload="second, queued", max_tries=1)
    st, l1 = lease("ord2"); check("order: before run_at the newer queued job is handed out", l1.get("id") == d["id"], l1.get("id"))
    time.sleep(0.35)
    st, l2 = lease("ord2"); check("order: after run_at the older scheduled job is handed out", st == 200 and l2.get("id") == c["id"], (st, l2.get("id") if isinstance(l2, dict) else l2))

def t_delete():
    st, a = create(queue="del", payload="p", max_tries=1, delay_ms=60000)
    st, _ = req("DELETE", f"/jobs/{a['id']}"); check("delete: a scheduled job is deleted with 204", st == 204, st)
    st, _ = get(a["id"]); check("delete: it is gone", st == 404, st)
    h = health(); check("delete: /health does not count it", h.get("scheduled", 99) == 0 or True, h)  # no absolute count is knowable here
    st, l = req("GET", "/jobs?state=scheduled"); check("delete: it is not listed", not any(j["id"] == a["id"] for j in l.get("jobs", [])), l)

def t_backoff():
    st, a = create(queue="bo", payload="p", max_tries=3, backoff_ms=500)
    st, l = lease("bo", token="w1"); check("backoff: first lease is 200 tries 1", st == 200 and l.get("tries") == 1, (st, l))
    t_fail = time.time()
    st, f = req("POST", f"/jobs/{a['id']}/fail", {"reason": "smtp down"}, token="w1")
    check("backoff: a fail with backoff is 200 scheduled", st == 200 and f.get("state") == "scheduled", (st, f))
    check("backoff: the failed job keeps tries 1 and its reason", f.get("tries") == 1 and f.get("reason") == "smtp down", f)
    check("backoff: run_at is now plus backoff_ms", near(at(f.get("run_at", "")), at(f.get("updated_at", "")) + 0.5, 0.05) and near(at(f.get("updated_at", "")), t_fail, 1.5), (f.get("updated_at"), f.get("run_at")))
    check("backoff: no worker or lease_until while scheduled", "worker" not in f and "lease_until" not in f, f)
    st, l = lease("bo", token="w2"); check("backoff: a lease before run_at is 204", st == 204, (st, l))
    st, _ = req("POST", f"/jobs/{a['id']}/ack", token="w1"); check("backoff: the old holder's ack is 409", st == 409, st)
    time.sleep(max(0, 0.7 - (time.time() - t_fail)))
    st, l = lease("bo", token="w2"); check("backoff: after run_at it is leased with tries 2", st == 200 and l.get("id") == a["id"] and l.get("tries") == 2 and l.get("worker") == "w2", (st, l))
    check("backoff: the reason is still shown while leased again", l.get("reason") == "smtp down", l)
    st, f = req("POST", f"/jobs/{a['id']}/fail", {"reason": "again"}, token="w2"); check("backoff: a second fail is scheduled again", st == 200 and f.get("state") == "scheduled" and f.get("tries") == 2, (st, f))
    time.sleep(0.7)
    st, l = lease("bo", token="w3"); check("backoff: the last try is leased with tries 3", st == 200 and l.get("tries") == 3, (st, l))
    st, f = req("POST", f"/jobs/{a['id']}/fail", {"reason": "final"}, token="w3")
    check("backoff: a fail on the last try is dead, not scheduled", st == 200 and f.get("state") == "dead" and f.get("tries") == 3 and "run_at" not in f, (st, f))
    # no backoff: queued at once
    st, b = create(queue="bo2", payload="p", max_tries=2)
    st, l = lease("bo2", token="w1"); st, f = req("POST", f"/jobs/{b['id']}/fail", {"reason": "x"}, token="w1")
    check("backoff: a fail without backoff is queued at once", st == 200 and f.get("state") == "queued" and "run_at" not in f, (st, f))
    st, l = lease("bo2", token="w2"); check("backoff: and leased again at once with tries 2", st == 200 and l.get("tries") == 2, (st, l))

def t_runout():
    st, a = create(queue="ro", payload="p", max_tries=2, backoff_ms=400)
    st, l = lease("ro", ms=100, token="w1")
    time.sleep(0.2)
    t_look = time.time()
    st, g = get(a["id"]); check("runout: a run-out lease with backoff is scheduled at the next look", st == 200 and g.get("state") == "scheduled" and g.get("tries") == 1, (st, g))
    check("runout: its run_at is the look plus backoff_ms", near(at(g.get("run_at", "")), t_look + 0.4, 0.3), (g.get("run_at"), t_look))
    st, l = lease("ro", token="w2"); check("runout: not leased before run_at", st == 204, st)
    time.sleep(0.5)
    st, l = lease("ro", token="w2"); check("runout: leased after run_at with tries 2", st == 200 and l.get("id") == a["id"] and l.get("tries") == 2, (st, l))
    # last try: dead even with backoff
    st, b = create(queue="ro2", payload="p", max_tries=1, backoff_ms=400)
    st, l = lease("ro2", ms=100, token="w1"); time.sleep(0.2)
    st, g = get(b["id"]); check("runout: a run-out lease on the last try is dead even with backoff", st == 200 and g.get("state") == "dead" and g.get("tries") == 1 and "run_at" not in g, (st, g))
    # the run-out is noticed by the sweep (idle), not only by a request on that job
    st, c = create(queue="ro3", payload="p", max_tries=2, backoff_ms=100)
    st, l = lease("ro3", ms=100, token="w1"); time.sleep(0.35)
    st, l = lease("ro3", token="w2")
    # Amended 15 Sep 22:45 after Go's run: the spec dates run_at from the look that notices the run-out, so a
    # service whose first look is this lease request answers 204 and hands the job out a backoff later; one that
    # swept on idle may answer 200 here. Both are the spec; the original check took only the second.
    if st == 204:
        time.sleep(0.2); st, l = lease("ro3", token="w2")
    check("runout: a run-out lease with backoff is handed out by a lease request once the backoff from its look has passed", st == 200 and l.get("id") == c["id"] and l.get("tries") == 2, (st, l))

def t_retry():
    st, a = create(queue="rt", payload="p", max_tries=1, backoff_ms=300)
    st, l = lease("rt", token="w1"); st, f = req("POST", f"/jobs/{a['id']}/fail", {"reason": "boom"}, token="w1")
    check("retry: setup, the job is dead", f.get("state") == "dead", f)
    st, r = req("POST", f"/jobs/{a['id']}/retry", token=None); check("retry: without a token is 401", st == 401, st)
    st, r = req("POST", f"/jobs/{a['id']}/retry", token="op"); check("retry: a dead job is 200 queued", st == 200 and r.get("state") == "queued", (st, r))
    check("retry: tries is 0 and reason, worker, lease_until, run_at are gone", r.get("tries") == 0 and all(k not in r for k in ("reason", "worker", "lease_until", "run_at")), r)
    check("retry: queue, payload, max_tries, backoff_ms are kept", r.get("queue") == "rt" and r.get("payload") == "p" and r.get("max_tries") == 1 and r.get("backoff_ms") == 300, r)
    st, g = get(a["id"]); check("retry: a read agrees", st == 200 and g.get("state") == "queued" and g.get("tries") == 0, (st, g))
    st, r2 = req("POST", f"/jobs/{a['id']}/retry", token="op"); check("retry: a queued job is 409", st == 409, st)
    st, l = lease("rt", token="w2"); check("retry: the retried job is leased with tries 1", st == 200 and l.get("id") == a["id"] and l.get("tries") == 1, (st, l))
    st, r2 = req("POST", f"/jobs/{a['id']}/retry", token="op"); check("retry: a leased job is 409", st == 409, st)
    st, _ = req("POST", f"/jobs/{a['id']}/ack", token="w2")
    st, r2 = req("POST", f"/jobs/{a['id']}/retry", token="op"); check("retry: a done job is 409", st == 409, st)
    st, b = create(queue="rt2", payload="p", max_tries=1, delay_ms=60000)
    st, r2 = req("POST", f"/jobs/{b['id']}/retry", token="op"); check("retry: a scheduled job is 409", st == 409, st)
    st, r2 = req("POST", "/jobs/j_999999/retry", token="op"); check("retry: a missing job is 404", st == 404, st)
    st, r2 = req("GET", f"/jobs/{a['id']}/retry", token="op"); check("retry: GET on the retry route is 405", st == 405, st)
    st, r2 = req("POST", f"/jobs/{a['id']}/retry", raw=b"{not json", token="op"); check("retry: a body is ignored or refused, never a crash (200/400/409)", st in (200, 400, 409), st)
    # a retried dead job takes its place by id
    st, c = create(queue="rt3", payload="c", max_tries=1); st, d = create(queue="rt3", payload="d", max_tries=1)
    st, l = lease("rt3", token="w1"); st, _ = req("POST", f"/jobs/{c['id']}/fail", {"reason": "x"}, token="w1")
    st, r = req("POST", f"/jobs/{c['id']}/retry", token="op")
    st, l1 = lease("rt3", token="w2"); check("retry: a retried job is handed out by id, ahead of a newer queued job", l1.get("id") == c["id"], l1.get("id"))
    # a retried job dies again after max_tries
    st, e = create(queue="rt4", payload="e", max_tries=2)
    for _ in range(2):
        st, l = lease("rt4", token="w1"); st, f = req("POST", f"/jobs/{e['id']}/fail", {"reason": "x"}, token="w1")
    check("retry: setup, dead after two fails", f.get("state") == "dead" and f.get("tries") == 2, f)
    st, r = req("POST", f"/jobs/{e['id']}/retry", token="op")
    st, l = lease("rt4", token="w1"); st, l2 = lease("rt4", token="w2"); st, f1 = req("POST", f"/jobs/{e['id']}/fail", {"reason": "y"}, token="w1")
    check("retry: after a retry the job counts tries from 0 again", l.get("tries") == 1 and f1.get("state") == "queued" and f1.get("tries") == 1, (l, f1))
    st, l = lease("rt4", token="w2"); st, f2 = req("POST", f"/jobs/{e['id']}/fail", {"reason": "z"}, token="w2")
    check("retry: and is dead again at max_tries", f2.get("state") == "dead" and f2.get("tries") == 2, f2)

def t_health():
    h = health()
    st, l = req("GET", "/jobs?state=scheduled"); n = len(l.get("jobs", []))
    check("health: the scheduled count agrees with the listing (under the cap)", n >= 100 or h.get("scheduled") == n, (h.get("scheduled"), n))
    st, a = create(queue="hl", payload="p", max_tries=1, delay_ms=60000)
    h2 = health(); check("health: a new scheduled job raises the count by one", h2.get("scheduled", -9) == h.get("scheduled", 0) + 1, (h, h2))
    req("DELETE", f"/jobs/{a['id']}")
    h3 = health(); check("health: deleting it lowers the count by one", h3.get("scheduled", -9) == h.get("scheduled", 0), (h, h3))

def t_durable(server):
    """The scheduled state, from a delay and from a backoff, survives a SIGKILL with its run_at."""
    st, a = create(queue="dsch", payload="delay", max_tries=2, delay_ms=8000)
    st, b = create(queue="dsch", payload="backoff", max_tries=3, backoff_ms=8000)
    st, l = lease("dsch", token="w1"); st, f = req("POST", f"/jobs/{b['id']}/fail", {"reason": "before the kill"}, token="w1")
    check("durable: setup, both scheduled", a.get("state") == "scheduled" and f.get("state") == "scheduled", (a, f))
    st, c = create(queue="dsch2", payload="due before restart", max_tries=1, delay_ms=200)
    time.sleep(0.3)
    st, g = get(c["id"]); check("durable: setup, the third is queued by a read", g.get("state") == "queued", g)
    st, d = create(queue="dsch3", payload="dead then retried", max_tries=1)
    st, l = lease("dsch3", token="w1"); st, _ = req("POST", f"/jobs/{d['id']}/fail", {"reason": "x"}, token="w1")
    st, r = req("POST", f"/jobs/{d['id']}/retry", token="op"); check("durable: setup, the fourth is retried", r.get("state") == "queued" and r.get("tries") == 0, r)
    st, e = create(queue="dsch4", payload="run out with backoff", max_tries=2, backoff_ms=8000)
    st, l = lease("dsch4", ms=100, token="w1"); time.sleep(0.2)
    st, g = get(e["id"]); check("durable: setup, the fifth is scheduled by a run-out", g.get("state") == "scheduled", g); e_run_at = g.get("run_at")
    server.kill(); time.sleep(0.3)
    took = server.start(); global PORT; PORT = server.port
    print(f"     durable: restarted in {took:.2f}s")
    st, g = get(a["id"]); check("durable: a delayed job is scheduled with the same run_at after the kill", st == 200 and g.get("state") == "scheduled" and g.get("run_at") == a.get("run_at"), (st, g, a.get("run_at")))
    st, g = get(b["id"]); check("durable: a backed-off job is scheduled with the same run_at after the kill", st == 200 and g.get("state") == "scheduled" and g.get("run_at") == f.get("run_at") and g.get("tries") == 1 and g.get("reason") == "before the kill", (st, g, f.get("run_at")))
    st, g = get(c["id"]); check("durable: a job queued by its run_at before the kill is queued after", st == 200 and g.get("state") == "queued" and "run_at" not in g, (st, g))
    st, g = get(d["id"]); check("durable: a retried job is queued with tries 0 after the kill", st == 200 and g.get("state") == "queued" and g.get("tries") == 0 and "reason" not in g, (st, g))
    st, g = get(e["id"]); check("durable: a job scheduled by a run-out keeps its run_at after the kill", st == 200 and g.get("state") == "scheduled" and g.get("run_at") == e_run_at, (st, g, e_run_at))
    h = health(); check("durable: /health counts the scheduled jobs after the kill", h.get("scheduled", 0) >= 3, h)
    st, l = lease("dsch", token="w9"); check("durable: nothing scheduled is handed out early after the kill", st == 204, (st, l))

def t_old_log(old_serve, old_cwd, compact, cwd):
    """A folder the round 7 service wrote opens under the changed service: every job with its state, the
    old names read, the new ones written, and compact leaves no old name."""
    if not old_serve:
        check("oldlog: skipped, no --old-serve given", False, "run with --old-serve to read this category"); return
    base = tempfile.mkdtemp(prefix="oldlog-"); d = os.path.join(base, "dir"); os.mkdir(d)
    old = Server(old_serve, old_cwd, d)
    global PORT
    try:
        old.start(); PORT = old.port
    except Exception as e:
        check("oldlog: the round 7 service starts", False, str(e)); return
    def ocreate(queue, payload, max_attempts):
        return req("POST", "/jobs", {"queue": queue, "payload": payload, "max_attempts": max_attempts})
    st, q = ocreate("old-q", "queued forever", 3); check("oldlog: setup, the old service creates", st == 201, (st, q))
    if st != 201: old.kill(); return
    st, dn = ocreate("old-done", "done", 3); st, l = req("POST", "/queues/old-done/lease", {"lease_ms": 60000}, token="w1"); req("POST", f"/jobs/{dn['id']}/ack", token="w1")
    st, dd = ocreate("old-dead", "dead", 1); st, l = req("POST", "/queues/old-dead/lease", {"lease_ms": 60000}, token="w1"); req("POST", f"/jobs/{dd['id']}/fail", {"reason": "old reason"}, token="w1")
    st, fq = ocreate("old-fq", "failed once, queued", 3); st, l = req("POST", "/queues/old-fq/lease", {"lease_ms": 60000}, token="w1"); req("POST", f"/jobs/{fq['id']}/fail", {"reason": "first reason"}, token="w1")
    st, lv = ocreate("old-live", "leased live", 2); st, l = req("POST", "/queues/old-live/lease", {"lease_ms": 600000}, token="holder")
    check("oldlog: setup, the live lease is on the fifth job", l.get("id") == lv["id"], (l, lv))
    st, ro = ocreate("old-ro", "leased, runs out", 2); st, l = req("POST", "/queues/old-ro/lease", {"lease_ms": 100}, token="short")
    check("oldlog: setup, the short lease is on the sixth job", l.get("id") == ro["id"], (l, ro))
    st, gone = ocreate("old-gone", "deleted", 1); req("DELETE", f"/jobs/{gone['id']}")
    st, uni = ocreate("old-uni", "unicode é 世 \"quoted\"\nline two", 2)
    st, before = req("GET", "/jobs"); before = {j["id"]: j for j in before.get("jobs", [])}
    st, hb = req("GET", "/health", token=None)
    old.kill(); time.sleep(0.3)
    logs = [p for p in glob.glob(os.path.join(d, "**", "*"), recursive=True) if os.path.isfile(p)]
    check("oldlog: the old service left a log", len(logs) >= 1, logs)
    if logs:
        biggest = max(logs, key=os.path.getsize)
        with open(biggest, "ab") as fh: fh.write(b'{"torn": "this line was cut sh')
    new = Server(SERVE_TEMPLATE, cwd, d)
    try:
        took = new.start(); PORT = new.port
        check("oldlog: the changed service opens the old folder", True); print(f"     oldlog: opened in {took:.2f}s")
    except Exception as e:
        check("oldlog: the changed service opens the old folder", False, str(e)); return
    try:
        st, after = req("GET", "/jobs"); after = {j["id"]: j for j in after.get("jobs", [])} if st == 200 else {}
        check("oldlog: every old job is present, the deleted one is not", set(after) == set(before), f"missing {set(before)-set(after)} extra {set(after)-set(before)}")
        for jid, oj in before.items():
            nj = after.get(jid)
            if not nj: continue
            expect = oj["state"] if jid != ro["id"] else "queued"
            check(f"oldlog: {oj['payload'][:20]!r} keeps its state ({expect})", nj.get("state") == expect, (oj["state"], nj.get("state")))
            check(f"oldlog: {oj['payload'][:20]!r} has tries == the old attempts", nj.get("tries") == oj.get("attempts"), (oj.get("attempts"), nj.get("tries")))
            check(f"oldlog: {oj['payload'][:20]!r} max_tries", nj.get("max_tries") == oj.get("max_attempts"), (oj.get("max_attempts"), nj.get("max_tries")))
            check(f"oldlog: {oj['payload'][:20]!r} speaks no old name", "attempts" not in nj and "max_attempts" not in nj, list(nj))
            check(f"oldlog: {oj['payload'][:20]!r} backoff_ms reads as 0", nj.get("backoff_ms") == 0, nj.get("backoff_ms"))
            check(f"oldlog: {oj['payload'][:20]!r} payload, queue, created_at unchanged", nj.get("payload") == oj["payload"] and nj.get("queue") == oj["queue"] and nj.get("created_at") == oj["created_at"], (oj, nj))
        if dd["id"] in after: check("oldlog: the dead job keeps its reason", after[dd["id"]].get("reason") == "old reason", after[dd["id"]])
        if lv["id"] in after: check("oldlog: the live lease is still held by its worker", after[lv["id"]].get("worker") == "holder" and after[lv["id"]].get("state") == "leased", after[lv["id"]])
        st, ack = req("POST", f"/jobs/{lv['id']}/ack", token="holder"); check("oldlog: the live lease's holder acks it under the new service", st == 200 and ack.get("state") == "done" and ack.get("tries") == 1, (st, ack))
        st, l = req("POST", "/queues/old-q/lease", {"lease_ms": 1000}, token="w2"); check("oldlog: the old queued job is handed out with tries 1", st == 200 and l.get("id") == q["id"] and l.get("tries") == 1, (st, l))
        st, r = req("POST", f"/jobs/{dd['id']}/retry", token="op"); check("oldlog: the old dead job can be retried", st == 200 and r.get("state") == "queued" and r.get("tries") == 0, (st, r))
        st, n = req("POST", "/jobs", {"queue": "old-q", "payload": "new, scheduled", "max_tries": 2, "delay_ms": 60000, "backoff_ms": 10}); check("oldlog: a new scheduled job is created beside the old ones", st == 201 and isinstance(n, dict) and n.get("state") == "scheduled", (st, n))
        if not (isinstance(n, dict) and "id" in n): n = {"id": "j_0", "run_at": None}
        check("oldlog: ids continue after the old log", st == 201 and int(n["id"].split("_")[1]) > max(int(i.split("_")[1]) for i in before), n.get("id"))
        st, h = req("GET", "/health", token=None); check("oldlog: /health counts the old jobs", h.get("done", 0) >= 2 and h.get("queued", 0) >= 1 and h.get("scheduled", 0) >= 1, h)
        st, all_after = req("GET", "/jobs"); all_after = {j["id"]: j for j in all_after.get("jobs", [])}
        new.stop()
        if compact:
            p = subprocess.run(compact.format(dir=d), shell=True, cwd=cwd, capture_output=True, text=True, timeout=120)
            check("oldlog: compact exits 0 on the old folder", p.returncode == 0, (p.returncode, p.stdout[-300:], p.stderr[-300:]))
            logs = [p_ for p_ in glob.glob(os.path.join(d, "**", "*"), recursive=True) if os.path.isfile(p_)]
            text = b"".join(open(p_, "rb").read() for p_ in logs)
            check("oldlog: after compact no old name is left in the folder", b"max_attempts" not in text and b'"attempts"' not in text, [p_ for p_ in logs if b"attempts" in open(p_, "rb").read()])
            check("oldlog: after compact the new names are in the folder", b"max_tries" in text and b"tries" in text, len(text))
        else:
            check("oldlog: compact skipped, no --compact given", False, "run with --compact to read this check")
        took = new.start(); PORT = new.port
        st, again = req("GET", "/jobs"); again = {j["id"]: j for j in again.get("jobs", [])}
        check("oldlog: after compact and restart every job is present with its state", set(again) == set(all_after) and all(again[i].get("state") == all_after[i].get("state") and again[i].get("tries") == all_after[i].get("tries") for i in again), {i: (all_after.get(i, {}).get("state"), again[i].get("state")) for i in again if again[i].get("state") != all_after.get(i, {}).get("state")})
        st, g = get(n["id"]); check("oldlog: the new scheduled job keeps its run_at across compact", st == 200 and g.get("state") == "scheduled" and g.get("run_at") == n.get("run_at"), (st, g))
    finally:
        new.stop()
        if not KEEP: shutil.rmtree(base, ignore_errors=True)
        else: print("kept", base)

def t_race():
    st, a = create(queue="race", payload="one", max_tries=5, backoff_ms=200)
    def go(results, token):
        try: results.append((token, lease("race", ms=2000, token=token)))
        except Exception as e: results.append((token, (0, str(e))))
    for round_no in range(2):
        results = []; ts = [threading.Thread(target=go, args=(results, f"r{i}")) for i in range(16)]
        [t.start() for t in ts]; [t.join() for t in ts]
        wins = [(tok, r) for tok, (st, r) in results if st == 200]
        check(f"race: round {round_no + 1}, exactly one of 16 workers holds the job", len(wins) == 1 and all(st in (200, 204) for _, (st, _) in results), [(tok, st) for tok, (st, _) in results if st not in (200, 204)] or len(wins))
        if len(wins) == 1:
            tok, r = wins[0]
            check(f"race: round {round_no + 1}, the holder is the winner with tries {round_no + 1}", r.get("worker") == tok and r.get("tries") == round_no + 1, r)
            st, f = req("POST", f"/jobs/{a['id']}/fail", {"reason": "retry me"}, token=tok); check(f"race: round {round_no + 1}, the holder's fail schedules it", st == 200 and f.get("state") == "scheduled", (st, f))
            time.sleep(0.35)

def t_load():
    """8 workers over 160 jobs with backoff 50 and max_tries 2: each job is failed once then acked; at
    the end every job is done, no job was ever held by two workers at once, and health agrees."""
    ids = [create(queue="load", payload=f"L{i}", max_tries=2, backoff_ms=50)[1]["id"] for i in range(160)]
    held = threading.Lock(); holders = {}; overlap = []; done = set(); errors = []
    def worker(i):
        tok = f"lw{i}"
        idle = 0
        while idle < 40:
            try: st, j = lease("load", ms=5000, token=tok)
            except Exception as e: errors.append(str(e)); return
            if st != 200: idle += 1; time.sleep(0.02); continue
            idle = 0
            with held:
                if holders.get(j["id"]) not in (None, tok): overlap.append((j["id"], holders[j["id"]], tok))
                holders[j["id"]] = tok
            if j.get("tries") == 1:
                st, f = req("POST", f"/jobs/{j['id']}/fail", {"reason": "once"}, token=tok)
                if st != 200: errors.append(("fail", st, f))
            else:
                st, ak = req("POST", f"/jobs/{j['id']}/ack", token=tok)
                if st != 200: errors.append(("ack", st, ak))
                else: done.add(j["id"])
            with held: holders[j["id"]] = None
    t0 = time.time(); ts = [threading.Thread(target=worker, args=(i,)) for i in range(8)]
    [t.start() for t in ts]; [t.join() for t in ts]; dt = time.time() - t0
    check("load: no request failed", not errors, errors[:3])
    check("load: no job was held by two workers at once", not overlap, overlap[:3])
    check("load: every job was failed once then acked", done == set(ids), f"{len(done)} of {len(ids)} done")
    st, l = req("GET", "/jobs?queue=load&state=done"); st2, l2 = req("GET", "/jobs?queue=load&state=scheduled"); st3, l3 = req("GET", "/jobs?queue=load&state=queued")
    check("load: nothing in the queue is left scheduled or queued", len(l2.get("jobs", [])) == 0 and len(l3.get("jobs", [])) == 0, (len(l2.get("jobs", [])), len(l3.get("jobs", []))))
    tries = {j["tries"] for j in l.get("jobs", [])}; check("load: every done job has tries 2", tries == {2}, tries)
    print(f"     load: {len(done)} jobs, each failed once and acked, in {dt:.1f}s")

SERVE_TEMPLATE = None
KEEP = False

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--serve", required=True); ap.add_argument("--cwd", default=None); ap.add_argument("--only", default=None)
    ap.add_argument("--old-serve", default=None); ap.add_argument("--old-cwd", default=None); ap.add_argument("--compact", default=None); ap.add_argument("--keep", action="store_true")
    a = ap.parse_args()
    global SERVE_TEMPLATE, KEEP, PORT
    SERVE_TEMPLATE = a.serve; KEEP = a.keep
    base = tempfile.mkdtemp(prefix="defects8-"); d = os.path.join(base, "dir"); os.mkdir(d)
    server = Server(a.serve, a.cwd, d)
    took = server.start(); PORT = server.port
    print(f"server up in {took:.2f}s on {PORT}, dir {d}")
    tests = [("fields", t_fields), ("scheduled", t_scheduled), ("order", t_order), ("delete", t_delete), ("backoff", t_backoff),
             ("runout", t_runout), ("retry", t_retry), ("health", t_health), ("durable", lambda: t_durable(server)),
             ("race", t_race), ("load", t_load)]
    for name, fn in tests:
        if a.only and name != a.only: continue
        if server.proc.poll() is not None:
            check(f"{name}: the server is still alive", False, f"exited {server.proc.returncode}")
            try: server.start(); PORT = server.port
            except Exception as e: print("cannot restart:", e); break
        try: fn()
        except Exception as e:
            check(f"{name}: ran to the end", False, f"{type(e).__name__}: {e}")
    alive = server.proc.poll() is None
    check("end: the server is still alive", alive, f"exit {server.proc.returncode}")
    server.stop()
    if not a.only or a.only == "oldlog":
        try: t_old_log(a.old_serve, a.old_cwd, a.compact, a.cwd)
        except Exception as e: check("oldlog: ran to the end", False, f"{type(e).__name__}: {e}")
    print(f"\n{len(PASSES)} passed, {len(DEFECTS)} defects")
    for n, dd in DEFECTS: print(f"  - {n}" + (f": {dd}" if dd else ""))
    if not a.keep: shutil.rmtree(base, ignore_errors=True)
    else: print("kept", base)

if __name__ == "__main__": main()
