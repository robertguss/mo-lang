#!/usr/bin/env python3
"""The erosion round's seventh hidden suite, for change 6 (mo-wiki/spec/programs/01g-job-queue-change-6.md).
Written by Fable on 18 Sep 2026 before the four maintainers' sessions started; never shown to a worker.

Categories: `prune` (the route's rule: the older archived jobs gone and 404, the younger kept, a live job never
touched, the counts, the key freed for a pruned job and kept for an archived one, 400 on a bad age, no token 401,
a prune that removes nothing, the offline `jobq prune`, /archive's shape, /archive/prune's method), `retention`
(the background prune under --retention: an archived job gone within the minute, a live one kept),
`prunerecord` (the record in the replay's order: an archive record after the cutoff stays and one before is gone,
the same after a stop and start, after compact no byte of a pruned job remains and verify exits 0, a broken prune
record refuses the folder), `prunekill` (a prune under a load of creates, leases and acks with a small retain_ms,
the service killed as it lands: all the old archived jobs gone or all present, every acked write present, the
keys of the gone ones free), `renamerule` (the corrected rule: a job created into the old name after a rename
stays there through an archive, a stop and start, and a compaction), `sequence` (the spec's sequence on a fresh
folder, then a kill right after the reopen), `bench` (the command runs and prints its numbers).

usage: defects6.py --serve '<cmd> serve {dir} --port {port}' --verify '<cmd> verify {dir}' --compact '<cmd> compact {dir}'
                   --prune '<cmd> prune {dir} --older-than-ms {ms}' --bench '<cmd> bench {dir} --jobs {jobs} --workers {workers}'
                   [--cwd DIR] [--only NAME]
The harness (Server, req, create, lease, get, health, check) is round 8's, imported from control-run-8-suite.
"""
import argparse, json, os, re, shutil, signal, subprocess, sys, tempfile, threading, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "control-run-8-suite"))
import defects as d8
from defects import Server, req, create, lease, get, health, check

def run(cmd, cwd, timeout=120):
    try:
        p = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout + p.stderr).strip()
    except subprocess.TimeoutExpired:
        return "timeout", ""
def safe(method, path, body=None, token="ada", timeout=5.0):
    try: return req(method, path, body, token=token, timeout=timeout)
    except Exception as e: return -1, type(e).__name__
def drain(limit=1500, timeout=180):
    t0 = time.time()
    while time.time() - t0 < timeout:
        n = int(subprocess.run("ss -tan | grep -c TIME-WAIT", shell=True, capture_output=True, text=True).stdout.strip() or 0)
        if n < limit: return
        time.sleep(3)
def fresh_dir(prefix):
    base = tempfile.mkdtemp(prefix=prefix); d = os.path.join(base, "dir"); os.mkdir(d); return base, d
def serve_with(a, d, opts=""):
    s = Server(a.serve + opts, a.cwd, d); took = s.start(); d8.PORT = s.port; return s, took
def keyed(queue, key, payload="p", max_tries=2, token="ada"): return create(queue=queue, payload=payload, max_tries=max_tries, token=token, key=key)
def ack(jid, token): return safe("POST", f"/jobs/{jid}/ack", token=token)
def rename(name, to, token="ada"): return safe("POST", f"/queues/{name}/rename", {"to": to}, token=token)
def prune(ms, token="ada"): return safe("POST", "/archive/prune", {"older_than_ms": ms}, token=token)
def archive(): return safe("GET", "/archive")
def looked():
    """a look: a lease request on a queue with nothing in it"""
    return lease("nothing-here", ms=1000, token="w-look")
def done_job(queue, key, token="w-d", payload="p"):
    """a job created, leased, and acked, so that it is done and will archive after retain_ms"""
    st, j = keyed(queue, key, payload=payload, max_tries=3)
    if st != 201 or not isinstance(j, dict): return None
    st, l = lease(queue, ms=60000, token=token)
    if st != 200 or not isinstance(l, dict) or l.get("id") != j["id"]: return None
    st, b = ack(j["id"], token)
    return j["id"] if st == 200 else None
