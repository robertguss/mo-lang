#!/usr/bin/env python3
"""Round 7's hidden defect suite for jobq (mo-wiki/spec/programs/01-job-queue.md).

Runs one implementation's `serve` command against the spec with adversarial input, races,
a kill mid-run, a torn log, and idle connections, and counts defects. Written by the lead
before the round; never shown to a worker.

usage: defects.py --serve '<cmd> serve {dir} --port {port}' [--cwd DIR] [--only NAME]
"""
import argparse, json, os, random, shutil, signal, socket, subprocess, sys, tempfile, threading, time
import http.client

DEFECTS = []   # (test, detail)
PASSES = []

def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p

class Server:
    def __init__(self, template, cwd, d):
        self.template, self.cwd, self.dir = template, cwd, d
        self.proc = None; self.port = None
    def start(self, timeout=15.0):
        self.port = free_port()
        cmd = self.template.format(dir=self.dir, port=self.port)
        self.out = open(os.path.join(self.dir, "..", f"server-{self.port}.out"), "w")
        self.proc = subprocess.Popen(cmd, shell=True, cwd=self.cwd, stdout=self.out, stderr=subprocess.STDOUT,
                                     preexec_fn=os.setsid)
        t0 = time.time()
        while time.time() - t0 < timeout:
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
def req(method, path, body=None, token="ada", port=None, timeout=10.0, raw=None, headers=None):
    c = http.client.HTTPConnection("127.0.0.1", port or PORT, timeout=timeout)
    h = {}
    if token is not None: h["authorization"] = f"Bearer {token}"
    if headers: h.update(headers)
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

def create(queue="q", payload="p", max_attempts=3, token="ada"):
    return req("POST", "/jobs", {"queue": queue, "payload": payload, "max_attempts": max_attempts}, token=token)

# ---------------- tests ----------------
def t_auth():
    st, _ = req("GET", "/jobs", token=None); check("auth: no token is 401", st == 401, st)
    st, _ = req("GET", "/jobs", token=""); check("auth: empty token is 401", st == 401, st)
    st, _ = req("GET", "/health", token=None); check("auth: /health needs no token", st == 200, st)
    st, _ = req("GET", "/jobs", token="a b"); check("auth: a token with a space is refused (401 or 400)", st in (400, 401), st)

def t_validation():
    cases = [
        ("non-JSON body", None, b"{not json"),
        ("missing payload", {"queue": "q", "max_attempts": 3}, None),
        ("queue 65 bytes", {"queue": "a" * 65, "payload": "p", "max_attempts": 3}, None),
        ("queue empty", {"queue": "", "payload": "p", "max_attempts": 3}, None),
        ("queue with a space", {"queue": "a b", "payload": "p", "max_attempts": 3}, None),
        ("payload with \\x01", {"queue": "q", "payload": "a\x01b", "max_attempts": 3}, None),
        ("payload 60 KiB + 1", {"queue": "q", "payload": "x" * (60 * 1024 + 1), "max_attempts": 3}, None),
        ("max_attempts 0", {"queue": "q", "payload": "p", "max_attempts": 0}, None),
        ("max_attempts 101", {"queue": "q", "payload": "p", "max_attempts": 101}, None),
        ("max_attempts as a string", {"queue": "q", "payload": "p", "max_attempts": "3"}, None),
        ("max_attempts 2.5", {"queue": "q", "payload": "p", "max_attempts": 2.5}, None),
        ("payload as a number", {"queue": "q", "payload": 5, "max_attempts": 3}, None),
        ("body is a list", None, b"[1,2]"),
        ("payload invalid UTF-8", None, b'{"queue": "q", "payload": "a\xffb", "max_attempts": 3}'),
    ]
    for name, body, raw in cases:
        try:
            st, j = req("POST", "/jobs", body=body, raw=raw)
            check(f"validation: {name} is 400", st == 400, f"{st} {str(j)[:80]}")
            if st == 400: check(f"validation: {name} carries an error string", isinstance(j, dict) and isinstance(j.get("error"), str), str(j)[:80])
        except Exception as e:
            check(f"validation: {name} is 400", False, f"connection failed: {e}")
    st, j = create(payload="x" * (60 * 1024)); check("validation: payload of exactly 60 KiB is 201", st == 201, st)
    st, j = create(payload="a\nb"); check("validation: a newline in the payload is allowed", st == 201, st)
    st, j = create(payload="a\tb"); check("validation: a tab in the payload is 400 (the spec allows only \\n)", st == 400, st)
    st, j = req("POST", "/queues/q/lease", {"lease_ms": 99}); check("validation: lease_ms 99 is 400", st == 400, st)
    st, j = req("POST", "/queues/q/lease", {"lease_ms": 3600001}); check("validation: lease_ms 3,600,001 is 400", st == 400, st)
    st, j = req("POST", "/queues/a" + "b" * 64 + "/lease", {}); check("validation: a 65-byte queue name in the lease path is 400 or 404", st in (400, 404), st)

