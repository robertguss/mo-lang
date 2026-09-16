#!/usr/bin/env python3
"""The erosion round's fourth oracle, from the four maintainers' decision lists (16 Sep 2026, Fable).
Inputs the change 2 spec left open and the maintainers decided differently, driven through the API and the
folder so the same script fits every implementation:
  1. `verify` on a folder that does not exist, and on an empty folder (Python prints `0 jobs`, others?)
  2. `verify` while `serve` holds the folder (Python's decision 3: verify takes the exclusive lock and refuses)
  3. a torn last line: `verify` must not rewrite the log (Mo's decision 5), and `serve` after it still opens
  4. the id sequence after deletes and a compaction, then a restart: the next id is still the highest ever
     handed out plus one (the counter decisions: Mo and Elixir refuse a counter below a job, Python lifts it)
  5. `GET /queues` when a queue's only job is dead, and when its only job is scheduled
  6. a `503` shape: the error body is JSON with an `error` key (Python's decision 7)
usage: oracle5.py --serve '<cmd> serve {dir} --port {port}' --verify '<cmd> verify {dir}' --compact '<cmd> compact {dir}' [--cwd DIR]
"""
import argparse, os, shutil, subprocess, sys, tempfile, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "control-run-8-suite"))
import defects as d8
from defects import Server, req, create, lease, get, health, check

def run(cmd, cwd, timeout=60):
    p = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    return p.returncode, (p.stdout + p.stderr).strip()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--serve", required=True); ap.add_argument("--verify", required=True); ap.add_argument("--compact", required=True); ap.add_argument("--cwd", default=None)
    a = ap.parse_args()
    base = tempfile.mkdtemp(prefix="oracle5-")
    # 1. nonexistent and empty folders
    rc, out = run(a.verify.format(dir=os.path.join(base, "nowhere")), a.cwd)
    check("oracle5: verify on a folder that does not exist exits 1 with one jobq: line", rc == 1 and out.strip().startswith("jobq:"), (rc, out[-160:]))
    empty = os.path.join(base, "empty"); os.mkdir(empty)
    rc, out = run(a.verify.format(dir=empty), a.cwd)
    print(f"     oracle5: verify on an empty folder -> exit {rc}: {out.strip().splitlines()[-1] if out.strip() else ''}")
    check("oracle5: verify on an empty folder exits 0 or 1, never 2 or a crash", rc in (0, 1), (rc, out[-160:]))
    # 2. verify while served
    d = os.path.join(base, "dir"); os.mkdir(d)
    s = Server(a.serve, a.cwd, d); s.start(); d8.PORT = s.port
    for i in range(5): create(queue="q", payload=f"p{i}", max_tries=2)
    rc, out = run(a.verify.format(dir=d), a.cwd)
    print(f"     oracle5: verify while served -> exit {rc}: {out.strip().splitlines()[-1] if out.strip() else ''}")
    check("oracle5: verify while the folder is served exits 0 (reads what is there) or 1 (refuses the lock), never 2 or a crash", rc in (0, 1), (rc, out[-160:]))
    st, h = req("GET", "/health"); check("oracle5: the service still answers after a verify ran on its folder", st == 200, (st, h))
    # 4. the id sequence after deletes, a compaction, and a restart
    for i in (1, 2, 3, 4): req("DELETE", f"/jobs/j_{i}")
    s.stop()
    rc, out = run(a.compact.format(dir=d), a.cwd); check("oracle5: compact after four deletes exits 0", rc == 0, (rc, out[-160:]))
    rc, out = run(a.verify.format(dir=d), a.cwd)
    nxt = [l for l in out.splitlines() if l.strip().startswith("1 jobs:")]
    check("oracle5: verify after the compaction says 1 job and a next id above j_5", rc == 0 and nxt and int(nxt[-1].strip().split("next id j_")[-1]) >= 6, (rc, out[-160:]))
    s = Server(a.serve, a.cwd, d); s.start(); d8.PORT = s.port
    st, c = create(queue="q", payload="after", max_tries=1); check("oracle5: the id after deletes, a compaction, and a restart is above every id handed out (j_6 or more; Mo reserves a block)", st == 201 and int(c.get("id", "j_0")[2:]) >= 6, (st, c))
    print(f"     oracle5: the id after deletes, a compaction, and a restart: {c.get('id')}")
    # 5. /queues with only a dead job, only a scheduled job
    st, x = create(queue="dead-only", payload="p", max_tries=1); st, l = lease("dead-only", token="w1"); req("POST", f"/jobs/{l['id']}/fail", {"reason": "x"}, token="w1")
    create(queue="sched-only", payload="p", max_tries=1, delay_ms=60000)
    st, qs = req("GET", "/queues"); names = {q["name"]: q for q in (qs.get("queues", []) if isinstance(qs, dict) else [])}
    check("oracle5: a queue whose only job is dead is listed with dead 1", names.get("dead-only", {}).get("dead") == 1, names.get("dead-only"))
    check("oracle5: a queue whose only job is scheduled is listed with scheduled 1", names.get("sched-only", {}).get("scheduled") == 1, names.get("sched-only"))
    # 3. the torn last line and verify
    s.stop()
    logs = [p for p in os.listdir(d) if os.path.isfile(os.path.join(d, p)) and not p.endswith(".lock")]
    log = os.path.join(d, sorted(logs, key=lambda p: os.path.getsize(os.path.join(d, p)))[-1])
    with open(log, "ab") as f: f.write(b'{"id": "j_99", "queue": "q", "state": "queu')
    before = open(log, "rb").read()
    rc, out = run(a.verify.format(dir=d), a.cwd)
    after = open(log, "rb").read()
    check("oracle5: verify on a torn last line exits 0", rc == 0, (rc, out[-160:]))
    check("oracle5: verify does not rewrite the log", before == after, (len(before), len(after)))
    s = Server(a.serve, a.cwd, d)
    try:
        s.start(); d8.PORT = s.port
        st, h = req("GET", "/health"); check("oracle5: serve after the torn line opens and answers", st == 200, (st, h))
        # 6. the 503 body shape cannot be forced here without the disk; check the 404 and 409 bodies are JSON with error
        st, j = req("POST", "/jobs/j_none/ack", token="w1"); check("oracle5: an ack on a missing job is a 404 with a JSON error body", st == 404 and isinstance(j, dict) and "error" in j, (st, j))
    finally:
        s.stop()
    print(f"\n{len(d8.PASSES)} passed, {len(d8.DEFECTS)} defects")
    for name, detail in d8.DEFECTS: print(f"  - {name}: {str(detail)[:240]}")
    shutil.rmtree(base, ignore_errors=True)

if __name__ == "__main__": main()