def folder_bytes(d):
    return b"".join(open(os.path.join(d, f), "rb").read() for f in sorted(os.listdir(d)) if os.path.isfile(os.path.join(d, f)))
def folder_size(d):
    return sum(os.path.getsize(os.path.join(d, f)) for f in os.listdir(d) if os.path.isfile(os.path.join(d, f)))
def state_of(jid):
    st, j = safe("GET", f"/jobs/{jid}")
    return (st, j.get("state") if isinstance(j, dict) else None, j.get("queue") if isinstance(j, dict) else None)
def wait_archived(n, tries=20):
    for _ in range(tries):
        looked(); h = health()
        if h.get("archived", 0) >= n: return h
        time.sleep(0.3)
    return health()

# ---------------------------------------------------------------- the prune
def t_prune(a):
    base, d = fresh_dir("prune6-"); s, _ = serve_with(a, d, " --retain-ms 500")
    old = [done_job("p", f"old-{i}", payload=f"payload-old-{i}") for i in range(3)]
    time.sleep(0.9); h = wait_archived(3)
    check("prune: three done jobs archived to set up", h.get("archived", 0) == 3 and all(old), h)
    time.sleep(2.5)  # the old ones are now at least 2.5 s archived
    young = [done_job("p", f"young-{i}", payload=f"payload-young-{i}") for i in range(2)]
    time.sleep(0.9); h = wait_archived(5)
    check("prune: two younger done jobs archived (5 archived)", h.get("archived", 0) == 5 and all(young), h)
    st, live = keyed("p", "live-1", max_tries=3); st, l = lease("p", ms=60000, token="w-l")
    st, ar = archive()
    check("prune: GET /archive shows 5 archived, an oldest_archived_at, and bytes", st == 200 and isinstance(ar, dict) and ar.get("archived") == 5 and isinstance(ar.get("oldest_archived_at"), str) and isinstance(ar.get("bytes"), int), (st, ar))
    for body in ({"older_than_ms": 999}, {"older_than_ms": "2000"}, {"older_than_ms": -5}, {}, {"older_than_ms": 1.5}):
        st, b = safe("POST", "/archive/prune", body, token="ada"); check(f"prune: `{json.dumps(body)[:26]}` is 400", st == 400, (st, b))
    st, b = safe("POST", "/archive/prune", None, token="ada"); check("prune: no body is 400", st == 400, (st, b))
    st, b = safe("POST", "/archive/prune", {"older_than_ms": 2000}, token=None); check("prune: no token is 401", st == 401, (st, b))
    st, b = safe("GET", "/archive/prune", token="ada"); check("prune: GET on the route is 405", st == 405, (st, b))
    st, b = safe("POST", "/archive", {"older_than_ms": 2000}, token="ada"); check("prune: POST /archive is 405", st == 405, (st, b))
    h = health(); check("prune: the bad requests removed nothing (5 archived)", h.get("archived", 0) == 5, h)
    st, r = prune(2000)
    check("prune: an age of 2 s removes the three old ones, keeps the two young, 200 {pruned 3, remaining 2}", st == 200 and isinstance(r, dict) and r.get("pruned") == 3 and r.get("remaining") == 2, (st, r))
    gone = [jid for jid in old if safe("GET", f"/jobs/{jid}")[0] != 404]
    check("prune: each pruned job reads 404", not gone, gone)
    kept = [jid for jid in young if state_of(jid)[0] != 200]
    check("prune: each young archived job still reads 200", not kept, kept)
    st, g = get(l["id"]); check("prune: the live leased job is untouched", st == 200 and isinstance(g, dict) and g.get("state") == "leased", (st, g))
    h = health(); check("prune: /health counts 2 archived after", h.get("archived", 0) == 2, h)
    st, ar = archive(); check("prune: /archive counts 2 after", st == 200 and isinstance(ar, dict) and ar.get("archived") == 2, ar)
    st, j = keyed("p", "old-0"); check("prune: the pruned job's key is free (201, a new job)", st == 201 and isinstance(j, dict) and j.get("id") not in old, (st, j))
    st, j = keyed("p", "young-0"); check("prune: a kept archived job's key is still used (200, the same job)", st == 200 and isinstance(j, dict) and j.get("id") == young[0], (st, j))
    st, listing = safe("GET", "/jobs?queue=p"); items = listing if isinstance(listing, list) else (listing.get("jobs") if isinstance(listing, dict) else None)
    if isinstance(items, list):
        ids = {x.get("id") for x in items if isinstance(x, dict)}
        check("prune: no pruned job in the listing", not (ids & set(old)), ids & set(old))
    size0 = folder_size(d)
    st, r = prune(3600000)
    check("prune: an age nothing meets is 200 {pruned 0, remaining 2}", st == 200 and isinstance(r, dict) and r.get("pruned") == 0 and r.get("remaining") == 2, (st, r))
    check("prune: a prune that removes nothing writes nothing (the folder's size unchanged)", folder_size(d) == size0, (size0, folder_size(d)))
    # the live job older than any age is never pruned
    time.sleep(1.2)
    st, r = prune(1000); check("prune: an age every archived job meets removes the two young ones", st == 200 and isinstance(r, dict) and r.get("pruned") == 2 and r.get("remaining") == 0, (st, r))
    st, g = get(l["id"]); check("prune: the live leased job, older than the age, is still there", st == 200 and isinstance(g, dict) and g.get("state") == "leased", (st, g))
    st, ar = archive(); check("prune: /archive with nothing archived: 0 and oldest_archived_at null", st == 200 and isinstance(ar, dict) and ar.get("archived") == 0 and ar.get("oldest_archived_at") is None, ar)
    s.stop()
    # offline
    s, _ = serve_with(a, d, " --retain-ms 500")
    ids = [done_job("q", f"off-{i}") for i in range(4)]; time.sleep(0.9); wait_archived(4); time.sleep(1.5); s.stop()
    rc, out = run(a.prune.format(dir=d, ms=1000), a.cwd)
    check("prune: `jobq prune` offline exits 0 and prints the counts (4 and 0)", rc == 0 and re.search(r"\b4\b", out) is not None and re.search(r"\b0\b", out) is not None, (rc, out[:160]))
    s, _ = serve_with(a, d, " --retain-ms 500")
    h = health(); check("prune: after the offline prune and a start, 0 archived", h.get("archived", 0) == 0, h)
    gone = [jid for jid in ids if jid and safe("GET", f"/jobs/{jid}")[0] != 404]; check("prune: the offline-pruned jobs read 404", not gone, gone)
    s.stop(); shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------- the background prune