def t_routes():
    st, _ = req("GET", "/nothing"); check("routes: unknown route is 404", st == 404, st)
    st, _ = req("GET", "/queues/q/lease"); check("routes: GET on a POST route is 405", st == 405, st)
    st, _ = req("PUT", "/jobs"); check("routes: PUT /jobs is 405", st == 405, st)
    st, _ = req("GET", "/jobs/j_999999"); check("routes: missing job is 404", st == 404, st)
    st, _ = req("POST", "/jobs/j_999999/ack"); check("routes: ack on a missing job is 404", st == 404, st)
    st, _ = req("DELETE", "/jobs/j_999999"); check("routes: delete on a missing job is 404", st == 404, st)
    st, _ = req("GET", "/jobs/../health"); check("routes: a dotted path is not a job", st in (400, 404), st)

def t_lifecycle():
    st, a = create(queue="life", payload="first"); check("life: create is 201", st == 201, st)
    if st != 201: return
    for k in ("id", "queue", "state", "payload", "attempts", "max_attempts", "created_at", "updated_at"):
        check(f"life: created job has {k}", k in a, list(a))
    check("life: created job is queued with 0 attempts", a.get("state") == "queued" and a.get("attempts") == 0, a)
    check("life: id has the j_ shape", str(a.get("id", "")).startswith("j_"), a.get("id"))
    check("life: created job carries no worker or lease_until", "worker" not in a and "lease_until" not in a, list(a))
    st, b = create(queue="life", payload="second")
    st, g = req("GET", f"/jobs/{a['id']}"); check("life: get returns the job", st == 200 and g.get("payload") == "first", (st, g))
    st, l1 = req("POST", "/queues/life/lease", {"lease_ms": 60000}, token="w1")
    check("life: lease hands out the oldest queued job", st == 200 and l1.get("id") == a["id"], (st, l1))
    if st == 200:
        check("life: leased job is leased to the caller with attempts 1", l1.get("state") == "leased" and l1.get("worker") == "w1" and l1.get("attempts") == 1 and "lease_until" in l1, l1)
    st, l2 = req("POST", "/queues/life/lease", {"lease_ms": 60000}, token="w2"); check("life: second lease hands out the second job", st == 200 and l2.get("id") == b["id"], (st, l2))
    st, l3 = req("POST", "/queues/life/lease", {"lease_ms": 60000}, token="w3"); check("life: lease on an empty queue is 204", st == 204, st)
    st, _ = req("POST", f"/jobs/{a['id']}/ack", token="w2"); check("life: ack by another worker is 409", st == 409, st)
    st, _ = req("DELETE", f"/jobs/{a['id']}"); check("life: delete of a leased job is 409", st == 409, st)
    st, d = req("POST", f"/jobs/{a['id']}/ack", token="w1"); check("life: ack by the holder is 200 done", st == 200 and d.get("state") == "done", (st, d))
    st, _ = req("POST", f"/jobs/{a['id']}/ack", token="w1"); check("life: a second ack is 409", st == 409, st)
    st, _ = req("POST", f"/jobs/{a['id']}/fail", {"reason": "x"}, token="w1"); check("life: fail on a done job is 409", st == 409, st)
    st, f = req("POST", f"/jobs/{b['id']}/fail", {"reason": "smtp down"}, token="w2"); check("life: fail below max is 200 queued with the reason", st == 200 and f.get("state") == "queued" and f.get("reason") == "smtp down" and f.get("attempts") == 1, (st, f))
    st, _ = req("POST", f"/jobs/{b['id']}/fail", {}, token="w2"); check("life: fail without a live lease is 409 (or 400 for the body)", st in (409, 400), st)
    # drive b to dead
    for i in range(2):
        st, l = req("POST", "/queues/life/lease", {"lease_ms": 60000}, token="w9")
        if st != 200 or l.get("id") != b["id"]:
            check("life: a failed job is leased again", False, (st, l)); break
        st, f = req("POST", f"/jobs/{b['id']}/fail", {"reason": f"again {i}"}, token="w9")
    st, g = req("GET", f"/jobs/{b['id']}")
    check("life: a job failed at max_attempts is dead with attempts == max", g.get("state") == "dead" and g.get("attempts") == 3, g)
    st, l = req("POST", "/queues/life/lease", {"lease_ms": 60000}, token="w9"); check("life: a dead job is never leased", st == 204, (st, l))
    st, _ = req("DELETE", f"/jobs/{a['id']}"); check("life: delete of a done job is 204", st == 204, st)
    st, _ = req("GET", f"/jobs/{a['id']}"); check("life: a deleted job is 404", st == 404, st)
    st, _ = req("DELETE", f"/jobs/{b['id']}"); check("life: delete of a dead job is 204", st == 204, st)
    st, c = create(queue="life", payload="third"); st, _ = req("DELETE", f"/jobs/{c['id']}"); check("life: delete of a queued job is 204", st == 204, st)

