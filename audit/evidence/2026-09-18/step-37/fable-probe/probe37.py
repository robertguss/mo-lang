#!/usr/bin/env python3
"""Fable's probes for step 37: the Mo TLS client against Python's ssl (OpenSSL 3.5.7 here, a
different OpenSSL from the bench's 3.0.13), and Python's ssl client against the Mo TLS server,
under both runtimes. Cases the brief did not name. Run from the repo root:

    python3 probe37.py <mo binary> <scratch dir>
"""
import os, shutil, socket, ssl, subprocess, sys, threading, time

MO = os.path.abspath(sys.argv[1])
SCRATCH = os.path.abspath(sys.argv[2])
REPO = os.path.abspath(os.path.join(os.path.dirname(MO), "..", "..", ".."))
EFFECTS = os.path.join(REPO, "examples", "effects")
TLS = os.path.join(EFFECTS, "tls")
results = []


def say(*a):
    print(*a, flush=True)


def check(name, ok, detail=""):
    results.append((name, ok))
    say(("PASS " if ok else "FAIL ") + name + ("  [" + detail + "]" if detail else ""))


class PyServer(threading.Thread):
    """A Python ssl server: one connection, echo lines back, or a behaviour the case names."""

    def __init__(self, cert, key, behaviour="echo", ctx_tweak=None):
        super().__init__(daemon=True)
        self.sock = socket.socket()
        self.sock.bind(("127.0.0.1", 0))
        self.sock.listen(4)
        self.port = self.sock.getsockname()[1]
        self.behaviour = behaviour
        self.ctx = None
        if cert:
            self.ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            self.ctx.load_cert_chain(cert, key)
            if ctx_tweak:
                ctx_tweak(self.ctx)
        self.error = None
        self.sock.settimeout(20)

    def run(self):
        try:
            conn, _ = self.sock.accept()
            conn.settimeout(15)
            if self.behaviour == "close":
                conn.close()
                return
            tls = self.ctx.wrap_socket(conn, server_side=True)
            if self.behaviour == "hangup":
                tls.close()
                return
            data = b""
            while not data.endswith(b"\n"):
                chunk = tls.recv(4096)
                if not chunk:
                    break
                data += chunk
            if self.behaviour == "echo":
                tls.sendall(data)
            elif self.behaviour == "big":
                tls.sendall(b"x" * 60000 + b"\n")
            time.sleep(0.2)
            tls.close()
        except Exception as e:  # noqa: BLE001
            self.error = repr(e)


def mo_client(cwd, host, port, timeout=30):
    p = subprocess.run(["timeout", str(timeout), MO, "run", "tls-client.mo", "--", host, str(port)],
                       cwd=cwd, capture_output=True, text=True)
    return p.returncode, (p.stdout + p.stderr).strip()


def bin_client(cwd, host, port, timeout=30):
    exe = os.path.join(cwd, "zig-out", "mo-build", "tls-client", "tls-client")
    p = subprocess.run(["timeout", str(timeout), exe, host, str(port)], cwd=cwd,
                       capture_output=True, text=True)
    return p.returncode, (p.stdout + p.stderr).strip()


def with_trust(name, root_file):
    """A copy of examples/effects with tls/root.pem replaced, so main trusts another root."""
    d = os.path.join(SCRATCH, "effects-" + name)
    if os.path.exists(d):
        shutil.rmtree(d)
    shutil.copytree(EFFECTS, d, ignore=shutil.ignore_patterns("zig-out", ".zig-cache"))
    shutil.copy(root_file, os.path.join(d, "tls", "root.pem"))
    return d


def build(cwd):
    p = subprocess.run(["timeout", "600", MO, "build", "tls-client.mo", "-o", "tls-client"],
                       cwd=cwd, capture_output=True, text=True)
    if p.returncode != 0:
        say("build failed in", cwd, p.stdout[-500:], p.stderr[-500:])
    return p.returncode == 0


def case(runtime, run, cwd, name, cert, key, want, behaviour="echo", tweak=None, host="localhost"):
    s = PyServer(os.path.join(TLS, cert) if cert else None, os.path.join(TLS, key) if key else None,
                 behaviour, tweak)
    s.start()
    rc, out = run(cwd, host, s.port)
    s.join(20)
    got = out.splitlines()[-1] if out else ""
    check(f"{runtime}: {name}", got == want or (isinstance(want, tuple) and got in want), f"got {got!r} rc={rc}" + (f" server: {s.error}" if s.error and got != want else ""))


