#!/usr/bin/env python3
"""Fable's step 38 probe, the server's shape, second version (the first is in first-attempt/ with what was wrong with it).
One thread, a non-blocking TLS socket: the client pipelines N numbered lines at examples/effects/tls-echo.mo as fast as the
socket takes them and reads nothing for `hold` seconds, so the server's writes block on a peer that is not reading while its
reader must keep going; then it reads and writes together. Every echoed byte and the order are checked.
usage: pipeline_probe.py <server cmd...>   (run from examples/effects; the server gets `<port> 50000`: a 50 s listener idle)
Python's ssl is the client (OpenSSL, a different TLS from the brick's). Exit 1 if any case fails."""
import os, select, socket, ssl, subprocess, sys, time
GUARD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../../../toolchain/bench/step36/guard.py")
def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p
def case(cmd, cores, n, size, hold):
    port = free_port(); env = dict(os.environ, MO_CORES=str(cores))
    srv = subprocess.Popen(["python3", GUARD, "300", "--"] + cmd + [str(port), "50000"], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        for _ in range(200):
            try: socket.create_connection(("127.0.0.1", port), timeout=0.2).close(); break
            except OSError: time.sleep(0.1)
        ctx = ssl.create_default_context(cafile="tls/cert.pem"); raw = socket.create_connection(("127.0.0.1", port), timeout=60)
        c = ctx.wrap_socket(raw, server_hostname="localhost"); c.setblocking(False)
        want = b"".join((f"{i:08d}:" + "x" * (size - 10) + "\n").encode() for i in range(n)); off = 0; got = bytearray(); note = None; t0 = time.time(); held_at = None
        while len(got) < len(want) and time.time() - t0 < 120:
            if srv.poll() is not None: note = f"the server exited {srv.poll()}"; break
            try:
                if off < len(want): off += c.send(want[off:off + 65536])
            except (ssl.SSLWantWriteError, ssl.SSLWantReadError, BlockingIOError): pass
            except Exception as e: note = f"send {type(e).__name__}: {e}"; break
            if time.time() - t0 >= hold:
                if held_at is None: held_at = off
                try:
                    while True:
                        b = c.recv(1 << 16)
                        if not b: note = "the stream ended"; break
                        got += b
                except (ssl.SSLWantReadError, ssl.SSLWantWriteError, BlockingIOError): pass
                except Exception as e: note = f"recv {type(e).__name__}: {e}"; break
                if note: break
            select.select([c], [c] if off < len(want) else [], [], 0.02)
        took = time.time() - t0; ok = bytes(got) == want and note is None
        bad = next((i for i in range(min(len(got), len(want))) if got[i] != want[i]), None)
        alive = srv.poll() is None
        rss = subprocess.run(["ps", "-o", "rss=", "-p", str(srv.pid)], capture_output=True, text=True).stdout.strip()
        kids = subprocess.run(["pgrep", "-P", str(srv.pid)], capture_output=True, text=True).stdout.split()
        krss = [subprocess.run(["ps", "-o", "rss=", "-p", k], capture_output=True, text=True).stdout.strip() for k in kids]
        print(f"{'ok  ' if ok and alive else 'FAIL'} cores={cores} n={n} size={size} hold={hold}s: sent {off} of {len(want)} ({held_at} before the first read), echoed {len(got)}, {took:.2f}s, first wrong byte {bad}, note {note}, server alive {alive}, server rss KiB {krss}", flush=True)
        try: c.close()
        except Exception: pass
        return ok and alive
    finally:
        if srv.poll() is None: srv.terminate()
        try: out, err = srv.communicate(timeout=10)
        except Exception: srv.kill(); out, err = b"", b""
        if err.strip(): print("   server stderr:", err.decode()[-400:], flush=True)
def main():
    cmd = sys.argv[1:]; print(f"# {time.strftime('%Y-%m-%d %H:%M:%S %Z')} load {os.getloadavg()} server: {' '.join(cmd)}", flush=True)
    res = [case(cmd, cores, n, size, hold) for cores in (1, 14) for (n, size, hold) in ((1600, 4096, 0), (20000, 1024, 0), (20000, 1024, 3), (100000, 256, 3))]
    print(f"# {sum(res)} of {len(res)} cases"); sys.exit(0 if all(res) else 1)
main()
