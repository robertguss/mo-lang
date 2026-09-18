#!/usr/bin/env python3
"""Fable's step 38 probe, the server's shape: a TLS client pipelines N numbered lines at examples/effects/tls-echo.mo from one
thread while another thread reads the echoes on the same connection, the reader starting `hold` seconds late so the server's
writes block on a peer that is not reading while its own reader must keep going. Every echoed byte and the order are checked.
usage: pipeline_probe.py <server cmd...>   (run from examples/effects; the server takes the port as its last argument)
Prints one line per case; exit 1 if any case fails. Python's ssl is the client (a different TLS from the brick's)."""
import os, socket, ssl, subprocess, sys, threading, time
GUARD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../../../toolchain/bench/step36/guard.py")
def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p
def case(cmd, cores, n, size, hold):
    port = free_port(); env = dict(os.environ, MO_CORES=str(cores))
    srv = subprocess.Popen(["python3", GUARD, "300", "--"] + cmd + [str(port)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        for _ in range(200):
            try: socket.create_connection(("127.0.0.1", port), timeout=0.2).close(); break
            except OSError: time.sleep(0.1)
        ctx = ssl.create_default_context(cafile="tls/cert.pem"); raw = socket.create_connection(("127.0.0.1", port), timeout=60)
        c = ctx.wrap_socket(raw, server_hostname="localhost"); c.settimeout(60)
        lines = [(f"{i:08d}:" + "x" * (size - 10) + "\n").encode() for i in range(n)]
        sent = {"n": 0, "err": None}; t0 = time.time()
        def writer():
            try:
                for i in range(0, n, 64): c.sendall(b"".join(lines[i:i + 64])); sent["n"] = min(n, i + 64)
            except Exception as e: sent["err"] = f"{type(e).__name__}: {e}"
        w = threading.Thread(target=writer, daemon=True); w.start(); time.sleep(hold)
        blocked_at = sent["n"]; want = b"".join(lines); got = bytearray(); err = None
        try:
            while len(got) < len(want):
                b = c.recv(1 << 16)
                if not b: break
                got += b
        except Exception as e: err = f"{type(e).__name__}: {e}"
        w.join(30); took = time.time() - t0
        ok = bytes(got) == want and sent["err"] is None and err is None
        first_bad = next((i for i in range(min(len(got), len(want))) if got[i] != want[i]), None)
        alive = srv.poll() is None
        print(f"{'ok  ' if ok and alive else 'FAIL'} cores={cores} n={n} size={size} hold={hold}s: sent {sent['n']} (writer had sent {blocked_at} when the reader began), echoed {len(got)} of {len(want)} bytes in {took:.2f}s, first wrong byte {first_bad}, writer error {sent['err']}, reader error {err}, server alive {alive}", flush=True)
        try: c.close()
        except Exception: pass
        return ok and alive
    finally:
        srv.terminate()
        try: srv.wait(5)
        except Exception: srv.kill()
def main():
    cmd = sys.argv[1:]; print(f"# {time.strftime('%Y-%m-%d %H:%M:%S %Z')} load {os.getloadavg()} server: {' '.join(cmd)}", flush=True)
    res = [case(cmd, cores, n, size, hold) for cores in (1, 14) for (n, size, hold) in ((1600, 4096, 0), (20000, 1024, 0), (20000, 1024, 3), (100000, 256, 3))]
    print(f"# {sum(res)} of {len(res)} cases"); sys.exit(0 if all(res) else 1)
main()