def t_listing():
    ids = [create(queue="lst", payload=f"n{i}")[1]["id"] for i in range(5)]
    req("POST", "/queues/lst/lease", {"lease_ms": 60000}, token="w1")
    st, j = req("GET", "/jobs?queue=lst&state=queued"); check("list: queue+state filter", st == 200 and len(j.get("jobs", [])) == 4 and all(x["state"] == "queued" for x in j["jobs"]), (st, j if st != 200 else len(j.get("jobs", []))))
    st, j = req("GET", "/jobs?state=leased"); check("list: state filter alone", st == 200 and any(x["id"] == ids[0] for x in j.get("jobs", [])), st)
    st, j = req("GET", "/jobs?queue=lst"); n = [x["id"] for x in j.get("jobs", [])]
    check("list: ordered by id", n == sorted(n, key=lambda s: int(s.split("_")[1])), n)
    st, j = req("GET", "/jobs?state=nonsense"); check("list: a bad state filter is 400", st == 400, st)
    for i in range(110): create(queue="many", payload="m")
    st, j = req("GET", "/jobs?queue=many"); check("list: at most 100 jobs", st == 200 and len(j.get("jobs", [])) == 100, (st, len(j.get("jobs", [])) if st == 200 else j))

def t_roundtrip():
    for name, p in [("unicode", "héllo wörld ✓ 日本"), ("quotes and backslashes", 'a"b\\c'), ("newline", "x\ny"), ("empty payload", "")]:
        st, j = create(queue="rt", payload=p)
        if st != 201: check(f"roundtrip: {name} created", False, st); continue
        st, g = req("GET", f"/jobs/{j['id']}"); check(f"roundtrip: {name}", g.get("payload") == p, repr(g.get("payload"))[:60])
    st, j = create(queue="rt", payload="p", token="wörker"); check("roundtrip: a non-ASCII token is handled (201, 400, or 401), not a crash", st in (201, 400, 401), st)