def t_retention(a):
    base, d = fresh_dir("retention6-"); s, _ = serve_with(a, d, " --retain-ms 500 --retention 1500")
    jid = done_job("r", "r-1"); time.sleep(0.9); h = wait_archived(1)
    check("retention: the job archived to set up", h.get("archived", 0) == 1 and jid is not None, h)
    st, live = keyed("r", "r-live", max_tries=3)
    t0 = time.time(); gone = False
    while time.time() - t0 < 75:
        looked()
        if safe("GET", f"/jobs/{jid}")[0] == 404: gone = True; break
        time.sleep(2)
    check("retention: the archived job is gone within the minute under --retention 1500", gone, f"after {time.time() - t0:.0f} s: {state_of(jid)}")
    st, g = get(live["id"]); check("retention: the live job is kept", st == 200 and isinstance(g, dict) and g.get("state") == "queued", (st, g))
    h = health(); check("retention: /health counts 0 archived", h.get("archived", 0) == 0, h)
    s.stop(); s, _ = serve_with(a, d, " --retain-ms 500")
    check("retention: the background prune is durable (404 after a stop and start)", safe("GET", f"/jobs/{jid}")[0] == 404, state_of(jid))
    s.stop(); shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------- the prune record
def t_prunerecord(a):
    base, d = fresh_dir("prunerecord6-"); s, _ = serve_with(a, d, " --retain-ms 500")
    before = [done_job("pr", f"b-{i}", payload=f"UNIQUE-BEFORE-{i}-zq") for i in range(2)]; time.sleep(0.9); wait_archived(2); time.sleep(1.6)
    st, r = prune(1000); check("prunerecord: the two archived before the prune are pruned", st == 200 and isinstance(r, dict) and r.get("pruned") == 2, (st, r))
    after = [done_job("pr", f"a-{i}", payload=f"UNIQUE-AFTER-{i}-zq") for i in range(2)]; time.sleep(0.9); h = wait_archived(2)
    check("prunerecord: two archived after the prune record", h.get("archived", 0) == 2, h)
    def view(): return ([safe("GET", f"/jobs/{j}")[0] for j in before], [safe("GET", f"/jobs/{j}")[0] for j in after])
    check("prunerecord: before the restart: the pruned read 404, the later 200", view() == ([404, 404], [200, 200]), view())
    s.stop(); s, _ = serve_with(a, d, " --retain-ms 500")
    check("prunerecord: the replay applies the prune in order (the same after a stop and start)", view() == ([404, 404], [200, 200]), view())
    h = health(); check("prunerecord: /health counts 2 archived after the replay", h.get("archived", 0) == 2, h)
    st, j = keyed("pr", "b-0"); check("prunerecord: a pruned key is free after the replay (201)", st == 201, (st, j))
    s.stop()
    rc, out = run(a.verify.format(dir=d), a.cwd); check("prunerecord: verify exits 0 on a log with a prune record", rc == 0, (rc, out[:160]))
    rc, out = run(a.compact.format(dir=d), a.cwd); check("prunerecord: compact exits 0", rc == 0, (rc, out[:160]))
    blob = folder_bytes(d)
    check("prunerecord: after compact no byte of a pruned job remains", b"UNIQUE-BEFORE-0-zq" not in blob and b"UNIQUE-BEFORE-1-zq" not in blob, [f for f in os.listdir(d)])
    check("prunerecord: after compact the later archived jobs are still on the disk", b"UNIQUE-AFTER-0-zq" in blob, [f for f in os.listdir(d)])
    rc, out = run(a.verify.format(dir=d), a.cwd); check("prunerecord: verify exits 0 after the compaction", rc == 0, (rc, out[:160]))
    s, _ = serve_with(a, d, " --retain-ms 500")
    check("prunerecord: the same view after the compaction", view() == ([404, 404], [200, 200]), view())
    # a broken prune record: prune with an age that leaves a unique number in the record, then break it on disk
    time.sleep(1.6); st, r = prune(1234567)
    st, r = prune(1000); s.stop()
    # find a file that changed with the last prune and holds a digit run to corrupt: replace the record's cutoff by a word
    hits = []
    for f in os.listdir(d):
        p = os.path.join(d, f)
        if not os.path.isfile(p): continue
        data = open(p, "rb").read()
        m = list(re.finditer(rb"prune", data, re.IGNORECASE))
        if m: hits.append((p, data, m[-1].start()))
    check("prunerecord: a file on the disk names the prune record", len(hits) >= 1, [h[0] for h in hits])
    if hits:
        p, data, at = hits[-1]
        tail = data[at:]; m = re.search(rb"\d{4,}", tail)
        if m:
            broken = data[:at] + tail[:m.start()] + b"not-a-cutoff" + tail[m.end():]
            open(p, "wb").write(broken)
            rc, out = run(a.verify.format(dir=d), a.cwd); check("prunerecord: a prune record with a bad cutoff refuses the folder, verify exits 1", rc == 1, (rc, out[:160]))
            port = d8.free_port(); cmd = a.serve.format(dir=d, port=port) + " --retain-ms 500"
            pr = subprocess.Popen(cmd, shell=True, cwd=a.cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, preexec_fn=os.setsid)
            try: pr.wait(timeout=15); rc = pr.returncode
            except subprocess.TimeoutExpired: os.killpg(os.getpgid(pr.pid), signal.SIGKILL); pr.wait(); rc = "still serving"
            check("prunerecord: serve refuses the folder with exit 1", rc == 1, rc)
            open(p, "wb").write(data)
            rc, out = run(a.verify.format(dir=d), a.cwd); check("prunerecord: restored, verify exits 0", rc == 0, (rc, out[:160]))
        else:
            check("prunerecord: the prune record carries a number to break (a cutoff)", False, tail[:80])
    shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------- the prune under a kill
