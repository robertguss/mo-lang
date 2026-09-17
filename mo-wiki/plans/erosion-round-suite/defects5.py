#!/usr/bin/env python3
"""The erosion round's sixth hidden suite, for change 5 (mo-wiki/spec/programs/01f-job-queue-change-5.md).
Written by Fable on 16 Sep 2026 after the four maintainers' sessions started (21:18); never shown to a worker.

Categories: `handoff` (the route's rule: from the holder, a stranger, after expiry, to oneself, in a chain, on a job
not leased, a bad `to`, an unknown job; the old worker 409 and the new worker 200 after), `handoffkept` (a handoff
across a stop and start, across a chaos restart, across a compaction: the same worker and lease_until), `rename`
(jobs in every state with keys moved whole, the lease in flight untouched and acked after, the listings, /queues,
the key lookup, a fresh queue under the old name, 404 on an empty name, 409 on an existing target and the same
name, 400 on a bad one), `renamerecord` (the rename record in the replay's order, compact with two renames, the
archive under an old name, verify on a bad rename record), `renamekill` (a rename under a load of keyed creates,
leases, acks, and handoffs, the service killed as it lands, the folder reopened: every job in exactly one queue,
every key once per queue, every acknowledged write present, no job with two workers).

usage: defects5.py --serve '<cmd> serve {dir} --port {port}' --verify '<cmd> verify {dir}' --compact '<cmd> compact {dir}'
                   [--cwd DIR] [--only NAME]
The harness (Server, req, create, lease, get, health, check) is round 8's, imported from control-run-8-suite.
"""
import argparse, json, os, re, shutil, signal, subprocess, sys, tempfile, threading, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "control-run-8-suite"))
import defects as d8
from defects import Server, req, create, lease, get, health, check

def run(cmd, cwd, timeout=60):
    p = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    return p.returncode, (p.stdout + p.stderr).strip()
def safe(method, path, body=None, token="ada", timeout=5.0):
    try: return req(method, path, body, token=token, timeout=timeout)
    except Exception as e: return -1, type(e).__name__
def drain(limit=1500, timeout=180):
    t0 = time.time()
    while time.time() - t0 < timeout:
        n = int(subprocess.run("netstat -an | grep -c TIME_WAIT", shell=True, capture_output=True, text=True).stdout.strip() or 0)
        if n < limit: return
        time.sleep(3)
def fresh_dir(prefix):
    base = tempfile.mkdtemp(prefix=prefix); d = os.path.join(base, "dir"); os.mkdir(d); return base, d
def serve_with(a, d, opts=""):
    s = Server(a.serve + opts, a.cwd, d); took = s.start(); d8.PORT = s.port; return s, took
def jobs_of(j): return j if isinstance(j, list) else (j.get("jobs") if isinstance(j, dict) else None)
def keyed(queue, key, payload="p", max_tries=2, token="ada", **more): return create(queue=queue, payload=payload, max_tries=max_tries, token=token, key=key, **more)
def handoff(jid, to, token): return safe("POST", f"/jobs/{jid}/handoff", {"to": to}, token=token)
def rename(name, to, token="ada"): return safe("POST", f"/queues/{name}/rename", {"to": to}, token=token)
def ack(jid, token): return safe("POST", f"/jobs/{jid}/ack", token=token)
def fail(jid, token): return safe("POST", f"/jobs/{jid}/fail", {"reason": "x"}, token=token)
def looked():
    """a look: a lease request on a queue with nothing in it"""
    return lease("nothing-here", ms=1000, token="w-look")
def queues_named():
    st, q = safe("GET", "/queues")
    if st != 200 or not isinstance(q, dict): return None
    return {x.get("name"): x for x in q.get("queues", [])}
def leased_job(queue, token, ms=60000):
    st, j = create(queue=queue, payload="p", max_tries=3); st, l = lease(queue, ms=ms, token=token)
    return l if st == 200 and isinstance(l, dict) else None