def t_expiry():
    st, a = create(queue="exp", payload="e")
    st, l = req("POST", "/queues/exp/lease", {"lease_ms": 100}, token="w1"); check("expiry: lease with 100 ms", st == 200, st)
    time.sleep(0.3)
    st, l2 = req("POST", "/queues/exp/lease", {"lease_ms": 60000}, token="w2")
    check("expiry: a run-out lease is handed out again with attempts 2", st == 200 and l2.get("id") == a["id"] and l2.get("attempts") == 2 and l2.get("worker") == "w2", (st, l2))
    st, _ = req("POST", f"/jobs/{a['id']}/ack", token="w1"); check("expiry: the old holder's ack is 409", st == 409, st)
    st, g = req("GET", f"/jobs/{a['id']}"); check("expiry: the job still belongs to the new holder after the stale ack", g.get("worker") == "w2" and g.get("state") == "leased", g)
    st, _ = req("POST", f"/jobs/{a['id']}/ack", token="w2"); check("expiry: the new holder acks", st == 200, st)
    st, b = create(queue="exp2", payload="last", max_attempts=1)
    st, l = req("POST", "/queues/exp2/lease", {"lease_ms": 100}, token="w1"); time.sleep(0.3)
    st, g = req("GET", f"/jobs/{b['id']}"); check("expiry: a lease that runs out on the last attempt is dead at the next look", g.get("state") == "dead", g)
    st, l = req("POST", "/queues/exp2/lease", {"lease_ms": 100}, token="w1"); check("expiry: nothing to lease after that", st == 204, st)

def t_race():
    st, a = create(queue="race", payload="one")
    results = []; lock = threading.Lock()
    def go(i):
        try: st, j = req("POST", "/queues/race/lease", {"lease_ms": 60000}, token=f"r{i}")
        except Exception as e: st, j = -1, str(e)
        with lock: results.append((st, j))
    ths = [threading.Thread(target=go, args=(i,)) for i in range(32)]
    [t.start() for t in ths]; [t.join() for t in ths]
    wins = [r for r in results if r[0] == 200]; nones = [r for r in results if r[0] == 204]; errs = [r for r in results if r[0] not in (200, 204)]
    check("race: exactly one of 32 racing workers holds the job", len(wins) == 1, f"{len(wins)} wins, {len(nones)} 204s, {len(errs)} other: {errs[:3]}")
    check("race: no racer got an error", len(errs) == 0, errs[:3])
    # acks race: 32 workers ack the same job, only the holder may succeed
    holder = wins[0][1]["worker"] if wins else None
    results = []
    def ack(i):
        try: st, j = req("POST", f"/jobs/{a['id']}/ack", token=f"r{i}")
        except Exception as e: st, j = -1, str(e)
        with lock: results.append((st, f"r{i}"))
    ths = [threading.Thread(target=ack, args=(i,)) for i in range(32)]
    [t.start() for t in ths]; [t.join() for t in ths]
    oks = [r for r in results if r[0] == 200]
    check("race: exactly one ack succeeds and it is the holder's", len(oks) == 1 and oks[0][1] == holder, (oks, holder))