def t_prunekill(a):
    base, d = fresh_dir("prunekill6-"); s, _ = serve_with(a, d, " --retain-ms 300")
    seed = [done_job("pk", f"seed-{i}") for i in range(40)]; time.sleep(0.6); wait_archived(40); time.sleep(2.2)
    h = health(); check("prunekill: forty archived jobs older than 2 s to set up", h.get("archived", 0) >= 40, h)
    stop = threading.Event(); lock = threading.Lock(); created = {}; acked = set()
    def worker(i):
        tok = f"w{i}"; n = 0
        while not stop.is_set():
            n += 1; k = f"k{i}-{n}"
            st, b = safe("POST", "/jobs", {"queue": "pk", "payload": "p", "max_tries": 2, "key": k}, token=tok)
            if st == 201 and isinstance(b, dict):
                with lock: created[b["id"]] = k
            st, b = safe("POST", "/queues/pk/lease", {"lease_ms": 60000}, token=tok)
            if st == 200 and isinstance(b, dict) and b.get("id"):
                st2, _ = safe("POST", f"/jobs/{b['id']}/ack", token=tok)
                if st2 == 200:
                    with lock: acked.add(b["id"])
    ths = [threading.Thread(target=worker, args=(i,), daemon=True) for i in range(4)]
    for t in ths: t.start()
    time.sleep(1.5)
    result = {}
    def pruner(): result["r"] = prune(2000)
    pt = threading.Thread(target=pruner, daemon=True); pt.start(); time.sleep(0.02); s.kill(); stop.set(); pt.join(3); time.sleep(0.3)
    drain()
    rc, out = run(a.verify.format(dir=d), a.cwd); check("prunekill: verify exits 0 after the kill", rc == 0, (rc, out[:160]))
    s, took = serve_with(a, d, " --retain-ms 300"); h = health()
    states = {jid: safe("GET", f"/jobs/{jid}")[0] for jid in seed if jid}
    present = [jid for jid, st in states.items() if st == 200]; gone = [jid for jid, st in states.items() if st == 404]
    check("prunekill: the old archived jobs are all present or all gone (the prune is one record)", len(present) == 0 or len(gone) == 0, (len(present), len(gone), result.get("r")))
    check("prunekill: every old job reads 200 or 404, nothing else", len(present) + len(gone) == len(states), {k: v for k, v in states.items() if v not in (200, 404)})
    if gone:
        st, j = keyed("pk", "seed-0"); check("prunekill: a pruned job's key is free after the reopen (201)", st == 201, (st, j))
    lost = [jid for jid in list(acked)[:200] if (safe("GET", f"/jobs/{jid}")[1] or {}).get("state") not in ("done", "archived") and safe("GET", f"/jobs/{jid}")[0] != 200]
    check(f"prunekill: every acknowledged ack is present ({len(acked)} acked)", not lost, lost[:3])
    total = sum(h.get(k, 0) for k in ("queued", "scheduled", "leased", "done", "dead", "archived"))
    check("prunekill: the young jobs are counted (created under the load, not older than the age, none pruned)", total >= len(created) - 1, (total, len(created)))
    s.stop(); shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------- the rename rule