# ---------------------------------------------------------------- the handoff
def t_handoff(a):
    base, d = fresh_dir("handoff5-"); s, _ = serve_with(a, d)
    j = leased_job("h", "alice")
    if not j: check("handoff: a job leased to set up", False, "no lease"); s.stop(); return
    before = (j.get("lease_until"), j.get("tries"))
    st, b = handoff(j["id"], "bob", "carol"); check("handoff: a stranger is 409", st == 409, (st, b))
    st, b = handoff(j["id"], "bob", "alice"); check("handoff: the holder hands the job to bob, 200", st == 200 and isinstance(b, dict), (st, b))
    if isinstance(b, dict):
        check("handoff: the job is leased to bob", b.get("state") == "leased" and b.get("worker") == "bob", b)
        check("handoff: lease_until and tries unchanged", (b.get("lease_until"), b.get("tries")) == before, (before, b.get("lease_until"), b.get("tries")))
        check("handoff: the response carries the id and the queue", b.get("id") == j["id"] and b.get("queue") == "h", b)
    st, b = ack(j["id"], "alice"); check("handoff: alice's ack is 409 after", st == 409, (st, b))
    st, b = fail(j["id"], "alice"); check("handoff: alice's fail is 409 after", st == 409, (st, b))
    st, b = handoff(j["id"], "dave", "alice"); check("handoff: alice's second handoff is 409", st == 409, (st, b))
    st, g = get(j["id"]); check("handoff: the read shows bob as the worker", st == 200 and isinstance(g, dict) and g.get("worker") == "bob", g)
    st, b = handoff(j["id"], "bob", "bob"); check("handoff: to oneself is 200 and changes nothing", st == 200 and isinstance(b, dict) and b.get("worker") == "bob" and (b.get("lease_until"), b.get("tries")) == before, (st, b))
    st, b = handoff(j["id"], "carol", "bob"); check("handoff: bob hands it on to carol (a chain), 200", st == 200 and isinstance(b, dict) and b.get("worker") == "carol", (st, b))
    st, b = ack(j["id"], "bob"); check("handoff: bob's ack is 409 after the chain", st == 409, (st, b))
    st, b = ack(j["id"], "carol"); check("handoff: carol's ack is 200", st == 200 and isinstance(b, dict) and b.get("state") == "done", (st, b))
    st, b = handoff(j["id"], "dave", "carol"); check("handoff: a done job is 409", st == 409, (st, b))
    # the new worker's fail
    j2 = leased_job("h", "alice"); handoff(j2["id"], "bob", "alice")
    st, b = fail(j2["id"], "bob"); check("handoff: the new worker's fail is 200", st == 200 and isinstance(b, dict) and b.get("state") in ("queued", "scheduled", "dead"), (st, b))
    # on a queued job, nobody holds a lease
    st, q = create(queue="h2", payload="p", max_tries=3)
    st, b = handoff(q["id"], "bob", "ada"); check("handoff: on a queued job is 409", st == 409, (st, b))
    # a bad `to`
    j3 = leased_job("h", "alice")
    for body in ({"to": ""}, {"to": "has space"}, {}, {"to": 5}, {"to": "x" * 129}):
        st, b = safe("POST", f"/jobs/{j3['id']}/handoff", body, token="alice"); check(f"handoff: `{json.dumps(body)[:24]}` is 400", st == 400, (st, b))
    st, b = safe("POST", f"/jobs/{j3['id']}/handoff", None, token="alice"); check("handoff: no body is 400", st == 400, (st, b))
    st, g = get(j3["id"]); check("handoff: the bad requests changed nothing", st == 200 and isinstance(g, dict) and g.get("worker") == "alice", g)
    st, b = handoff("j_999999", "bob", "alice"); check("handoff: an unknown job is 404", st == 404, (st, b))
    st, b = safe("POST", f"/jobs/{j3['id']}/handoff", {"to": "bob"}, token=None); check("handoff: no token is 401", st == 401, (st, b))
    st, b = safe("GET", f"/jobs/{j3['id']}/handoff", token="alice"); check("handoff: GET on the route is 405", st == 405, (st, b))
    # after the lease ran out
    st, jj = create(queue="h3", payload="p", max_tries=3); st, l = lease("h3", ms=200, token="alice"); time.sleep(0.5); looked()
    st, b = handoff(l["id"], "bob", "alice"); check("handoff: after the lease ran out is 409", st == 409, (st, b))
    st, g = get(l["id"]); check("handoff: the run-out job is queued again, no worker", st == 200 and isinstance(g, dict) and g.get("state") == "queued" and not g.get("worker"), g)
    # a handoff counts in /health as leased still
    h = health(); check("handoff: /health still counts the job leased to alice (1)", h.get("leased", 0) == 1, h)  # amended 21:58: the category leaves one job leased, not two
    s.stop(); shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------- the handoff kept