def t_load():
    errs = []; lock = threading.Lock(); done = [0]
    def worker(i):
        try:
            for k in range(25):
                st, j = create(queue=f"load{i % 4}", payload=f"{i}-{k}")
                if st != 201: raise RuntimeError(f"create {st}")
                st, l = req("POST", f"/queues/load{i % 4}/lease", {"lease_ms": 60000}, token=f"L{i}")
                if st == 200:
                    st2, _ = req("POST", f"/jobs/{l['id']}/ack", token=f"L{i}")
                    if st2 != 200: raise RuntimeError(f"ack {st2} on {l['id']}")
                    with lock: done[0] += 1
                elif st != 204: raise RuntimeError(f"lease {st}")
        except Exception as e:
            with lock: errs.append(str(e))
    ths = [threading.Thread(target=worker, args=(i,)) for i in range(8)]
    t0 = time.time(); [t.start() for t in ths]; [t.join() for t in ths]; dt = time.time() - t0
    check("load: 8 workers x 25 create/lease/ack with no error", not errs, errs[:3])
    st, h = req("GET", "/health", token=None)
    st, j = req("GET", "/jobs?state=leased")
    check("load: no job left leased by a worker that acked", st == 200 and not [x for x in j.get("jobs", []) if x["queue"].startswith("load")], [x["id"] for x in j.get("jobs", []) if x["queue"].startswith("load")][:5])
    print(f"     load: {done[0]} acks in {dt:.1f}s ({done[0]/dt:.0f}/s), health {h}")

def t_idle(server):
    socks = []
    try:
        for i in range(1200):
            s = socket.create_connection(("127.0.0.1", server.port), timeout=5); socks.append(s)
    except Exception as e:
        check("idle: 1,200 quiet connections can be opened", False, f"opened {len(socks)}: {e}")
    else:
        check("idle: 1,200 quiet connections can be opened", True)
    t0 = time.time()
    try:
        st, j = create(queue="idle", payload="through the crowd"); dt = time.time() - t0
        check("idle: a producer is answered within 5 s while 1,200 quiet connections are open", st == 201 and dt < 5, f"{st} after {dt:.2f}s")
    except Exception as e:
        check("idle: a producer is answered within 5 s while 1,200 quiet connections are open", False, f"{e} after {time.time()-t0:.1f}s")
    # slowloris: partial headers held open
    s = socket.create_connection(("127.0.0.1", server.port)); s.sendall(b"POST /jobs HTTP/1.1\r\nhost: x\r\nauthorization: Bearer ada\r\ncontent-length: 100\r\n")
    t0 = time.time()
    try:
        st, j = create(queue="idle", payload="past a slow client"); check("idle: a slow client with half a request does not block another", st == 201 and time.time() - t0 < 5, f"{st} {time.time()-t0:.2f}s")
    except Exception as e:
        check("idle: a slow client with half a request does not block another", False, str(e))
    s.close()
    for x in socks: x.close()
    # after the crowd is gone the server still answers
    time.sleep(0.5)
    st, _ = req("GET", "/health", token=None); check("idle: the server answers after the crowd leaves", st == 200, st)
    # oversized body
    try:
        st, j = req("POST", "/jobs", raw=b"x" * (2 * 1024 * 1024)); check("idle: a 2 MiB body is refused (400 or 413) or the connection closed, not a crash", st in (400, 413), st)
    except (ConnectionResetError, BrokenPipeError, http.client.RemoteDisconnected) as e:
        check("idle: a 2 MiB body is refused (400 or 413) or the connection closed, not a crash", True)
    except Exception as e:
        check("idle: a 2 MiB body is refused (400 or 413) or the connection closed, not a crash", False, str(e))
    st, _ = req("GET", "/health", token=None); check("idle: the server answers after the oversized body", st == 200, st)