def t_renamerule(a):
    base, d = fresh_dir("renamerule6-"); s, _ = serve_with(a, d, " --retain-ms 500")
    st, early = keyed("a", "e-1", max_tries=3)
    st, r = rename("a", "b"); check("renamerule: `a` renamed to `b`, 200", st == 200, (st, r))
    late = done_job("a", "l-1"); time.sleep(0.9); h = wait_archived(1)
    check("renamerule: a job created into `a` after the rename, done and archived", h.get("archived", 0) == 1 and late is not None, h)
    def view(): return (state_of(early["id"])[2], state_of(late)[2])
    check("renamerule: the early job is in `b`, the late one in `a`", view() == ("b", "a"), view())
    q = {x.get("name") for x in (safe("GET", "/queues")[1] or {}).get("queues", [])} if isinstance(safe("GET", "/queues")[1], dict) else None
    check("renamerule: /queues lists `a` and `b`", q is not None and {"a", "b"} <= q, q)
    s.stop(); s, _ = serve_with(a, d, " --retain-ms 500")
    check("renamerule: the same after a stop and start (the rename does not move a job created after it)", view() == ("b", "a"), view())
    s.stop()
    rc, out = run(a.compact.format(dir=d), a.cwd); check("renamerule: compact exits 0", rc == 0, (rc, out[:160]))
    rc, out = run(a.verify.format(dir=d), a.cwd); check("renamerule: verify exits 0 after the compaction", rc == 0, (rc, out[:160]))
    s, _ = serve_with(a, d, " --retain-ms 500")
    check("renamerule: the same after the compaction", view() == ("b", "a"), view())
    st, r = rename("b", "c"); st, r2 = rename("a", "b")
    check("renamerule: `b` to `c`, then `a` to `b` (a name reused), both 200", st == 200 and isinstance(r2, dict), (r, r2))
    check("renamerule: the early job is in `c`, the late one in `b`", view() == ("c", "b"), view())
    s.stop(); s, _ = serve_with(a, d, " --retain-ms 500")
    check("renamerule: the same after a second stop and start", view() == ("c", "b"), view())
    st, j = keyed("b", "l-1"); check("renamerule: the late job's key is used in `b` (200, the same job)", st == 200 and isinstance(j, dict) and j.get("id") == late, (st, j))
    s.stop(); shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------- the sequence
