#!/usr/bin/env python3
"""nums.py SP REPO ROUNDS ROW...: step 24's numbers, before and after interleaved, best of ROUNDS.

SP is a scratch folder outside the repository and REPO the repository root. SP/before/toolchain is
the toolchain at the step's first commit (git archive 195dd88), built; SP/nums/before and
SP/nums/after each hold kv, httpd, jobq, and agent (verified: lines stripped, mo.root at the tree),
built with that tree's mo into zig-out/mo-build; SP/load/jqload is bench/step23/jqload.c compiled.
Rows: kv (kv-10k-get), kv-c, http (http-1k), http-c, jobq (32 workers, pairs a second), agent
(32 concurrent five-step runs, runs a second). Every server runs under a timeout and is killed after.
"""
import json, os, shutil, signal, socket, subprocess, sys, time

SP, REPO = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
NUMS = f"{SP}/nums"
MO = {"before": f"{SP}/before/toolchain/zig-out/bin/mo", "after": f"{REPO}/toolchain/zig-out/bin/mo"}
AGENT_BENCH = f"{REPO}/examples/programs/agent/measure/bench.py"


def binary(tree, prog):
    return f"{NUMS}/{tree}/{prog}/zig-out/mo-build/{prog}/{prog}"


def interp(tree, prog):
    return [MO[tree], "run", f"{NUMS}/{tree}/{prog}/main.mo", "--"]


def wait_port(port, t=60):
    t0 = time.time()
    while time.time() - t0 < t:
        try:
            socket.create_connection(("127.0.0.1", port), timeout=1).close()
            return True
        except OSError:
            time.sleep(0.05)
    return False


def start(argv):
    return subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def stop(p):
    try:
        os.killpg(p.pid, signal.SIGTERM)
        p.wait(timeout=10)
    except Exception:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except Exception:
            pass
        p.wait()


def kv(tree, compiled):
    data = f"{SP}/d/kv-{tree}"
    shutil.rmtree(data, ignore_errors=True)
    os.makedirs(data)
    open(f"{data}/kv.log", "w").write("SET greeting hello wide world\n")
    port = 7991
    argv = ([binary(tree, "kv")] if compiled else interp(tree, "kv")) + ["serve", data, "--port", str(port)]
    p = start(argv)
    try:
        assert wait_port(port), "kv did not listen"
        s = socket.create_connection(("127.0.0.1", port))
        f = s.makefile("rb")
        for _ in range(500):
            s.sendall(b"GET greeting\n")
            f.readline()
        t0 = time.perf_counter()
        for _ in range(10_000):
            s.sendall(b"GET greeting\n")
            f.readline()
        ms = (time.perf_counter() - t0) * 1000
        s.close()
        return ms
    finally:
        stop(p)


REQUEST = b"GET /hello?name=bench HTTP/1.1\r\nhost: 127.0.0.1\r\n\r\n"


def http(tree, compiled):
    port = 7992
    argv = ([binary(tree, "httpd")] if compiled else interp(tree, "httpd")) + ["serve", "--port", str(port)]
    p = start(argv)
    try:
        assert wait_port(port), "httpd did not listen"
        best = None
        t0 = time.perf_counter()
        for _ in range(1000):
            s = socket.create_connection(("127.0.0.1", port))
            s.sendall(REQUEST)
            got = b""
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                got += chunk
            s.close()
            assert b"200" in got.split(b"\r\n", 1)[0], got[:80]
        return (time.perf_counter() - t0) * 1000
    finally:
        stop(p)


def jobq(tree, _compiled):
    data = f"{SP}/d/jobq-{tree}"
    shutil.rmtree(data, ignore_errors=True)
    shutil.copytree(f"{NUMS}/{tree}/jobq/data/demo", data)
    port = 7993
    p = start([binary(tree, "jobq"), "serve", data, "--port", str(port)])
    try:
        assert wait_port(port), "jobq did not listen"
        out = subprocess.run([f"{SP}/load/jqload", str(port), "32", "8", "50000"], capture_output=True, text=True, timeout=300)
        return float(out.stdout.split("pairs_per_s ")[1].split()[0])
    finally:
        stop(p)


def agent(tree, _compiled):
    work = f"{SP}/d/agent-{tree}"
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(f"{work}/svc/work")
    open(f"{work}/svc/work/readme.txt", "w").write("bench\n")
    now = '{"tool": "now", "tokens": 10}'
    open(f"{work}/five.txt", "w").write("\n".join([now] * 4 + ['{"done": "five steps", "tokens": 10}']) + "\n")
    base = 7994
    a = binary(tree, "agent")
    mock = start([a, "mock", f"{work}/five.txt", "--port", str(base + 1)])
    serve = None
    try:
        assert wait_port(base + 1), "mock did not listen"
        serve = start([a, "serve", f"{work}/svc", "--model", f"127.0.0.1:{base + 1}", "--port", str(base)])
        assert wait_port(base), "agent serve did not listen"
        out = subprocess.run(["python3", AGENT_BENCH, "rate", str(base), "32", "20", "now"], capture_output=True, text=True, timeout=300)
        return json.loads(out.stdout)["runs_per_second"]
    finally:
        if serve:
            stop(serve)
        stop(mock)


ROWS = {"kv": (kv, False, "ms", min), "kv-c": (kv, True, "ms", min), "http": (http, False, "ms", min),
        "http-c": (http, True, "ms", min), "jobq": (jobq, True, "pairs/s", max), "agent": (agent, True, "runs/s", max)}

rounds = int(sys.argv[3])
for row in sys.argv[4:]:
    fn, compiled, unit, pick = ROWS[row]
    got = {"before": [], "after": []}
    for r in range(rounds):
        for tree in ("before", "after"):
            v = fn(tree, compiled)
            got[tree].append(v)
            print(f"{row} round {r} {tree}: {v:.1f} {unit}", flush=True)
    b, a = pick(got["before"]), pick(got["after"])
    change = (a - b) / b * 100 if unit == "ms" else (b - a) / b * 100
    print(f"{row} best: before {b:.1f} {unit}, after {a:.1f} {unit}; {change:+.1f}% slower", flush=True)
