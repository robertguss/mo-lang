#!/usr/bin/env python3
"""The erosion round's fifth hidden suite, for change 4 (mo-wiki/spec/programs/01e-job-queue-change-4.md).
Written by Fable on 16 Sep 2026 after the four maintainers' sessions started (13:05); never shown to a worker.

Categories: `flags` (--retain-ms and its range; verify and compact refuse it), `key` (the key's rule, the second
create answered with the first job in every state, the key freed by a delete, the lookup), `keykept` (the key
across a stop and start, across a chaos restart, across a compaction), `archive` (done and dead jobs older than
retain_ms archived at the next look: /health, listings, /queues, the read, retry, delete, verify's line, the file),
`archivekill` (short-lived jobs under load with a small retain_ms, the service killed under it, every job counted
once on the reopened folder, keys of archived jobs still used), `verifyarchive` (a bad archive record refuses the
folder; a torn archive line is cut). The suites of the earlier generations are the regressions and run separately.

usage: defects4.py --serve '<cmd> serve {dir} --port {port}' --verify '<cmd> verify {dir}' --compact '<cmd> compact {dir}'
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
def wait_health(deadline_s=5.0):
    t0 = time.time()
    while time.time() - t0 < deadline_s:
        st, _ = safe("GET", "/health", token=None, timeout=1.0)
        if st == 200: return time.time() - t0
        time.sleep(0.01)
    return None
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
def archive_path(d):
    for name in ("jobq.archive", "jobs.archive", "archive.log", "jobq.archive.log"):
        p = os.path.join(d, name)
        if os.path.exists(p): return p
    return None
def keyed(queue, key, payload="p", max_tries=2, **more): return create(queue=queue, payload=payload, max_tries=max_tries, key=key, **more)
def looked():
    """a look: a lease request on a queue with nothing in it"""
    return lease("nothing-here", ms=1000, token="w-look")

# ---------------------------------------------------------------- flags
def t_flags(a):
    base, d = fresh_dir("flags4-")
    s, _ = serve_with(a, d, " --retain-ms 1000"); st, h = safe("GET", "/health", token=None)
    check("flags: serve accepts --retain-ms 1000 and /health carries archived 0", st == 200 and isinstance(h, dict) and h.get("archived") == 0, (st, h)); s.stop()
    s, _ = serve_with(a, d); st, h = safe("GET", "/health", token=None)
    check("flags: without the option /health still carries archived", st == 200 and isinstance(h, dict) and "archived" in h, h); s.stop()
    for opts in (" --retain-ms 999", " --retain-ms 2678400001", " --retain-ms -5", " --retain-ms x", " --retain-ms 1000 --retain-ms 1000"):
        port = d8.free_port(); cmd = (a.serve + opts).format(dir=d, port=port)
        p = subprocess.Popen(cmd, shell=True, cwd=a.cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, preexec_fn=os.setsid)
        try: p.wait(timeout=10); rc = p.returncode
        except subprocess.TimeoutExpired: os.killpg(os.getpgid(p.pid), signal.SIGKILL); p.wait(); rc = "still serving"
        check(f"flags: `{opts.strip()}` is a usage error, exit 2", rc == 2, rc)
    rc, out = run(a.verify.format(dir=d) + " --retain-ms 1000", a.cwd); check("flags: verify does not take --retain-ms (exit 2)", rc == 2, (rc, out[:100]))
    rc, out = run(a.compact.format(dir=d) + " --retain-ms 1000", a.cwd); check("flags: compact does not take --retain-ms (exit 2)", rc == 2, (rc, out[:100]))
    shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------- the key
def t_key(a):
    base, d = fresh_dir("key4-"); s, _ = serve_with(a, d)
    st, j = keyed("emails", "order-1", payload="first"); check("key: a create with a key is 201", st == 201, (st, j)); first = j if isinstance(j, dict) else {}
    check("key: the job carries its key", first.get("key") == "order-1", first)
    st, j2 = keyed("emails", "order-1", payload="second", max_tries=5)
    check("key: the same key in the same queue is 200 with the first job", st == 200 and isinstance(j2, dict) and j2.get("id") == first.get("id"), (st, j2))
    check("key: the second body is ignored (payload and max_tries unchanged)", isinstance(j2, dict) and j2.get("payload") == "first" and j2.get("max_tries") == 2, j2)
    st, h = safe("GET", "/health", token=None); check("key: no second job was made", isinstance(h, dict) and h.get("queued") == 1, h)
    st, j3 = keyed("reports", "order-1"); check("key: the same key in another queue is 201 and another job", st == 201 and isinstance(j3, dict) and j3.get("id") != first.get("id"), (st, j3))
    st, j4 = create(queue="emails", payload="plain", max_tries=2); check("key: a create without a key still works", st == 201 and isinstance(j4, dict) and "key" not in j4, (st, j4))
    for bad, why in (("", "empty"), ("a b", "a space"), ("k" * 65, "65 bytes"), ("é", "not ascii"), (7, "a number"), (None, "null")):
        st, j = create(queue="emails", payload="p", max_tries=2, key=bad); check(f"key: {why} is 400", st == 400, (st, j))
    st, j = req("GET", "/jobs?queue=emails&key=order-1"); jl = jobs_of(j)
    check("key: GET /jobs?queue&key finds the job", st == 200 and jl is not None and len(jl) == 1 and jl[0].get("id") == first.get("id"), (st, j))
    st, j = req("GET", "/jobs?queue=emails&key=nope"); check("key: an unused key lists nothing", st == 200 and jobs_of(j) == [], (st, j))
    st, j = req("GET", "/jobs?key=order-1"); check("key: key without queue is 400", st == 400, (st, j))
    # every state: leased, done, dead, scheduled
    st, l = lease("emails", ms=60000, token="w1"); leased_id = l.get("id") if isinstance(l, dict) else None
    st, j = keyed("emails", "order-1"); check("key: while leased the second create is 200 the same job", st == 200 and isinstance(j, dict) and j.get("id") == first.get("id") and j.get("state") in ("leased", "queued"), (st, j))
    if leased_id == first.get("id"): req("POST", f"/jobs/{leased_id}/ack", token="w1")
    else:
        req("POST", f"/jobs/{leased_id}/ack", token="w1"); st, l = lease("emails", ms=60000, token="w1"); req("POST", f"/jobs/{l['id']}/ack", token="w1")
    st, j = get(first["id"]); done_now = isinstance(j, dict) and j.get("state") == "done"
    st, j = keyed("emails", "order-1"); check("key: once done the second create is still 200 the same job", st == 200 and isinstance(j, dict) and j.get("id") == first.get("id"), (st, j))
    st, dj = keyed("alerts", "dies", max_tries=1); st, l = lease("alerts", ms=1000, token="w1"); req("POST", f"/jobs/{l['id']}/fail", {"reason": "x"}, token="w1")
    st, j = keyed("alerts", "dies"); check("key: once dead the second create is 200 the dead job", st == 200 and isinstance(j, dict) and j.get("id") == dj.get("id") and j.get("state") == "dead", (st, j))
    st, sj = keyed("later", "sched", delay_ms=60000); st, j = keyed("later", "sched"); check("key: a scheduled job's key is used", st == 200 and isinstance(j, dict) and j.get("id") == sj.get("id"), (st, j))
    st, _ = req("DELETE", f"/jobs/{dj['id']}"); st, j = keyed("alerts", "dies")
    check("key: a delete frees the key, the next create is 201 a new job", st == 201 and isinstance(j, dict) and j.get("id") != dj.get("id"), (st, j))
    st, j = req("GET", f"/jobs/{first['id']}"); check("key: the key shows on a read", isinstance(j, dict) and j.get("key") == "order-1", j)
    st, j = req("GET", "/jobs?queue=emails"); jl = jobs_of(j) or []
    check("key: keys show in listings, plain jobs have none", any(x.get("key") == "order-1" for x in jl) and any("key" not in x for x in jl), jl)
    s.stop(); shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------- the key kept
def t_keykept(a):
    # amended 14:55: the switch counts records the board applies, and what a program counts as a record differs (Mo counts the
    # ids reservation), so the keyed creates are made with the switch far off, then plain creates until one fails, then the restart
    base, d = fresh_dir("keykept4-"); s, _ = serve_with(a, d, " --crash-every 25 --max-restarts 100")
    st, j1 = keyed("q", "k1"); check("keykept: the first keyed create is 201", st == 201, (st, j1)); st, j2 = keyed("q", "k2"); check("keykept: the second keyed create is 201", st == 201, (st, j2))
    failed = False
    for i in range(60):
        st, _ = safe("POST", "/jobs", {"queue": "q", "payload": "p", "max_tries": 1})
        if st in (503, -1): failed = True; break
    check("keykept: a plain create eventually trips the switch", failed, i); wait_health(5.0)
    st, j = keyed("q", "k1"); check("keykept: after a chaos restart the key is still used (200, the same job)", st == 200 and isinstance(j, dict) and j.get("id") == j1.get("id"), (st, j))
    k3 = None
    for i in range(3):
        st, j = keyed("q", "k3")
        if st == 201: k3 = j; break
        if st == 200 and isinstance(j, dict) and j.get("key") == "k3": k3 = j; break
        wait_health(5.0)
    check("keykept: a new key after the restart is made (201, or 200 if the failed attempt landed)", k3 is not None, (st, j))
    if k3 is None: k3 = {}
    s.stop(); s, _ = serve_with(a, d)
    st, j = keyed("q", "k2"); check("keykept: after a stop and start the key is still used", st == 200 and isinstance(j, dict) and j.get("id") == j2.get("id"), (st, j))
    st, j = keyed("q", "k3"); check("keykept: a key made just before the stop is still used", st == 200 and isinstance(j, dict) and j.get("id") == k3.get("id"), (st, j))
    req("DELETE", f"/jobs/{j2['id']}"); s.stop()
    rc, out = run(a.compact.format(dir=d), a.cwd); check("keykept: compact exits 0", rc == 0, (rc, out[:120]))
    s, _ = serve_with(a, d)
    st, j = keyed("q", "k1"); check("keykept: after a compaction the key is still used", st == 200 and isinstance(j, dict) and j.get("id") == j1.get("id"), (st, j))
    st, j = keyed("q", "k2"); check("keykept: a key freed before the compaction is free after it", st == 201, (st, j))
    s.stop()  # amended 14:40: verify runs on a folder that is not being served (Go's verify refuses a served folder, a variant recorded in generation two)
    rc, out = run(a.verify.format(dir=d), a.cwd); check("keykept: verify exits 0 on a folder with keys", rc == 0, (rc, out[:120]))
    shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------- the archive
def t_archive(a):
    base, d = fresh_dir("archive4-"); s, _ = serve_with(a, d, " --retain-ms 1000")
    ids = {}
    st, j = keyed("emails", "done-1"); ids["done1"] = j["id"]; st, j = create(queue="emails", payload="p", max_tries=2); ids["done2"] = j["id"]
    st, j = create(queue="emails", payload="p", max_tries=1); ids["dead"] = j["id"]
    st, j = create(queue="emails", payload="stays", max_tries=2); ids["queued"] = j["id"]
    for _ in range(2):
        st, l = lease("emails", ms=60000, token="w1"); req("POST", f"/jobs/{l['id']}/ack", token="w1")
    st, l = lease("emails", ms=60000, token="w1"); req("POST", f"/jobs/{l['id']}/fail", {"reason": "x"}, token="w1")
    h0 = health(); check("archive: before retain_ms nothing is archived", h0.get("archived") == 0 and h0.get("done") == 2 and h0.get("dead") == 1, h0)
    time.sleep(1.6); looked()
    h1 = health(); check("archive: after retain_ms and a look, 3 archived", h1.get("archived") == 3, h1)
    check("archive: done and dead no longer count them", h1.get("done") == 0 and h1.get("dead") == 0 and h1.get("queued") == 1, h1)
    st, j = req("GET", "/jobs?queue=emails"); jl = jobs_of(j) or []
    check("archive: the listing shows only the live job", [x.get("id") for x in jl] == [ids["queued"]], jl)
    st, j = req("GET", "/queues"); q = next((x for x in (j.get("queues", []) if isinstance(j, dict) else []) if x.get("name") == "emails"), {})
    check("archive: /queues counts only live jobs", q.get("queued") == 1 and q.get("done", 0) == 0 and q.get("dead", 0) == 0, q)
    st, j = get(ids["done1"]); check("archive: an archived job reads 200 with archived_at", st == 200 and isinstance(j, dict) and j.get("archived_at") and j.get("state") == "done", (st, j))
    st, j = get(ids["dead"]); check("archive: the archived dead job reads 200 as dead", st == 200 and isinstance(j, dict) and j.get("state") == "dead" and j.get("archived_at"), (st, j))
    st, j = req("POST", f"/jobs/{ids['dead']}/retry"); check("archive: retry of an archived job is 409", st == 409, (st, j))
    st, j = keyed("emails", "done-1"); check("archive: the key of an archived job is still used (200, that job)", st == 200 and isinstance(j, dict) and j.get("id") == ids["done1"], (st, j))
    st, j = get(ids["queued"]); check("archive: the queued job is not archived", st == 200 and "archived_at" not in j, j)
    p = archive_path(d); check("archive: the archive file exists in the folder", p is not None, os.listdir(d))
    if p:
        lines = [l for l in open(p, errors="replace").read().splitlines() if l.strip()]
        check("archive: the file holds three records", len(lines) == 3, len(lines))
    st, _ = req("DELETE", f"/jobs/{ids['done2']}"); check("archive: delete of an archived job is 204", st == 204, st)
    st, j = get(ids["done2"]); check("archive: a deleted archived job reads 404", st == 404, (st, j))
    h2 = health(); check("archive: /health archived drops to 2 after the delete", h2.get("archived") == 2, h2)
    s.stop()
    rc, out = run(a.verify.format(dir=d), a.cwd); check("verify: exits 0 with the archive", rc == 0, (rc, out[:160]))
    check("verify: the line ends with '; archived 2'", re.search(r"; archived 2\s*$", out.splitlines()[0] if out else "") is not None or "archived 2" in out, out[:160])
    rc, out = run(a.compact.format(dir=d), a.cwd); check("archive: compact exits 0", rc == 0, (rc, out[:120]))
    if p:
        lines = [l for l in open(p, errors="replace").read().splitlines() if l.strip()]
        check("archive: after compact the archive holds the two undeleted records", len(lines) == 2, len(lines))
    s, took = serve_with(a, d); h3 = health()
    check("archive: after compact and a restart /health counts 2 archived, 1 queued", h3.get("archived") == 2 and h3.get("queued") == 1 and h3.get("done") == 0, h3)
    st, j = get(ids["done1"]); check("archive: the archived job still reads after the restart", st == 200 and isinstance(j, dict) and j.get("archived_at"), (st, j))
    st, j = keyed("emails", "done-1"); check("archive: its key is still used after the restart", st == 200, (st, j))
    st, j = req("GET", "/jobs?queue=emails"); check("archive: the listing after the restart shows only the live job", [x.get("id") for x in (jobs_of(j) or [])] == [ids["queued"]], j)
    s.stop(); shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------- the archive under a kill
def t_archivekill(a):
    base, d = fresh_dir("archivekill4-"); s, _ = serve_with(a, d, " --retain-ms 1000")
    stop = threading.Event(); lock = threading.Lock(); created = {}; keys = {}
    def worker(i):
        q = f"q{i % 2}"; tok = f"w{i}"; n = 0
        while not stop.is_set():
            n += 1; k = f"k{i}-{n}"
            st, b = safe("POST", "/jobs", {"queue": q, "payload": "p", "max_tries": 1, "key": k}, token=tok)
            if st == 201:
                with lock: created[b["id"]] = k
            st, b = safe("POST", f"/queues/{q}/lease", {"lease_ms": 30000}, token=tok)
            if st == 200 and isinstance(b, dict) and b.get("id"):
                if n % 3: safe("POST", f"/jobs/{b['id']}/ack", token=tok)
                else: safe("POST", f"/jobs/{b['id']}/fail", {"reason": "x"}, token=tok)
    ths = [threading.Thread(target=worker, args=(i,), daemon=True) for i in range(4)]
    for t in ths: t.start()
    time.sleep(3.5); s.kill(); stop.set(); time.sleep(0.3)
    drain()
    rc, out = run(a.verify.format(dir=d), a.cwd); check("archivekill: verify exits 0 after the kill", rc == 0, (rc, out[:160]))
    s, took = serve_with(a, d, " --retain-ms 1000"); h = health()
    total = sum(h.get(k, 0) for k in ("queued", "scheduled", "leased", "done", "dead", "archived"))
    check("archivekill: every created job is counted exactly once after the reopen", total == len(created), (total, len(created), h))
    check("archivekill: some jobs were archived under the load", h.get("archived", 0) > 0, h)
    missing, twice = [], []
    sample = list(created.items())[::max(1, len(created) // 150)]
    for jid, k in sample:
        st, j = safe("GET", f"/jobs/{jid}")
        if st != 200: missing.append((jid, st)); continue
        st2, j2 = safe("POST", "/jobs", {"queue": j.get("queue"), "payload": "p", "max_tries": 1, "key": k})
        if st2 != 200 or not isinstance(j2, dict) or j2.get("id") != jid: twice.append((jid, k, st2, j2.get("id") if isinstance(j2, dict) else j2))
    check(f"archivekill: every sampled job reads 200, live or archived ({len(sample)} sampled)", not missing, missing[:3])
    check("archivekill: every sampled key is still used by its job", not twice, twice[:3])
    p = archive_path(d)
    if p:
        # amended 14:55: one id per line (Mo's line names the id before the record too)
        ids_in_archive = [m.group(0) for l in open(p, errors="replace").read().splitlines() for m in [re.search(r'j_\d+', l)] if m and "deleted" not in l and '"delete"' not in l and '"del"' not in l]
        check("archivekill: no id appears twice in the archive", len(ids_in_archive) == len(set(ids_in_archive)), len(ids_in_archive) - len(set(ids_in_archive)))
    s.stop(); s, took = serve_with(a, d, " --retain-ms 1000"); h2 = health()
    total2 = sum(h2.get(k, 0) for k in ("queued", "scheduled", "leased", "done", "dead", "archived"))
    check("archivekill: the total is the same after a second reopen (time passes, so more may be archived)", total2 == total, (total, total2, h, h2))  # amended 14:40: the first form compared each count, and done jobs age into the archive between reopens
    s.stop(); shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------- verify on the archive
def t_verifyarchive(a):
    base, d = fresh_dir("verifyarchive4-"); s, _ = serve_with(a, d, " --retain-ms 1000")
    st, j = create(queue="q", payload="p", max_tries=2); st, l = lease("q", ms=60000, token="w1"); req("POST", f"/jobs/{l['id']}/ack", token="w1")
    time.sleep(1.6); looked(); h = health(); s.stop()
    p = archive_path(d)
    check("verifyarchive: one record archived to set up", h.get("archived") == 1 and p is not None, (h, os.listdir(d)))
    if not p: shutil.rmtree(base, ignore_errors=True); return
    good = open(p, "rb").read()
    # a torn last line is cut, not refused
    open(p, "wb").write(good + good.strip(b"\n").splitlines()[-1][: len(good.strip(b"\n").splitlines()[-1]) // 2])
    rc, out = run(a.verify.format(dir=d), a.cwd); check("verifyarchive: a torn last archive line is cut, verify exits 0", rc == 0, (rc, out[:160]))
    s, took = serve_with(a, d); h2 = health(); check("verifyarchive: serve opens the torn archive and counts 1 archived", h2.get("archived") == 1, h2); s.stop()
    # a record in the archive that is not done or dead refuses the folder
    line = good.strip(b"\n").splitlines()[-1]
    bad = line.replace(b'"done"', b'"queued"').replace(b"done", b"queued", 1) if b"queued" not in line else line
    open(p, "wb").write(good + bad + b"\n")
    rc, out = run(a.verify.format(dir=d), a.cwd); check("verifyarchive: a queued record in the archive is refused, exit 1", rc == 1, (rc, out[:160]))
    check("verifyarchive: the refusal names a record", "record" in out.lower(), out[:160])
    port = d8.free_port(); cmd = a.serve.format(dir=d, port=port)
    pr = subprocess.Popen(cmd, shell=True, cwd=a.cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, preexec_fn=os.setsid)
    try: pr.wait(timeout=15); rc = pr.returncode
    except subprocess.TimeoutExpired: os.killpg(os.getpgid(pr.pid), signal.SIGKILL); pr.wait(); rc = "still serving"
    check("verifyarchive: serve refuses the folder with exit 1", rc == 1, rc)
    open(p, "wb").write(good)
    rc, out = run(a.verify.format(dir=d), a.cwd); check("verifyarchive: restored, verify exits 0", rc == 0, (rc, out[:160]))
    shutil.rmtree(base, ignore_errors=True)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--serve", required=True); ap.add_argument("--verify", required=True); ap.add_argument("--compact", required=True)
    ap.add_argument("--cwd", default=None); ap.add_argument("--only", default=None)
    a = ap.parse_args()
    for name, fn in (("flags", t_flags), ("key", t_key), ("keykept", t_keykept), ("archive", t_archive), ("verifyarchive", t_verifyarchive), ("archivekill", t_archivekill)):
        if a.only and name != a.only: continue
        try: fn(a)
        except Exception as e: check(f"{name}: ran to the end", False, f"{type(e).__name__}: {e}")
        subprocess.run("pkill -f 'serve /var/folders'", shell=True, capture_output=True)
    print(f"\n{len(d8.PASSES)} passed, {len(d8.DEFECTS)} defects")
    for name, detail in d8.DEFECTS: print(f"  - {name}: {str(detail)[:300]}")

if __name__ == "__main__": main()
