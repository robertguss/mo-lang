#!/usr/bin/env python3
"""P6 on Mo's change 2 program: crash the queue process from outside while 8 workers create/lease/ack,
through the runtime surface (a binary built with --surface, MO_SURFACE=PORT): POST /send/<queue id> with a
call the API would have refused (lease_ms below the rule), which trips `leased`'s requires inside the queue.
Reads whether the service keeps answering, what it answers, whether the queue comes back, and whether any
acknowledged write is lost. usage: p6-mo.py --binary PATH [--kills 2.0,5.0] [--seconds 9]"""
import argparse, http.client, json, os, subprocess, tempfile, threading, time, socket, signal, sys

def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p

class Client:
    def __init__(self, port, token): self.port, self.token = port, token; self.c = None
    def req(self, method, path, body=None, timeout=5, raw=None):
        try:
            if self.c is None: self.c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=timeout)
            data = raw.encode() if raw is not None else (json.dumps(body).encode() if body is not None else None)
            h = {"authorization": f"Bearer {self.token}"}
            if data is not None and raw is None: h["content-type"] = "application/json"
            self.c.request(method, path, body=data, headers=h)
            r = self.c.getresponse(); b = r.read()
            if r.getheader("connection", "").lower() == "close": self.c.close(); self.c = None
            try: return r.status, (json.loads(b) if b else None)
            except ValueError: return r.status, b.decode(errors="replace")
        except (http.client.HTTPException, OSError) as e:
            self.c = None
            return -1, type(e).__name__

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--binary", default=None)
    ap.add_argument("--cmd", default=None, help="a command with {dir} {port} placeholders, e.g. 'mo run --surface {sport} main.mo -- serve {dir} --port {port}'; for mo run the surface port comes from --surface")
    ap.add_argument("--kills", default="2.0,5.0")
    ap.add_argument("--seconds", type=float, default=9.0)
    ap.add_argument("--message", default='Want(call: Call(worker: "w1", command: Lease(queue: "q0", lease_ms: 5)))')
    a = ap.parse_args()
    kills = [float(k) for k in a.kills.split(",") if k]
    base = tempfile.mkdtemp(prefix="p6mo-"); d = os.path.join(base, "dir"); os.mkdir(d)
    port = free_port(); sport = free_port()
    env = dict(os.environ, MO_SURFACE=str(sport), MO_CORES="1")
    log = open(os.path.join(base, "server.log"), "w")
    def cmd_for(dd, pp, sp):
        if a.cmd: return a.cmd.format(dir=dd, port=pp, sport=sp).split()
        return [a.binary, "serve", dd, "--port", str(pp)]
    proc = subprocess.Popen(cmd_for(d, port, sport), env=env, stdout=log, stderr=subprocess.STDOUT, preexec_fn=os.setsid)
    t0 = time.time()
    while True:
        st, _ = Client(port, "x").req("GET", "/health")
        if st == 200: break
        if time.time() - t0 > 20: raise SystemExit("server did not start")
        time.sleep(0.05)
    surf = Client(sport, "surface")
    st, procs = surf.req("GET", "/processes")
    qid = next(p["id"] for p in procs if p["name"] == "Queue")
    print(f"up in {time.time()-t0:.2f}s on port {port}, surface {sport}; processes {[(p['id'], p['name']) for p in procs]}; queue id {qid}")

    stop = threading.Event(); lock = threading.Lock()
    events = []; created = {}; acked = {}
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
            if st == 200 and b and isinstance(b, dict) and b.get("id"):
                jid = b["id"]
                st2, _ = c.req("POST", f"/jobs/{jid}/ack")
                with lock: events.append((time.time() - start, i, "ack", st2))
                if st2 == 200:
                    with lock: acked[jid] = True
            if st == -1 or st == 503:
                time.sleep(0.01)
    start = time.time()
    ths = [threading.Thread(target=worker, args=(i,), daemon=True) for i in range(8)]
    for t in ths: t.start()

    killlog = []
    h = Client(port, "probe")
    for target in kills:
        while time.time() - start < target: time.sleep(0.01)
        tk = time.time() - start
        sst, out = surf.req("POST", f"/send/{qid}", raw=a.message)
        # time to first /health 200 after the kill, capped
        first = None; last_st = None
        while True:
            st, b = h.req("GET", "/health", timeout=2)
            last_st = (st, b if not isinstance(b, dict) else {k: b[k] for k in list(b)[:2]})
            if st == 200: first = time.time() - start; break
            if time.time() - start - tk > 4: break
            time.sleep(0.005)
        _, procs2 = surf.req("GET", "/processes")
        qrow = next((p for p in procs2 if p["id"] == qid), None) if isinstance(procs2, list) else None
        _, crashes = surf.req("GET", "/crashes?n=2")
        _, evs = surf.req("GET", "/events?n=400")
        evs = [e for e in evs if isinstance(e, dict) and not any(k in ("Updated", "Delivered", "Sent", "Asked", "Answered") for k in e)][-6:] if isinstance(evs, list) else evs
        killlog.append((tk, sst, out, first, last_st, qrow, (crashes, evs)))
    while time.time() - start < a.seconds: time.sleep(0.05)
    stop.set(); time.sleep(0.5)

    print("\nkills through the surface:")
    for tk, sst, out, first, last_st, qrow, crashes in killlog:
        back = f"/health 200 again at {first:5.2f}s ({(first-tk)*1000:6.1f} ms)" if first else f"/health never 200 again within 4 s; last answer {last_st}"
        print(f"  at {tk:5.2f}s: send -> {sst} {str(out)[:80]!r}; {back}")
        print(f"    queue row after: {qrow}")
        print(f"    crashes: {json.dumps(crashes)[:600]}")
    print("\nrequests by second and status:")
    by = {}
    for t, i, op, st in events:
        k = (int(t), st); by[k] = by.get(k, 0) + 1
    for s in sorted({k[0] for k in by}):
        row = {st: n for (ss, st), n in by.items() if ss == s}
        print(f"  {s:2d}s  " + "  ".join(f"{st}:{n}" for st, n in sorted(row.items(), key=lambda kv: str(kv[0]))))
    tot = len(events); bad = sum(1 for e in events if e[3] not in (200, 201))
    print(f"\ntotal requests {tot}, not 200/201: {bad}")
    print(f"created {len(created)}, acked {len(acked)}")
    _, mem = surf.req("GET", "/memory"); print(f"resident after: {mem.get('resident_bytes') if isinstance(mem, dict) else mem}")

    # restart on the same folder: the disk's view of what was acknowledged
    os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    try: proc.wait(timeout=20)
    except subprocess.TimeoutExpired: os.killpg(os.getpgid(proc.pid), signal.SIGKILL); proc.wait()
    print(f"server exit code {proc.returncode}")
    port2 = free_port()
    proc2 = subprocess.Popen(cmd_for(d, port2, free_port()), env=dict(os.environ, MO_CORES="1"), stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT, preexec_fn=os.setsid)
    t1 = time.time()
    while True:
        st, _ = Client(port2, "x").req("GET", "/health")
        if st == 200: break
        if time.time() - t1 > 20: print("restart: the server did not come back in 20 s"); break
        time.sleep(0.05)
    print(f"restarted on the same folder in {time.time()-t1:.2f}s")
    c = Client(port2, "audit"); lost_ack = []; lost_create = []; states = {}
    for jid in list(acked):
        st, b = c.req("GET", f"/jobs/{jid}")
        s = b.get("state") if st == 200 and isinstance(b, dict) else f"http {st}"
        states[s] = states.get(s, 0) + 1
        if s != "done": lost_ack.append((jid, st, s))
    for jid in list(created):
        st, b = c.req("GET", f"/jobs/{jid}")
        if st != 200: lost_create.append((jid, st))
    st, health = c.req("GET", "/health")
    print(f"acked jobs' states on the reopened folder: {states}")
    print(f"acked jobs not done: {len(lost_ack)} {lost_ack[:5]}")
    print(f"created jobs gone: {len(lost_create)} {lost_create[:5]}")
    print(f"health after restart: {health}")
    os.killpg(os.getpgid(proc2.pid), signal.SIGTERM)
    print(f"server log: {os.path.join(base, 'server.log')}")
    print(open(os.path.join(base, "server.log")).read()[-1500:])

main()
