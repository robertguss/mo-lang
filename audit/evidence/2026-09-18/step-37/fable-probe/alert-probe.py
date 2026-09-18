#!/usr/bin/env python3
"""Fable's probe: what TlsClient.connect reports when the server answers the ClientHello with a
fatal alert, closes, or resets. A raw TCP server, no TLS library. Run from the repo root:

    python3 alert-probe.py <mo binary> [<tls-client binary built from examples/effects>]

Expected after the step 37 fix: Handshake, Handshake, Closed, Closed for each runtime.
"""
import os, socket, subprocess, sys, threading, time

MO = os.path.abspath(sys.argv[1])
BIN = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else None
CWD = os.path.join(os.path.dirname(MO), "..", "..", "..", "examples", "effects")


def serve(mode, box):
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    s.listen(1)
    box.append(s.getsockname()[1])
    c, _ = s.accept()
    c.settimeout(5)
    c.recv(4096)  # the ClientHello
    alert = bytes([0x15, 3, 3, 0, 2, 2, 70])  # fatal protocol_version
    if mode == "alert then close":
        c.sendall(alert); time.sleep(0.05); c.close()
    elif mode == "alert, socket kept open":
        c.sendall(alert); time.sleep(3); c.close()
    elif mode == "close only":
        c.close()
    elif mode == "RST":
        c.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, b"\x01\x00\x00\x00\x00\x00\x00\x00"); c.close()
    s.close()


def run(runtime, host, port):
    if runtime == "run":
        cmd = ["timeout", "20", MO, "run", "tls-client.mo", "--", host, str(port)]
    else:
        cmd = ["timeout", "20", BIN, host, str(port)]
    p = subprocess.run(cmd, cwd=CWD, capture_output=True, text=True)
    out = (p.stdout + p.stderr).strip().splitlines()
    return out[-1] if out else "", p.returncode


for runtime in (["run", "binary"] if BIN else ["run"]):
    for mode in ("alert then close", "alert, socket kept open", "close only", "RST"):
        box = []
        t = threading.Thread(target=serve, args=(mode, box), daemon=True)
        t.start()
        while not box:
            time.sleep(0.01)
        got, rc = run(runtime, "localhost", box[0])
        print(f"{runtime}: {mode} -> {got} (rc {rc})", flush=True)
        t.join(6)
