#!/usr/bin/env python3
"""P6 on Elixir: kill the queue GenServer from outside while 8 workers create/lease/ack,
read whether the supervisor restores service, and whether any acknowledged write is lost.
usage: p6-elixir.py --escript-dir DIR [--kills queue,queue,store] [--seconds 9]"""
import argparse, http.client, json, os, subprocess, tempfile, threading, time, socket, signal, sys

NODE = "jobq@" + subprocess.run(["hostname", "-s"], capture_output=True, text=True).stdout.strip()
COOKIE = "p6"

def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p

class Client:
    def __init__(self, port, token): self.port, self.token = port, token; self.c = None
    def req(self, method, path, body=None, timeout=5):
        try:
            if self.c is None: self.c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=timeout)
            data = json.dumps(body).encode() if body is not None else None
            h = {"authorization": f"Bearer {self.token}"}
            if data is not None: h["content-type"] = "application/json"
            self.c.request(method, path, body=data, headers=h)
            r = self.c.getresponse(); b = r.read()
            if r.getheader("connection", "").lower() == "close": self.c.close(); self.c = None
            return r.status, (json.loads(b) if b else None)
        except (http.client.HTTPException, OSError) as e:
            self.c = None
            return -1, type(e).__name__

def rpc(expr):
    """Run an Elixir expression on the server node from a second node."""
    code = f'IO.inspect(:rpc.call(:"{NODE}", :erlang, :apply, [fn -> {expr} end, []]))'
    r = subprocess.run(["elixir", "--sname", f"probe{os.getpid()}", "--cookie", COOKIE, "-e", code],
                       capture_output=True, text=True, timeout=30)
    return (r.stdout + r.stderr).strip()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--escript-dir", required=True)
    ap.add_argument("--kills", default="queue,queue,store")
    ap.add_argument("--seconds", type=float, default=9.0)
    ap.add_argument("--spacing", type=float, default=3.0)
    a = ap.parse_args()
    kills = [k for k in a.kills.split(",") if k]
    base = tempfile.mkdtemp(prefix="p6-"); d = os.path.join(base, "dir"); os.mkdir(d)
    port = free_port()
    env = dict(os.environ, ERL_FLAGS=f"-sname jobq -setcookie {COOKIE}")
    proc = subprocess.Popen(["./jobq", "serve", d, "--port", str(port)], cwd=a.escript_dir, env=env,
                            stdout=open(os.path.join(base, "server.log"), "w"), stderr=subprocess.STDOUT, preexec_fn=os.setsid)
    t0 = time.time()
    while True:
        st, _ = Client(port, "x").req("GET", "/health")
        if st == 200: break
        if time.time() - t0 > 20: raise SystemExit("server did not start")
        time.sleep(0.05)
    print(f"up in {time.time()-t0:.2f}s on port {port}, node {NODE}; ping -> {rpc('Node.self()')}")
    qpid = rpc("Jobq.Registry.whereis(:default, :queue)")
    print(f"queue pid before: {qpid}")

    stop = threading.Event(); lock = threading.Lock()
    events = []      # (t, worker, op, status)
    created = {}     # id -> True
    acked = {}       # id -> True
    def worker(i):
        c = Client(port, f"w{i}"); q = f"q{i % 4}"
        while not stop.is_set():
            t = time.time() - start
            st, b = c.req("POST", "/jobs", {"queue": q, "payload": "p", "max_tries": 3})
            with lock: events.append((t, i, "create", st))
            if st == 201:
                with lock: created[b["id"]] = True
            st, b = c.req("POST", f"/queues/{q}/lease", {"lease_ms": 30000})
            with lock: events.append((time.time() - start, i, "lease", st))
            if st == 200 and b and b.get("id"):
                jid = b["id"]
                st2, _ = c.req("POST", f"/jobs/{jid}/ack")
                with lock: events.append((time.time() - start, i, "ack", st2))
                if st2 == 200:
                    with lock: acked[jid] = True
            if st == -1:
                time.sleep(0.01)
    start = time.time()
    ths = [threading.Thread(target=worker, args=(i,), daemon=True) for i in range(8)]
    for t in ths: t.start()

    killlog = []
    h = Client(port, "probe")
    for n, role in enumerate(kills):
        target = a.spacing * (n + 1) - 1.5
        while time.time() - start < target: time.sleep(0.01)
        pid_before = rpc(f"Jobq.Registry.whereis(:default, :{role})")
        tk = time.time() - start
        out = rpc(f"Process.exit(Jobq.Registry.whereis(:default, :{role}), :kill)")
        # time to first healthy answer after the kill
        while True:
            st, b = h.req("GET", "/health", timeout=2)
            if st == 200: break
            if time.time() - start - tk > 6: break
            time.sleep(0.005)
        tr = time.time() - start
        pid_after = rpc(f"Jobq.Registry.whereis(:default, :{role})")
        killlog.append((role, tk, tr, out, pid_before, pid_after, st))
    while time.time() - start < a.seconds: time.sleep(0.05)
    stop.set(); time.sleep(0.5)

    # what survived: every acked job is acked, every created job exists
    c = Client(port, "audit")
    lost_ack, lost_create, states = [], [], {}
    for jid in list(acked):
        st, b = c.req("GET", f"/jobs/{jid}")
        s = b.get("state") if st == 200 and isinstance(b, dict) else f"http {st}"
        states[s] = states.get(s, 0) + 1
        if st != 200 or b.get("state") not in ("acked", "done"): lost_ack.append((jid, st, s))
    for jid in list(created):
        st, b = c.req("GET", f"/jobs/{jid}")
        if st != 200: lost_create.append((jid, st))
    st, health = c.req("GET", "/health")

    print("\nkills:")
    for role, tk, tr, out, pb, pa, st in killlog:
        print(f"  {role:6s} at {tk:5.2f}s, /health 200 again at {tr:5.2f}s ({(tr-tk)*1000:6.1f} ms); pid {pb} -> {pa}; exit -> {out[:40]!r}")
    print("\nrequests by second and status:")
    by = {}
    for t, i, op, st in events:
        k = (int(t), st); by[k] = by.get(k, 0) + 1
    secs = sorted({k[0] for k in by})
    for s in secs:
        row = {st: n for (ss, st), n in by.items() if ss == s}
        print(f"  {s:2d}s  " + "  ".join(f"{st}:{n}" for st, n in sorted(row.items(), key=lambda kv: str(kv[0]))))
    tot = len(events); bad = sum(1 for e in events if e[3] not in (200, 201))
    print(f"\ntotal requests {tot}, not 200/201: {bad}")
    print(f"created {len(created)}, acked {len(acked)}; acked jobs' states now: {states}")
    print(f"acked jobs no longer acked: {len(lost_ack)} {lost_ack[:5]}")
    print(f"created jobs gone: {len(lost_create)} {lost_create[:5]}")
    print(f"health: {health}")

    # restart on the same folder: the disk's view
    os.killpg(os.getpgid(proc.pid), signal.SIGTERM); proc.wait(timeout=20)
    port2 = free_port()
    proc2 = subprocess.Popen(["./jobq", "serve", d, "--port", str(port2)], cwd=a.escript_dir,
                             stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT, preexec_fn=os.setsid)
    t0 = time.time()
    while True:
        st, _ = Client(port2, "x").req("GET", "/health")
        if st == 200 or time.time() - t0 > 30: break
        time.sleep(0.05)
    c = Client(port2, "audit"); lost2 = 0
    for jid in list(acked):
        st, b = c.req("GET", f"/jobs/{jid}")
        if st != 200 or b.get("state") not in ("acked", "done"): lost2 += 1
    st, health2 = c.req("GET", "/health")
    print(f"\nafter a restart on the same folder ({time.time()-t0:.2f}s): acked jobs not acked {lost2}; health {health2}")
    os.killpg(os.getpgid(proc2.pid), signal.SIGTERM); proc2.wait(timeout=20)
    print(f"\nserver log: {os.path.join(base, 'server.log')}")
    with open(os.path.join(base, "server.log")) as f:
        log = f.read()
    print(f"server log lines: {log.count(chr(10))}; first 15 lines:\n" + "\n".join(log.splitlines()[:15]))

if __name__ == "__main__":
    main()