def t_sequence(a):
    base, d = fresh_dir("sequence6-"); s, _ = serve_with(a, d, " --retain-ms 500")
    q1 = [keyed("s1", f"s1-{i}", max_tries=3)[1] for i in range(4)]; q2 = [keyed("s2", f"s2-{i}", max_tries=3)[1] for i in range(4)]
    done1 = []
    for _ in range(2):
        st, l = lease("s1", ms=60000, token="w-s"); ack(l["id"], "w-s"); done1.append(l["id"])
    st, l = lease("s2", ms=60000, token="w-s"); ack(l["id"], "w-s"); done2 = l["id"]
    time.sleep(0.9); h = wait_archived(3); check("sequence: three done jobs archived", h.get("archived", 0) == 3, h)
    s.stop()
    rc, out = run(a.compact.format(dir=d), a.cwd); check("sequence: compact exits 0", rc == 0, (rc, out[:160]))
    s, _ = serve_with(a, d, " --retain-ms 500")
    st, r = rename("s1", "s1b"); check("sequence: rename `s1` to `s1b` after the compaction, 200", st == 200, (st, r))
    st, fresh = keyed("s1", "s1-fresh", max_tries=3); check("sequence: a create into the old name starts a fresh queue (201)", st == 201, (st, fresh))
    time.sleep(2.0)
    old_done = done_job("s2", "s2-late"); time.sleep(0.9); wait_archived(4)
    st, r = prune(1500); check("sequence: a prune with an age between removes the three older archived jobs and keeps the late one", st == 200 and isinstance(r, dict) and r.get("pruned") == 3 and r.get("remaining") == 1, (st, r))
    s.stop()
    rc, out = run(a.verify.format(dir=d), a.cwd); check("sequence: verify exits 0 after the stop", rc == 0, (rc, out[:160]))
    s, _ = serve_with(a, d, " --retain-ms 500")
    st, j = keyed("s1b", "s1-0"); check("sequence: a freed key (a pruned job's) creates a new job in the renamed queue (201)", st == 201, (st, j))
    st, j = keyed("s2", "s2-late"); check("sequence: a used key (the kept archived job's) answers 200 with the same job", st == 200 and isinstance(j, dict) and j.get("id") == old_done, (st, j))
    st, l = lease("s1b", ms=60000, token="w-t"); check("sequence: a lease on the renamed queue hands out a queued job", st == 200 and isinstance(l, dict), (st, l))
    st, b = ack(l["id"], "w-t"); check("sequence: its ack is 200", st == 200, (st, b))
    qs = safe("GET", "/queues")[1]; names = {x.get("name") for x in qs.get("queues", [])} if isinstance(qs, dict) else None
    check("sequence: /queues lists `s1b`, `s1`, and `s2`", names is not None and {"s1b", "s1", "s2"} <= names, names)
    st, ar = archive(); check("sequence: /archive counts 1", st == 200 and isinstance(ar, dict) and ar.get("archived") == 1, ar)
    h = health(); check("sequence: /health agrees (1 archived)", h.get("archived", 0) == 1, h)
    # a kill right after the reopen and a write: the folder the compaction wrote is the durable one
    st, w = keyed("s2", "s2-after-kill", max_tries=3); s.kill(); time.sleep(0.2)
    rc, out = run(a.verify.format(dir=d), a.cwd); check("sequence: verify exits 0 after a kill right after the reopen", rc == 0, (rc, out[:160]))
    s, _ = serve_with(a, d, " --retain-ms 500")
    st, g = get(w["id"]) if isinstance(w, dict) else (0, None); check("sequence: the write before the kill is present after the reopen", st == 200, (st, g))
    check("sequence: the pruned jobs are still gone after the kill and reopen", all(safe("GET", f"/jobs/{j}")[0] == 404 for j in done1 + [done2]), [state_of(j) for j in done1 + [done2]])
    s.stop(); shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------- the bench