def tls12_only(ctx):
    ctx.maximum_version = ssl.TLSVersion.TLSv1_2


def alpn_h2(ctx):
    ctx.set_alpn_protocols(["h2", "http/1.1"])


def client_cases(runtime, run):
    ed = with_trust("ed", os.path.join(TLS, "root.pem"))
    p256 = with_trust("p256", os.path.join(TLS, "root-p256.pem"))
    other = with_trust("other", os.path.join(TLS, "root-other.pem"))
    sysca = with_trust("sysca", "/etc/ssl/certs/ca-certificates.crt")
    if run is bin_client:
        for d in (ed, p256, other, sysca):
            if not build(d):
                check(f"{runtime}: build in {os.path.basename(d)}", False)
                return
    case(runtime, run, ed, "Python ssl server, Ed25519 chain, a line echoed", "cert.pem", "key.pem", "hello from mo")
    case(runtime, run, p256, "Python ssl server, P-256 chain, trusted by root-p256", "cert-p256.pem", "key-p256.pem", "hello from mo")
    case(runtime, run, ed, "P-256 chain against a client trusting the Ed25519 root: Untrusted", "cert-p256.pem", "key-p256.pem", "Untrusted")
    case(runtime, run, other, "Ed25519 chain against a client trusting the other root: Untrusted", "cert.pem", "key.pem", "Untrusted")
    case(runtime, run, ed, "leaf for example.org: Untrusted", "refuse-host.pem", "refuse-host-key.pem", "Untrusted")
    case(runtime, run, ed, "expired leaf: Untrusted", "refuse-expired.pem", "refuse-expired-key.pem", "Untrusted")
    case(runtime, run, ed, "RSA leaf: the server refuses our signature schemes first, a fatal alert: Handshake", "refuse-rsa.pem", "refuse-rsa-key.pem", "Handshake")
    case(runtime, run, ed, "chain of five accepted", "depth5.pem", "depth5-key.pem", "hello from mo")
    case(runtime, run, ed, "chain of six: Untrusted", "refuse-depth.pem", "refuse-depth-key.pem", "Untrusted")
    case(runtime, run, ed, "leaf signed by a non-CA: Untrusted", "refuse-notca.pem", "refuse-notca-key.pem", "Untrusted")
    case(runtime, run, ed, "connect for 127.0.0.1 (an IP SAN) echoed", "cert.pem", "key.pem", "hello from mo", host="127.0.0.1")
    case(runtime, run, ed, "server speaking TLS 1.2 at most: Handshake", "cert.pem", "key.pem", "Handshake", tweak=tls12_only)
    case(runtime, run, ed, "server with an ALPN list against a client offering none: echoed", "cert.pem", "key.pem", "hello from mo", tweak=alpn_h2)
    case(runtime, run, ed, "server closes before any hello: Closed", "cert.pem", "key.pem", "Closed", behaviour="close")
    case(runtime, run, ed, "server closes right after the handshake without close_notify: Closed on the write, or the end on the read, by timing", "cert.pem", "key.pem", ("Closed", "the server closed"), behaviour="hangup")
    case(runtime, run, ed, "a 60,000-byte line back (four records): read whole", "cert.pem", "key.pem", "x" * 60000, behaviour="big")
    # A real host on the internet, with the system's roots: what program 7's operator would see.
    rc, out = run(sysca, "www.google.com", 443, timeout=40)
    say(f"INFO {runtime}: www.google.com:443 with the system roots -> rc={rc} {out.splitlines()[-1] if out else ''!r}")
    rc, out = run(sysca, "example.com", 443, timeout=40)
    say(f"INFO {runtime}: example.com:443 with the system roots -> rc={rc} {out.splitlines()[-1] if out else ''!r}")