def t_handoffkept(a):
    base, d = fresh_dir("handoffkept5-"); s, _ = serve_with(a, d)
    j = leased_job("k", "alice", ms=120000); st, b = handoff(j["id"], "bob", "alice")
    until = b.get("lease_until") if isinstance(b, dict) else None
    s.stop(); s, _ = serve_with(a, d)
    st, g = get(j["id"]); check("handoffkept: after a stop and start the job is leased to bob with the same lease_until", st == 200 and isinstance(g, dict) and g.get("worker") == "bob" and g.get("lease_until") == until, (until, g))
    st, b = ack(j["id"], "alice"); check("handoffkept: alice's ack is 409 after the restart", st == 409, (st, b))
    st, b = ack(j["id"], "bob"); check("handoffkept: bob's ack is 200 after the restart", st == 200, (st, b))
    # across a compaction
    j = leased_job("k", "alice", ms=120000); st, b = handoff(j["id"], "bob", "alice"); until = b.get("lease_until") if isinstance(b, dict) else None
    s.stop(); rc, out = run(a.compact.format(dir=d), a.cwd); check("handoffkept: compact exits 0", rc == 0, (rc, out[:120]))
    s, _ = serve_with(a, d)
    st, g = get(j["id"]); check("handoffkept: after a compaction the job is leased to bob with the same lease_until", st == 200 and isinstance(g, dict) and g.get("worker") == "bob" and g.get("lease_until") == until, (until, g))
    st, b = ack(j["id"], "bob"); check("handoffkept: bob's ack is 200 after the compaction", st == 200, (st, b))
    s.stop()
    # across a chaos restart: handoffs until the board fails, then the handed-off jobs still with their new workers
    s, _ = serve_with(a, d, " --crash-every 7 --max-restarts 100")
    h0 = health(); held = {}
    for i in range(30):
        jj = leased_job("c", f"w{i}", ms=120000)
        if not jj: continue
        st, b = handoff(jj["id"], f"x{i}", f"w{i}")
        if st == 200 and isinstance(b, dict): held[jj["id"]] = (f"x{i}", b.get("lease_until"))
        if health().get("restarts", 0) > h0.get("restarts", 0) and len(held) >= 5: break
    time.sleep(1.5)
    h = health(); check("handoffkept: the chaos switch restarted the board at least once", h.get("restarts", 0) > h0.get("restarts", 0), (h0, h))
    wrong = []
    for jid, (w, until) in held.items():
        st, g = get(jid)
        if st != 200 or not isinstance(g, dict) or g.get("worker") != w or g.get("lease_until") != until: wrong.append((jid, w, until, st, g))
    check(f"handoffkept: every handed-off job ({len(held)}) is with its new worker and lease after the chaos restarts", not wrong, wrong[:3])
    s.stop(); shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------- the rename