def t_bench(a):
    base, d = fresh_dir("bench6-")
    rc, out = run(a.bench.format(dir=d, jobs=300, workers=4), a.cwd, timeout=240)
    check("bench: `jobq bench` exits 0 within four minutes on 300 jobs", rc == 0, (rc, out[-300:]))
    nums = re.findall(r"\d+(?:\.\d+)?", out)
    check("bench: it prints numbers for creates a second and pairs a second (at least four numbers)", len(nums) >= 4, out[-300:])
    low = out.lower()
    check("bench: its lines name creates, pairs, restart, and memory", all(w in low for w in ("create", "pair", "restart")) and ("rss" in low or "memory" in low or "resident" in low), out[-300:])
    check("bench: no jobq process is left after it", subprocess.run("pgrep -f 'serve " + d + "'", shell=True, capture_output=True).returncode != 0, "a server left")
    shutil.rmtree(base, ignore_errors=True)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--serve", required=True); ap.add_argument("--verify", required=True); ap.add_argument("--compact", required=True)
    ap.add_argument("--prune", required=True); ap.add_argument("--bench", required=True)
    ap.add_argument("--cwd", default=None); ap.add_argument("--only", default=None)
    a = ap.parse_args()
    for name, fn in (("prune", t_prune), ("retention", t_retention), ("prunerecord", t_prunerecord), ("prunekill", t_prunekill), ("renamerule", t_renamerule), ("sequence", t_sequence), ("bench", t_bench)):
        if a.only and name != a.only: continue
        try: fn(a)
        except Exception as e: check(f"{name}: ran to the end", False, f"{type(e).__name__}: {e}")
        subprocess.run("pkill -f 'serve /tmp'", shell=True, capture_output=True)
    print(f"\n{len(d8.PASSES)} passed, {len(d8.DEFECTS)} defects")
    for name, detail in d8.DEFECTS: print(f"  - {name}: {str(detail)[:300]}")

if __name__ == "__main__": main()
