#!/usr/bin/env python3
"""One client for all three jobq implementations: 100k creates with 100-byte payloads, RSS after,
then lease+ack pairs a second with 1 and with 32 workers (keep-alive connections), then RSS again.
usage: measure.py --serve '<cmd> serve {dir} --port {port}' [--cwd DIR] [--jobs 100000]"""
import argparse, http.client, json, os, subprocess, tempfile, threading, time, socket, signal

def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p

class Client:
    def __init__(self, port, token): self.port, self.token = port, token; self.c = None
    def req(self, method, path, body=None):
        for attempt in range(3):
            try:
                if self.c is None: self.c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=30)
                data = json.dumps(body).encode() if body is not None else None
                h = {"authorization": f"Bearer {self.token}"}
                if data is not None: h["content-type"] = "application/json"
                self.c.request(method, path, body=data, headers=h)
                r = self.c.getresponse(); b = r.read()
                if r.getheader("connection", "").lower() == "close": self.c.close(); self.c = None
                return r.status, (json.loads(b) if b else None)
            except (http.client.HTTPException, OSError):
                self.c = None
        raise RuntimeError("request failed three times")

def rss_mib(pid):
    # the server may be a shell wrapper (uv run); take the largest RSS in the process group
    out = subprocess.run(["ps", "-o", "rss=", "--ppid", str(pid)], capture_output=True, text=True).stdout.split()
    own = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True).stdout.split()
    vals = [int(x) for x in out + own if x.strip()]
    # descend one more level
    kids = subprocess.run(["pgrep", "-P", str(pid)], capture_output=True, text=True).stdout.split()
    for k in kids:
        vals += [int(x) for x in subprocess.run(["ps", "-o", "rss=", "--ppid", k], capture_output=True, text=True).stdout.split() if x.strip()]
    return max(vals) / 1024 if vals else 0.0

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--serve", required=True); ap.add_argument("--cwd"); ap.add_argument("--jobs", type=int, default=100000)
    a = ap.parse_args()
    base = tempfile.mkdtemp(prefix="measure-"); d = os.path.join(base, "dir"); os.mkdir(d)
    port = free_port(); cmd = a.serve.format(dir=d, port=port)
    proc = subprocess.Popen(cmd, shell=True, cwd=a.cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, preexec_fn=os.setsid)
    t0 = time.time()
    while True:
        try:
            st, _ = Client(port, "x").req("GET", "/health"); break
        except Exception:
            if time.time() - t0 > 20: raise SystemExit("server did not start")
            time.sleep(0.05)
    print(f"up in {time.time()-t0:.2f}s; rss empty {rss_mib(proc.pid):.1f} MiB")
    payload = "x" * 100
    # creates with 8 producers on keep-alive connections
    t0 = time.time(); per = a.jobs // 8; errs = []
    def producer(i):
        c = Client(port, f"p{i}")
        for k in range(per):
            st, _ = c.req("POST", "/jobs", {"queue": f"q{k % 4}", "payload": payload, "max_tries": 3})
            if st != 201: errs.append(st); return
    ths = [threading.Thread(target=producer, args=(i,)) for i in range(8)]
    [t.start() for t in ths]; [t.join() for t in ths]
    dt = time.time() - t0
    print(f"creates: {per*8} in {dt:.1f}s = {per*8/dt:.0f}/s, errors {errs[:3]}; rss at {per*8} jobs {rss_mib(proc.pid):.1f} MiB")
    # lease+ack pairs, 1 worker, 10 s
    def pairs(nworkers, seconds):
        count = [0]; lock = threading.Lock(); stop = time.time() + seconds; bad = []
        def w(i):
            c = Client(port, f"w{i}"); n = 0
            while time.time() < stop:
                st, j = c.req("POST", f"/queues/q{i % 4}/lease", {"lease_ms": 60000})
                if st == 200:
                    st2, _ = c.req("POST", f"/jobs/{j['id']}/ack")
                    if st2 == 200: n += 1
                    else: bad.append(st2)
                elif st != 204: bad.append(st)
                else: break
            with lock: count[0] += n
        ths = [threading.Thread(target=w, args=(i,)) for i in range(nworkers)]
        t0 = time.time(); [t.start() for t in ths]; [t.join() for t in ths]; dt = time.time() - t0
        return count[0], dt, bad[:3]
    n, dt, bad = pairs(1, 10); print(f"pairs, 1 worker: {n} in {dt:.1f}s = {n/dt:.0f}/s {bad}")
    n, dt, bad = pairs(32, 10); print(f"pairs, 32 workers: {n} in {dt:.1f}s = {n/dt:.0f}/s {bad}")
    print(f"rss after pairs {rss_mib(proc.pid):.1f} MiB")
    # replay: restart and time to /health
    os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    try: proc.wait(timeout=10)
    except subprocess.TimeoutExpired: os.killpg(os.getpgid(proc.pid), signal.SIGKILL); proc.wait()
    size = sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(d) for f in fs)
    proc = subprocess.Popen(cmd, shell=True, cwd=a.cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, preexec_fn=os.setsid)
    t0 = time.time()
    while True:
        try: Client(port, "x").req("GET", "/health"); break
        except Exception:
            if time.time() - t0 > 300: print("restart timed out"); break
            time.sleep(0.05)
    print(f"restart with a {size/1e6:.0f} MB log: {time.time()-t0:.2f}s to /health; rss {rss_mib(proc.pid):.1f} MiB")
    os.killpg(os.getpgid(proc.pid), signal.SIGKILL); proc.wait()
    subprocess.run(["rm", "-rf", base])

if __name__ == "__main__": main()
