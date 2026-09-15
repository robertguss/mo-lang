#!/usr/bin/env python3
"""Round 8's fourth oracle (mo-wiki/plans/control-run-8.md, from measurement 2): inputs the suites do not
send, taken from the three maintainers' "decisions the change spec did not cover", played through all
three changed programs. Disagreement is the signal; the lead reads each against the spec.

usage: oracle4.py --name NAME --serve '<cmd> serve {dir} --port {port}' [--cwd DIR] --log-format mo|go|python
Prints one line per probe: NAME probe -> status body-head; run once per program and compare by eye.
"""
import argparse, json, os, shutil, signal, socket, subprocess, tempfile, time
import http.client

def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p

def req(port, method, path, body=None, token="ada"):
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
    h = {"authorization": f"Bearer {token}"}
    data = None
    if body is not None: data = json.dumps(body).encode(); h["content-type"] = "application/json"
    c.request(method, path, body=data, headers=h); r = c.getresponse(); b = r.read(); c.close()
    try: j = json.loads(b) if b else None
    except Exception: j = b.decode("utf-8", "replace")
    return r.status, j

def serve(template, cwd, d):
    port = free_port()
    p = subprocess.Popen(template.format(dir=d, port=port), shell=True, cwd=cwd, stdout=open(os.path.join(d, "..", "out"), "w"), stderr=subprocess.STDOUT, preexec_fn=os.setsid)
    t0 = time.time()
    while time.time() - t0 < 15:
        if p.poll() is not None: return p, port, f"exited {p.returncode}: " + open(os.path.join(d, "..", "out")).read()[-200:].strip()
        try:
            st, _ = req(port, "GET", "/health", token=None)
            if st == 200: return p, port, "up"
        except Exception: pass
        time.sleep(0.05)
    return p, port, "no answer in 15 s"

def stop(p):
    if p and p.poll() is None:
        os.killpg(os.getpgid(p.pid), signal.SIGKILL); p.wait()

# --- log writers in each implementation's own framing, with a job record given as a dict ---
def crc32c(data):
    poly = 0x82F63B78; crc = 0xFFFFFFFF
    for b in data:
        crc ^= b
        for _ in range(8): crc = (crc >> 1) ^ poly if crc & 1 else crc >> 1
    return crc ^ 0xFFFFFFFF

def write_log(fmt, d, jobs):
    if fmt == "mo":
        with open(os.path.join(d, "jobq.log"), "w") as f:
            f.write("SET ids 1000\n")
            for j in jobs: f.write(f"SET {j['id']} {json.dumps(j)}\n")
    elif fmt == "go":
        with open(os.path.join(d, "jobq.log"), "wb") as f:
            for j in jobs:
                body = json.dumps({"op": "put", "job": j}, separators=(",", ":")).encode()
                f.write(f"{crc32c(body):08x} ".encode() + body + b"\n")
    else:
        # the Python program's own shape: a number, epoch milliseconds, explicit nulls
        with open(os.path.join(d, "jobs.log"), "w") as f:
            for j in jobs:
                r = {"number": int(j["id"][2:]), "queue": j["queue"], "state": j["state"], "payload": j["payload"]}
                for k in ("attempts", "max_attempts", "tries", "max_tries", "backoff_ms"):
                    if k in j: r[k] = j[k]
                r["created_ms"] = 1789376400000; r["updated_ms"] = 1789376400000
                if "run_at" in j: r["run_at_ms"] = 1789376460000
                r["worker"] = None; r["lease_until_ms"] = None; r["reason"] = None
                f.write(json.dumps({"kind": "put", "job": r}) + "\n")

