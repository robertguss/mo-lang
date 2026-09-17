import http.client, json, os, signal, socket, subprocess, sys, tempfile, threading, time
MO = sys.argv[1]; SECS = float(sys.argv[2]); FOLDER = sys.argv[3] if len(sys.argv) > 3 else tempfile.mkdtemp(prefix="reopen-")
J = os.environ.get("JOBQ_DIR", "../mo-lang-erosion3-mo/examples/programs/jobq")
G = os.path.join(os.path.dirname(os.path.abspath(__file__)), "guard.py")
def port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p
def start(folder):
    p = port()
    proc = subprocess.Popen(["python3", G, "300", "--", MO, "run", J + "/main.mo", "--", "serve", folder, "--port", str(p)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    t0 = time.time()
    while time.time() - t0 < 60:
        if proc.poll() is not None: return proc, p, time.time() - t0
        try:
            c = http.client.HTTPConnection("127.0.0.1", p, timeout=5); c.request("GET", "/health"); r = c.getresponse(); r.read()
            if r.status == 200: return proc, p, time.time() - t0
        except OSError: time.sleep(0.02)
    return proc, p, None
proc, p, took = start(FOLDER); print("first up", took)
stop = threading.Event(); n = [0]
def worker(i):
    c = None
    while not stop.is_set():
        try:
            if c is None: c = http.client.HTTPConnection("127.0.0.1", p, timeout=10)
            c.request("POST", "/jobs", body=json.dumps({"queue": f"u{i%4}", "payload": "p"*100, "max_tries": 3}), headers={"authorization": f"Bearer w{i}"})
            r = c.getresponse(); r.read(); n[0] += 1
            if r.getheader("connection", "").lower() == "close": c.close(); c = None
        except Exception: c = None
ths = [threading.Thread(target=worker, args=(i,)) for i in range(8)]
[t.start() for t in ths]; time.sleep(SECS); stop.set(); [t.join() for t in ths]
print("creates", n[0]); proc.send_signal(signal.SIGTERM); proc.wait()
proc, p, took = start(FOLDER); print("second up", took, "exit", proc.poll())
if proc.poll() is not None: print(proc.stdout.read()[:3000])
else: proc.send_signal(signal.SIGTERM); proc.wait()
print("folder", FOLDER)