def setup_states(queue, tag):
    """jobs in every state in `queue`, with keys; returns id by state. Amended 21:58: each job that is leased is created
    when nothing else is queued (a lease hands out the oldest queued job), and the queued job comes last."""
    ids = {}
    st, j = keyed(queue, f"{tag}-done", max_tries=3); st, l = lease(queue, ms=60000, token="w-done"); ack(l["id"], "w-done"); ids["done"] = l["id"]
    st, j = keyed(queue, f"{tag}-dead", max_tries=1); st, l = lease(queue, ms=60000, token="w-dead"); fail(l["id"], "w-dead"); ids["dead"] = l["id"]
    st, j = keyed(queue, f"{tag}-leased", max_tries=3); st, l = lease(queue, ms=120000, token="w-hold"); ids["leased"] = l["id"]; ids["_lease"] = l
    st, j = keyed(queue, f"{tag}-scheduled", delay_ms=600000); ids["scheduled"] = j["id"]
    st, j = keyed(queue, f"{tag}-queued"); ids["queued"] = j["id"]
    return ids

def t_rename(a):
    base, d = fresh_dir("rename5-"); s, _ = serve_with(a, d, " --retain-ms 1000")
    # an archived job first, while nothing else is queued (amended 22:12: it was created after the queued job, and the lease took that one)
    st, j = keyed("old", "o-archived", max_tries=3); st, l = lease("old", ms=60000, token="w-arc"); ack(l["id"], "w-arc"); ids = {"archived": l["id"]}
    ids.update(setup_states("old", "o"))
    time.sleep(1.6); looked(); h = health()
    check("rename: an archived job to set up (the done job of the setup may be archived too)", h.get("archived", 0) >= 1, h)
    live_before = queues_named().get("old") if queues_named() else None
    st, r = rename("old", "new"); check("rename: 200 with the new name and a count", st == 200 and isinstance(r, dict) and r.get("queue") == "new" and isinstance(r.get("moved"), int), (st, r))
    if isinstance(r, dict): check("rename: `moved` counts every job, the archived ones included (6)", r.get("moved") == 6, r)
    wrong = []
    for state, jid in ids.items():
        if state.startswith("_"): continue
        st, g = get(jid)
        if st != 200 or not isinstance(g, dict) or g.get("queue") != "new": wrong.append((state, st, g if not isinstance(g, dict) else g.get("queue")))
    check("rename: every job reads as being in `new`, the archived one too", not wrong, wrong)
    q = queues_named()
    check("rename: /queues shows `new` with the counts `old` had and no `old`", q is not None and "new" in q and "old" not in q and all(q["new"].get(k) == live_before.get(k) for k in ("queued", "scheduled", "leased", "done", "dead")), (live_before, q))
    st, j = safe("GET", "/jobs?queue=old"); check("rename: the listing of `old` is empty", st == 200 and jobs_of(j) == [], j)
    st, j = safe("GET", "/jobs?queue=new"); check("rename: the listing of `new` shows the live jobs (3: the done and dead jobs aged into the archive)", st == 200 and len(jobs_of(j) or []) == 3, j)  # amended 21:58 (was 5) and 22:24 (was 4: the dead job ages too)
    st, j = safe("GET", "/jobs?queue=new&key=o-queued"); check("rename: the key lookup in `new` finds the job", st == 200 and [x.get("id") for x in (jobs_of(j) or [])] == [ids["queued"]], j)
    st, j = safe("GET", "/jobs?queue=old&key=o-queued"); check("rename: the key lookup in `old` is empty", st == 200 and jobs_of(j) == [], j)
    st, j = keyed("new", "o-queued"); check("rename: the key is used in `new` (200, the same job)", st == 200 and isinstance(j, dict) and j.get("id") == ids["queued"], (st, j))
    st, l = lease("old", ms=1000, token="w-x"); check("rename: a lease on `old` is 204", st == 204, (st, l))
    st, l = lease("new", ms=60000, token="w-y"); check("rename: a lease on `new` hands out the queued job", st == 200 and isinstance(l, dict) and l.get("id") == ids["queued"], (st, l))
    st, g = get(ids["leased"]); check("rename: the lease in flight is untouched (same worker, same lease_until)", st == 200 and isinstance(g, dict) and g.get("worker") == "w-hold" and g.get("lease_until") == ids["_lease"].get("lease_until"), (ids["_lease"].get("lease_until"), g))
    st, b = ack(ids["leased"], "w-hold"); check("rename: the holder's ack is 200 after the rename", st == 200 and isinstance(b, dict) and b.get("queue") == "new", (st, b))
    st, g = get(ids["archived"]); check("rename: the archived job reads with queue `new` and archived_at", st == 200 and isinstance(g, dict) and g.get("queue") == "new" and g.get("archived_at"), g)
    st, j = keyed("old", "o-queued"); check("rename: the key is free in `old`: a create there is 201, a fresh queue", st == 201 and isinstance(j, dict) and j.get("id") != ids["queued"], (st, j))
    q = queues_named(); check("rename: /queues now shows both", q is not None and "old" in q and "new" in q, q)
    st, r = rename("new", "old"); check("rename: renaming onto a queue with a job is 409", st == 409, (st, r))
    st, r = rename("new", "new"); check("rename: to the same name is 409", st == 409, (st, r))
    st, r = rename("nobody-here", "x"); check("rename: an empty name is 404", st == 404, (st, r))
    for body in ({"to": ""}, {"to": "bad name"}, {"to": "x" * 65}, {}, {"to": 3}):
        st, r = safe("POST", "/queues/new/rename", body, token="ada"); check(f"rename: `{json.dumps(body)[:20]}` is 400", st == 400, (st, r))
    st, r = safe("POST", "/queues/new/rename", {"to": "third"}, token=None); check("rename: no token is 401", st == 401, (st, r))
    st, r = safe("GET", "/queues/new/rename", token="ada"); check("rename: GET on the route is 405", st == 405, (st, r))
    st, r = rename("new", "third"); check("rename: renamed again, to `third`", st == 200 and isinstance(r, dict) and r.get("queue") == "third", (st, r))
    st, j = keyed("third", "o-dead"); check("rename: the dead job's key moved to `third` (200, the same job)", st == 200 and isinstance(j, dict) and j.get("id") == ids["dead"], (st, j))
    st, b = safe("DELETE", f"/jobs/{ids['dead']}"); st, j = keyed("third", "o-dead"); check("rename: after a delete the key is free in `third` (201)", st == 201, (st, j))
    st, r = rename("third", "new"); check("rename: renamed back to `new` (now empty), 200", st == 200, (st, r))
    st, j = safe("GET", "/jobs?queue=new&key=o-scheduled"); check("rename: the key lookup follows the rename back", st == 200 and [x.get("id") for x in (jobs_of(j) or [])] == [ids["scheduled"]], j)
    s.stop(); shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------- the rename record