def t_durability(server):
    ids = [create(queue="dur", payload=f"d{i}")[1]["id"] for i in range(20)]
    st, l1 = req("POST", "/queues/dur/lease", {"lease_ms": 60000}, token="hold")   # live lease across the restart
    st, l2 = req("POST", "/queues/dur/lease", {"lease_ms": 100}, token="short")    # runs out across the restart
    st, _ = req("POST", f"/jobs/{ids[5]}/ack", token="nobody")                      # 409, no change
    st, f = req("POST", "/queues/dur/lease", {"lease_ms": 60000}, token="f"); req("POST", f"/jobs/{f['id']}/fail", {"reason": "before the kill"}, token="f")
    st, _ = req("DELETE", f"/jobs/{ids[19]}")
    st, before = req("GET", "/jobs?queue=dur"); before = {j["id"]: j for j in before["jobs"]}
    server.kill()
    time.sleep(0.3)
    t0 = time.time(); took = server.start(); global PORT; PORT = server.port
    print(f"     durability: restarted in {took:.2f}s")
    st, after = req("GET", "/jobs?queue=dur"); after = {j["id"]: j for j in after.get("jobs", [])}
    check("durability: every job survives a SIGKILL", set(after) == set(before), f"missing {set(before)-set(after)} extra {set(after)-set(before)}")
    check("durability: the deleted job stays deleted", ids[19] not in after, ids[19] in after)
    if l1["id"] in after:
        check("durability: a live lease is still held by its worker after restart", after[l1["id"]]["state"] == "leased" and after[l1["id"]].get("worker") == "hold", after[l1["id"]])
    if l2["id"] in after:
        check("durability: a lease that ran out during the restart is queued (or dead) at the next look", after[l2["id"]]["state"] in ("queued", "dead"), after[l2["id"]])
    if f["id"] in after:
        check("durability: a fail before the kill is kept with its reason", after[f["id"]].get("reason") == "before the kill" and after[f["id"]]["attempts"] == 1, after[f["id"]])
    same = [i for i in before if i in after and i not in (l2["id"],) and {k: v for k, v in before[i].items() if k != "updated_at"} != {k: v for k, v in after[i].items() if k != "updated_at"}]
    check("durability: unchanged jobs are byte-for-byte the same after replay", not same, [(before[i], after[i]) for i in same[:2]])
    st, n = create(queue="dur", payload="after"); check("durability: ids continue after the restart and never repeat", st == 201 and n["id"] not in before and int(n["id"].split("_")[1]) > max(int(i.split("_")[1]) for i in before), n.get("id"))
    st, _ = req("POST", f"/jobs/{l1['id']}/ack", token="hold"); check("durability: the live lease's holder can still ack after restart", st == 200, st)

def t_kill_under_load(server):
    """A response is never sent before its record is durable: every 201 and every 200 ack answered
    before a SIGKILL must be there after the restart."""
    created = []; acked = []; lock = threading.Lock(); stop = threading.Event()
    def worker(i):
        while not stop.is_set():
            try:
                st, j = create(queue=f"kill{i % 3}", payload=f"k{i}")
                if st == 201:
                    with lock: created.append(j["id"])
                st, l = req("POST", f"/queues/kill{i % 3}/lease", {"lease_ms": 60000}, token=f"K{i}")
                if st == 200:
                    st2, _ = req("POST", f"/jobs/{l['id']}/ack", token=f"K{i}")
                    if st2 == 200:
                        with lock: acked.append(l["id"])
            except Exception:
                return
    ths = [threading.Thread(target=worker, args=(i,)) for i in range(6)]
    [t.start() for t in ths]; time.sleep(1.5)
    server.kill(); stop.set(); [t.join(timeout=15) for t in ths]
    with lock: c, a = list(created), list(acked)
    time.sleep(0.3); took = server.start(); global PORT; PORT = server.port
    print(f"     kill: {len(c)} created, {len(a)} acked before the kill; restarted in {took:.2f}s")
    present = {}
    for q in range(3):
        st, j = req("GET", f"/jobs?queue=kill{q}")
        for x in j.get("jobs", []): present[x["id"]] = x
    # the listing caps at 100 a query, so fetch the rest one by one
    missing = []; notdone = []
    for i in c:
        if i in present: continue
        st, g = req("GET", f"/jobs/{i}")
        if st != 200: missing.append(i)
        else: present[i] = g
    for i in a:
        if i in present and present[i]["state"] != "done": notdone.append((i, present[i]["state"]))
    check("kill: every job answered 201 before the kill is present after restart", not missing, f"{len(missing)} missing of {len(c)}: {missing[:5]}")
    check("kill: every job acked 200 before the kill is done after restart", not notdone, f"{len(notdone)} of {len(a)}: {notdone[:5]}")
    st, n = create(queue="kill0", payload="after"); check("kill: the service takes writes after the kill", st == 201, st)