def base_job(n, **more):
    j = {"id": f"j_{n}", "queue": "q", "state": "queued", "payload": f"p{n}", "created_at": "2026-09-14T09:00:00.000Z", "updated_at": "2026-09-14T09:00:00.000Z"}
    j.update(more); return j

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--name", required=True); ap.add_argument("--serve", required=True); ap.add_argument("--cwd"); ap.add_argument("--log-format", required=True)
    a = ap.parse_args()
    out = []
    def probe(name, text): out.append(f"{a.name:7} {name:44} -> {text}"); print(out[-1], flush=True)

    # 1. live-service probes on an empty folder
    base = tempfile.mkdtemp(prefix="oracle4-"); d = os.path.join(base, "dir"); os.mkdir(d)
    p, port, up = serve(a.serve, a.cwd, d)
    if up != "up": probe("empty folder serves", up); stop(p); return
    st, r = req(port, "POST", "/jobs", {"queue": "q", "payload": "p", "max_tries": 1, "extra": 1}); probe("create with an unknown field `extra`", f"{st} {str(r)[:70]}")
    st, r = req(port, "POST", "/jobs", {"queue": "q", "payload": "p", "max_tries": 1, "delay_ms": 0.0}); probe("create with delay_ms 0.0 (a float that is whole)", f"{st} {str(r)[:70]}")
    st, r = req(port, "POST", "/jobs", {"queue": "q", "payload": "p", "max_tries": 1, "backoff_ms": None}); probe("create with backoff_ms null", f"{st} {str(r)[:70]}")
    st, a1 = req(port, "POST", "/jobs", {"queue": "at", "payload": "p", "max_tries": 2, "delay_ms": 100})
    time.sleep(0.1)  # a lease exactly around run_at: leasable at run_at itself or a millisecond later?
    st, r = req(port, "POST", "/queues/at/lease", {"lease_ms": 1000}, token="w"); probe("lease at about run_at (100 ms delay, 100 ms later)", f"{st}")
    st, b1 = req(port, "POST", "/jobs", {"queue": "other", "payload": "p", "max_tries": 1, "delay_ms": 150})
    time.sleep(0.25); st, r = req(port, "POST", "/queues/q/lease", {"lease_ms": 1000}, token="w")  # a look on another queue
    st, r = req(port, "GET", "/health", token=None); probe("a due job in `other` after a lease on `q` only: /health", f"scheduled={r.get('scheduled') if isinstance(r, dict) else r}")
    st, c1 = req(port, "POST", "/jobs", {"queue": "rt", "payload": "p", "max_tries": 1})
    st, r = req(port, "POST", "/queues/rt/lease", {"lease_ms": 1000}, token="w"); st, r = req(port, "POST", f"/jobs/{c1['id']}/fail", {"reason": "x"}, token="w")
    st, r = req(port, "POST", f"/jobs/{c1['id']}/retry", {"reason": "operator"}, token="op"); probe("retry with a JSON body", f"{st} {r.get('state') if isinstance(r, dict) else r}")
    st, r = req(port, "POST", f"/jobs/{c1['id']}/retry", token="op"); probe("retry of a queued job: the 409 body", f"{st} {str(r)[:70]}")
    st, r = req(port, "POST", "/jobs", {"queue": "q", "payload": "p", "max_tries": 1, "delay_ms": 5, "backoff_ms": 5}); st, r = req(port, "GET", f"/jobs/{r['id']}"); probe("a job created with delay 5 ms, read at once", f"{r.get('state')} run_at={'run_at' in r}")
    stop(p); shutil.rmtree(base, ignore_errors=True)

    # 2. logs in the new shape with records the spec does not describe
    cases = {
        "record with both attempts and tries": [base_job(1, attempts=0, max_attempts=2, tries=0, max_tries=2, backoff_ms=0)],
        "record with neither count": [base_job(1, backoff_ms=0)],
        "old record whose attempts equal max_attempts while queued": [base_job(1, attempts=2, max_attempts=2)],
        "new record scheduled with run_at in the past": [base_job(1, tries=0, max_tries=2, backoff_ms=0, state="scheduled", run_at="2026-09-14T09:01:00.000Z")],
        "new record scheduled without run_at": [base_job(1, tries=0, max_tries=2, backoff_ms=0, state="scheduled")],
        "old record with backoff_ms present": [base_job(1, attempts=0, max_attempts=2, backoff_ms=250)],
    }
    for name, jobs in cases.items():
        base = tempfile.mkdtemp(prefix="oracle4-"); d = os.path.join(base, "dir"); os.mkdir(d)
        write_log(a.log_format, d, jobs)
        p, port, up = serve(a.serve, a.cwd, d)
        if up != "up": probe(name, "refused: " + up[:90].replace("\n", " ")); stop(p); shutil.rmtree(base, ignore_errors=True); continue
        try:
            st, r = req(port, "GET", "/jobs/j_1")
            text = f"{st} state={r.get('state')} tries={r.get('tries')} max_tries={r.get('max_tries')} backoff_ms={r.get('backoff_ms')} run_at={'run_at' in r}" if isinstance(r, dict) and st == 200 else f"{st} {str(r)[:60]}"
        except Exception as e: text = f"read: {type(e).__name__}"
        try:
            st2, l = req(port, "POST", "/queues/q/lease", {"lease_ms": 1000}, token="w"); lease = str(st2)
        except Exception as e: lease = f"{type(e).__name__} (the service stopped answering)"
        time.sleep(0.2)
        probe(name, text + f"; lease -> {lease}" + ("" if p.poll() is None else f"; SERVER EXITED {p.returncode}"))
        stop(p); shutil.rmtree(base, ignore_errors=True)

if __name__ == "__main__": main()