def t_renamerecord(a):
    base, d = fresh_dir("renamerecord5-"); s, _ = serve_with(a, d, " --retain-ms 1000")
    st, first = keyed("alpha-src", "r-first"); st, r = rename("alpha-src", "beta-dst"); st, second = keyed("alpha-src", "r-second")
    st, arc = keyed("beta-dst", "r-arc", max_tries=3); st, l = lease("beta-dst", ms=60000, token="w-a"); ack(l["id"], "w-a"); time.sleep(1.6); looked()
    h = health(); check("renamerecord: a job archived under `beta-dst` to set up", h.get("archived", 0) >= 1, h)
    st, r = rename("beta-dst", "gamma-dst"); check("renamerecord: a second rename, `beta-dst` to `gamma-dst`, 200", st == 200, (st, r))
    def where():
        return {k: (get(v)[1] or {}).get("queue") if isinstance(get(v)[1], dict) else None for k, v in (("first", first["id"]), ("second", second["id"]), ("arc", l["id"]))}
    expect = {"first": "gamma-dst", "second": "alpha-src", "arc": "gamma-dst"}
    check("renamerecord: before the restart, the first job in `gamma-dst`, the second in `alpha-src`, the archived in `gamma-dst`", where() == expect, where())
    s.stop(); s, _ = serve_with(a, d, " --retain-ms 1000")
    check("renamerecord: the replay applies the rename in order (the same after a stop and start)", where() == expect, where())
    q = queues_named(); check("renamerecord: /queues after the replay: `alpha-src` and `gamma-dst`, no `beta-dst`", q is not None and set(q) == {"alpha-src", "gamma-dst"}, q)
    st, j = keyed("gamma-dst", "r-first"); check("renamerecord: the key followed two renames (200, the same job)", st == 200 and isinstance(j, dict) and j.get("id") == first["id"], (st, j))
    s.stop()
    rc, out = run(a.verify.format(dir=d), a.cwd); check("renamerecord: verify exits 0 on a log with two renames", rc == 0, (rc, out[:160]))
    rc, out = run(a.compact.format(dir=d), a.cwd); check("renamerecord: compact exits 0", rc == 0, (rc, out[:160]))
    logs = " ".join(open(os.path.join(d, f), errors="replace").read() for f in os.listdir(d) if os.path.isfile(os.path.join(d, f)))
    check("renamerecord: after compact no file names `beta-dst` (the renames folded, the archive rewritten)", "beta-dst" not in logs, [f for f in os.listdir(d)])
    s, _ = serve_with(a, d, " --retain-ms 1000")
    check("renamerecord: the same board after the compaction", where() == expect, where())
    st, g = get(l["id"]); check("renamerecord: the archived job reads with `gamma-dst` after the compaction", st == 200 and isinstance(g, dict) and g.get("queue") == "gamma-dst" and g.get("archived_at"), g)
    # a bad rename record: rename to a name that is unique in the folder's bytes, then break it on disk
    st, r = rename("gamma-dst", "delta-dst"); s.stop()
    hits = []
    for f in os.listdir(d):
        p = os.path.join(d, f)
        if not os.path.isfile(p): continue
        data = open(p, "rb").read()
        if b"delta-dst" in data: hits.append((p, data))
    check("renamerecord: the rename to `delta-dst` is on the disk (in one file)", len(hits) == 1, [h[0] for h in hits])
    if len(hits) == 1:
        p, data = hits[0]
        open(p, "wb").write(data.replace(b"delta-dst", b"delta dst"))
        rc, out = run(a.verify.format(dir=d), a.cwd); check("renamerecord: a rename record with a bad name refuses the folder, verify exits 1", rc == 1, (rc, out[:160]))
        port = d8.free_port(); cmd = a.serve.format(dir=d, port=port)
        pr = subprocess.Popen(cmd, shell=True, cwd=a.cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, preexec_fn=os.setsid)
        try: pr.wait(timeout=15); rc = pr.returncode
        except subprocess.TimeoutExpired: os.killpg(os.getpgid(pr.pid), signal.SIGKILL); pr.wait(); rc = "still serving"
        check("renamerecord: serve refuses the folder with exit 1", rc == 1, rc)
        open(p, "wb").write(data)
        rc, out = run(a.verify.format(dir=d), a.cwd); check("renamerecord: restored, verify exits 0", rc == 0, (rc, out[:160]))
    shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------- the rename under a kill