def start_echo(runtime):
    """examples/effects/tls-echo.mo under mo run or as a binary, on a free port."""
    port = 18500 + (0 if runtime == "run" else 1)
    if runtime == "run":
        cmd = [MO, "run", "tls-echo.mo", "--", str(port), "60000"]
    else:
        build_dir = EFFECTS
        p = subprocess.run(["timeout", "600", MO, "build", "tls-echo.mo", "-o", "tls-echo"], cwd=build_dir, capture_output=True, text=True)
        assert p.returncode == 0, p.stderr[-500:]
        cmd = [os.path.join(build_dir, "zig-out", "mo-build", "tls-echo", "tls-echo"), str(port), "60000"]
    proc = subprocess.Popen(cmd, cwd=EFFECTS, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    for _ in range(100):
        try:
            socket.create_connection(("127.0.0.1", port), timeout=0.2).close()
            return proc, port
        except OSError:
            time.sleep(0.1)
    raise SystemExit("echo did not come up")


def py_client(port, alpn=None, host="localhost", trust="root.pem", minver=None, maxver=None):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.load_verify_locations(os.path.join(TLS, trust))
    if alpn:
        ctx.set_alpn_protocols(alpn)
    if minver:
        ctx.minimum_version = minver
    if maxver:
        ctx.maximum_version = maxver
    raw = socket.create_connection(("127.0.0.1", port), timeout=10)
    return ctx.wrap_socket(raw, server_hostname=host)


def server_cases(runtime):
    proc, port = start_echo(runtime)
    try:
        t = py_client(port)
        t.sendall(b"hi there\n")
        got = t.recv(100)
        check(f"{runtime}: Python 3.5.7 client verifies the chain (leaf, intermediate) to root.pem and echoes", got == b"hi there\n", repr(got))
        check(f"{runtime}: the server presented no ALPN to a client offering none", t.selected_alpn_protocol() is None, repr(t.selected_alpn_protocol()))
        check(f"{runtime}: TLS 1.3", t.version() == "TLSv1.3", t.version())
        t.close()
        t = py_client(port, alpn=["h2", "http/1.1"])
        t.sendall(b"alpn\n")
        got = t.recv(100)
        check(f"{runtime}: a client offering h2 against a server with no list: no ALPN, still echoes", got == b"alpn\n" and t.selected_alpn_protocol() is None, f"{got!r} {t.selected_alpn_protocol()!r}")
        t.close()
        try:
            py_client(port, trust="root-other.pem")
            check(f"{runtime}: a client trusting the other root refuses the server", False, "no error")
        except ssl.SSLError as e:
            check(f"{runtime}: a client trusting the other root refuses the server", "CERTIFICATE_VERIFY_FAILED" in str(e), str(e)[:80])
        try:
            py_client(port, host="example.org")
            check(f"{runtime}: a client for example.org refuses the localhost leaf", False, "no error")
        except ssl.SSLError as e:
            check(f"{runtime}: a client for example.org refuses the localhost leaf", "CERTIFICATE_VERIFY_FAILED" in str(e) or "Hostname mismatch" in str(e), str(e)[:80])
        try:
            py_client(port, maxver=ssl.TLSVersion.TLSv1_2)
            check(f"{runtime}: a TLS 1.2-only client is refused", False, "no error")
        except ssl.SSLError as e:
            check(f"{runtime}: a TLS 1.2-only client is refused", True, str(e)[:60])
        t = py_client(port)
        t.sendall(b"still\n")
        got = t.recv(100)
        check(f"{runtime}: the server serves after the refusals", got == b"still\n", repr(got))
        t.close()
        # The chain served equals cert.pem's leaf.
        t = py_client(port)
        der = t.getpeercert(binary_form=True)
        leaf = ssl.PEM_cert_to_DER_cert(open(os.path.join(TLS, "cert.pem")).read().split("-----END CERTIFICATE-----")[0] + "-----END CERTIFICATE-----\n")
        check(f"{runtime}: the leaf served equals tls/cert.pem's first block", der == leaf)
        t.close()
    finally:
        proc.terminate()
        try:
            proc.wait(5)
        except subprocess.TimeoutExpired:
            proc.kill()


def main():
    say("uptime:", subprocess.run(["uptime"], capture_output=True, text=True).stdout.strip())
    say("python ssl:", ssl.OPENSSL_VERSION, " mo:", MO)
    for runtime, run in (("run", mo_client), ("binary", bin_client)):
        client_cases(runtime, run)
        server_cases(runtime)
    ok = sum(1 for _, r in results if r)
    say(f"\n{ok} of {len(results)} passed")
    sys.exit(0 if ok == len(results) else 1)


if __name__ == "__main__":
    main()
