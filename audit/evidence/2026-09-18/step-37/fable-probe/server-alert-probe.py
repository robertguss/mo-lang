#!/usr/bin/env python3
"""Fable's probe: the Mo TLS server (examples/effects/tls-echo.mo) when a client refuses its chain
and sends a fatal alert (unknown_ca) after the server's flight, then another client connects.
Python's ssl (OpenSSL 3.5.7 here) is the client. Run from examples/effects:

    python3 server-alert-probe.py <mo binary> <tls-echo binary>

Expected: both runtimes echo good1, good2, good3 and stay alive (before the step 37 fix the
binary died with SIGSEGV after the first alert).
"""
import socket, ssl, subprocess, sys, time

MO, BIN = sys.argv[1], sys.argv[2]


def client(port, trust="root.pem", host="localhost"):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.load_verify_locations("tls/" + trust)
    raw = socket.create_connection(("127.0.0.1", port), timeout=5)
    t = ctx.wrap_socket(raw, server_hostname=host)
    t.sendall(b"ok\n")
    r = t.recv(100)
    t.close()
    return r


ok = True
for name, cmd in (("binary", [BIN, "18601", "60000"]), ("run", [MO, "run", "tls-echo.mo", "--", "18602", "60000"])):
    port = int(cmd[-2])
    p = subprocess.Popen(["timeout", "40"] + cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    for _ in range(100):
        try:
            socket.create_connection(("127.0.0.1", port), timeout=0.2).close()
            break
        except OSError:
            time.sleep(0.1)
    steps = []
    steps.append(("good1", client(port)))
    try:
        client(port, trust="root-other.pem")
        steps.append(("other root", "no error"))
    except Exception as e:  # noqa: BLE001
        steps.append(("other root", str(e)[:50]))
    time.sleep(0.5)
    for label, kw in (("good2", {}), ("wrong host", {"host": "example.org"}), ("good3", {})):
        try:
            steps.append((label, client(port, **kw)))
        except Exception as e:  # noqa: BLE001
            steps.append((label, str(e)[:50]))
        time.sleep(0.3)
    alive = p.poll() is None
    p.terminate()
    try:
        out, _ = p.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        p.kill()
        out, _ = p.communicate()
    good = alive and all(v == b"ok\n" for k, v in steps if k.startswith("good"))
    ok = ok and good
    print(("PASS " if good else "FAIL ") + name, steps, "alive:", alive, "rc:", p.returncode, flush=True)
sys.exit(0 if ok else 1)