def t_torn(server):
    ids = [create(queue="torn", payload=f"t{i}")[1]["id"] for i in range(5)]
    server.stop(); time.sleep(0.3)
    files = [os.path.join(dp, f) for dp, _, fs in os.walk(server.dir) for f in fs]
    files = [f for f in files if os.path.isfile(f)]
    if not files:
        check("torn: a log file exists in the folder", False, "no files"); server.start(); return
    log = max(files, key=os.path.getsize)
    with open(log, "ab") as fh: fh.write(b'{"id": "j_9999", "queue": "torn", "state": "qu')
    try:
        took = server.start()
        check("torn: the service starts with a torn last line", True)
    except Exception as e:
        check("torn: the service starts with a torn last line", False, str(e)); return
    global PORT; PORT = server.port
    st, after = req("GET", "/jobs?queue=torn"); got = {j["id"] for j in after.get("jobs", [])}
    check("torn: every whole record survives, the torn one is dropped", st == 200 and set(ids) <= got and "j_9999" not in got, (st, sorted(got)[:8]))
    st, n = create(queue="torn", payload="after the tear"); check("torn: writes work after the tear", st == 201, st)
    server.stop(); time.sleep(0.3); server.start(); PORT = server.port
    st, after = req("GET", "/jobs?queue=torn"); got = {j["id"] for j in after.get("jobs", [])}
    check("torn: a second restart keeps the write made after the tear", st == 200 and n.get("id") in got, sorted(got)[-3:])

def t_health():
    st, h = req("GET", "/health", token=None)
    check("health: shape", st == 200 and all(k in h for k in ("queued", "leased", "done", "dead", "uptime_ms")), h)
    st, j = req("GET", "/jobs?state=dead");
    check("health: dead count is at least the dead jobs the listing shows (capped at 100)", h.get("dead", -1) >= min(len(j.get("jobs", [])), 100), (h.get("dead"), len(j.get("jobs", []))))

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--serve", required=True); ap.add_argument("--cwd", default=None); ap.add_argument("--only", default=None)
    ap.add_argument("--keep", action="store_true")
    a = ap.parse_args()
    base = tempfile.mkdtemp(prefix="defects-"); d = os.path.join(base, "dir"); os.mkdir(d)
    server = Server(a.serve, a.cwd, d)
    global PORT
    took = server.start(); PORT = server.port
    print(f"server up in {took:.2f}s on {PORT}, dir {d}")
    tests = [("auth", t_auth), ("validation", t_validation), ("routes", t_routes), ("lifecycle", t_lifecycle), ("listing", t_listing),
             ("roundtrip", t_roundtrip), ("expiry", t_expiry), ("race", t_race), ("load", t_load), ("idle", lambda: t_idle(server)),
             ("durability", lambda: t_durability(server)), ("kill", lambda: t_kill_under_load(server)), ("torn", lambda: t_torn(server)), ("health", t_health)]
    for name, fn in tests:
        if a.only and name != a.only: continue
        if server.proc.poll() is not None:
            check(f"{name}: the server is still alive", False, f"exited {server.proc.returncode}");
            try: server.start(); PORT = server.port
            except Exception as e: print("cannot restart:", e); break
        try: fn()
        except Exception as e:
            check(f"{name}: ran to the end", False, f"{type(e).__name__}: {e}")
    alive = server.proc.poll() is None
    check("end: the server is still alive", alive, f"exit {server.proc.returncode}")
    server.stop()
    print(f"\n{len(PASSES)} passed, {len(DEFECTS)} defects")
    for n, dd in DEFECTS: print(f"  - {n}" + (f": {dd}" if dd else ""))
    if not a.keep: shutil.rmtree(base, ignore_errors=True)
    else: print("kept", base)

if __name__ == "__main__": main()