def t_renamekill(a):
    base, d = fresh_dir("renamekill5-"); s, _ = serve_with(a, d)
    stop = threading.Event(); renaming = threading.Event(); lock = threading.Lock(); created = {}; acked = set(); handed = {}; sent = [0]
    def worker(i):
        tok = f"w{i}"; n = 0
        while not stop.is_set():
            n += 1; k = f"k{i}-{n}"
            if not renaming.is_set():  # amended 21:58: no create into the old name once the rename is on its way (a fresh queue under it is by the spec)
                with lock: sent[0] += 1
                st, b = safe("POST", "/jobs", {"queue": "src", "payload": "p", "max_tries": 2, "key": k}, token=tok)
                if st == 201 and isinstance(b, dict):
                    with lock: created[b["id"]] = k
            st, b = safe("POST", "/queues/src/lease", {"lease_ms": 60000}, token=tok)
            if st == 200 and isinstance(b, dict) and b.get("id"):
                if n % 2:
                    st2, b2 = safe("POST", f"/jobs/{b['id']}/handoff", {"to": f"h{i}"}, token=tok)
                    if st2 == 200:
                        with lock: handed[b["id"]] = f"h{i}"
                else:
                    st2, _ = safe("POST", f"/jobs/{b['id']}/ack", token=tok)
                    if st2 == 200:
                        with lock: acked.add(b["id"])
    ths = [threading.Thread(target=worker, args=(i,), daemon=True) for i in range(4)]
    for t in ths: t.start()
    time.sleep(2.5)
    result = {}
    def renamer(): result["r"] = rename("src", "dst")
    renaming.set(); time.sleep(0.15)
    rt = threading.Thread(target=renamer, daemon=True); rt.start(); time.sleep(0.02); s.kill(); stop.set(); rt.join(3); time.sleep(0.3)
    drain()
    rc, out = run(a.verify.format(dir=d), a.cwd); check("renamekill: verify exits 0 after the kill", rc == 0, (rc, out[:160]))
    s, took = serve_with(a, d); h = health()
    q = queues_named() or {}
    total = sum(h.get(k, 0) for k in ("queued", "scheduled", "leased", "done", "dead", "archived"))
    check("renamekill: every created job is counted once after the reopen (a create durable but unanswered under the kill may add one)", len(created) <= total <= sent[0], (total, len(created), sent[0], h))  # amended 21:58
    check("renamekill: the jobs are in exactly one queue, `src` or `dst`", set(q) in ({"src"}, {"dst"}), (list(q), result.get("r")))
    home = "dst" if "dst" in q else "src"
    check(f"renamekill: a lease on the other name is 204 (home is `{home}`)", lease("src" if home == "dst" else "dst", ms=1000, token="w-x")[0] == 204, home)
    missing, moved, twice, two_workers = [], [], [], []
    sample = list(created.items())[::max(1, len(created) // 150)]
    for jid, k in sample:
        st, j = safe("GET", f"/jobs/{jid}")
        if st != 200 or not isinstance(j, dict): missing.append((jid, st)); continue
        if j.get("queue") != home: moved.append((jid, j.get("queue")))
        if j.get("state") == "leased" and not isinstance(j.get("worker"), str): two_workers.append((jid, j.get("worker")))
        st2, j2 = safe("POST", "/jobs", {"queue": home, "payload": "p", "max_tries": 2, "key": k})
        if st2 != 200 or not isinstance(j2, dict) or j2.get("id") != jid: twice.append((jid, k, st2))
    check(f"renamekill: every sampled job reads 200 ({len(sample)} sampled)", not missing, missing[:3])
    check("renamekill: every sampled job is in the home queue (all moved or none)", not moved, moved[:3])
    check("renamekill: every sampled key is used once in the home queue", not twice, twice[:3])
    check("renamekill: no leased job carries other than one worker", not two_workers, two_workers[:3])
    lost = [jid for jid in acked if (safe("GET", f"/jobs/{jid}")[1] or {}).get("state") != "done"]
    check(f"renamekill: every acknowledged ack is present ({len(acked)} acked)", not lost, lost[:3])
    wrong = [(jid, w) for jid, w in list(handed.items())[:100] if (safe("GET", f"/jobs/{jid}")[1] or {}).get("worker") != w]
    check(f"renamekill: every acknowledged handoff is present ({len(handed)} handed off)", not wrong, wrong[:3])
    s.stop(); shutil.rmtree(base, ignore_errors=True)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--serve", required=True); ap.add_argument("--verify", required=True); ap.add_argument("--compact", required=True)
    ap.add_argument("--cwd", default=None); ap.add_argument("--only", default=None)
    a = ap.parse_args()
    for name, fn in (("handoff", t_handoff), ("handoffkept", t_handoffkept), ("rename", t_rename), ("renamerecord", t_renamerecord), ("renamekill", t_renamekill)):
        if a.only and name != a.only: continue
        try: fn(a)
        except Exception as e: check(f"{name}: ran to the end", False, f"{type(e).__name__}: {e}")
        subprocess.run("pkill -f 'serve /var/folders'", shell=True, capture_output=True)
    print(f"\n{len(d8.PASSES)} passed, {len(d8.DEFECTS)} defects")
    for name, detail in d8.DEFECTS: print(f"  - {name}: {str(detail)[:300]}")

if __name__ == "__main__": main()
