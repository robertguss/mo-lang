"""Fable's own conformance probes for step 36's TLS server, cases the brief did not name.
Runs the example echo under `mo run` and as a binary, drives it with openssl s_client and Python's
ssl (both OpenSSL 3.0), and prints one line per case: PASS or FAIL with what was seen."""
import os, socket, ssl, subprocess, sys, threading, time
sys.path.insert(0, '/home/exedev/Projects/mo-lang/toolchain/bench/step36')
import common as c  # noqa: E402

CERT = str(c.CERTS / 'cert.pem')
results = []


def report(name, ok, detail=''):
    results.append(ok)
    print(f"{'PASS' if ok else 'FAIL'} {name} {detail}".rstrip())


def ctx(cafile=CERT):
    x = ssl.create_default_context(cafile=cafile)
    x.check_hostname = False
    x.minimum_version = ssl.TLSVersion.TLSv1_3
    return x


def tls_echo(port, line: bytes, timeout=20, cafile=CERT, suite=None):
    x = ctx(cafile)
    if suite:
        x.set_ciphers('DEFAULT'); x.set_ciphersuites = None
    s = x.wrap_socket(socket.create_connection(('127.0.0.1', port), timeout=timeout), server_hostname='localhost')
    s.sendall(line + b'\n')
    buf = b''
    while not buf.endswith(b'\n'):
        chunk = s.recv(65536)
        if not chunk:
            break
        buf += chunk
    s.close()
    return buf


def s_client(port, stdin: bytes, extra=(), seconds=20, quiet=True):
    argv = [c.OPENSSL, 's_client', '-connect', f'127.0.0.1:{port}', '-CAfile', CERT,
            '-verify_return_error', '-servername', 'localhost', '-no_ign_eof'] + (['-quiet'] if quiet else []) + list(extra)
    p = subprocess.run(argv, input=stdin, capture_output=True, timeout=seconds)
    return p.returncode, p.stdout, p.stderr


def probe(runtime):
    srv = c.start_echo(runtime)
    port = srv.port
    pid = srv.proc.pid
    try:
        # 1. non-ASCII and an empty line
        report(f'{runtime} utf8 line', tls_echo(port, 'héllo ☃ wörld'.encode()) == 'héllo ☃ wörld\n'.encode())
        report(f'{runtime} empty line', tls_echo(port, b'') == b'\n')
        # 2. a 60,000-byte line: four records each way
        big = b'x' * 60000
        got = tls_echo(port, big, timeout=60)
        report(f'{runtime} 60000-byte line', got == big + b'\n', f'got {len(got)} bytes')
        # 3. key update from the client (s_client 'K' command, interactive mode), then a line
        try:
            p = subprocess.Popen([c.OPENSSL, 's_client', '-connect', f'127.0.0.1:{port}', '-CAfile', CERT, '-servername', 'localhost'],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            time.sleep(1.0); p.stdin.write(b'K\n'); p.stdin.flush(); time.sleep(0.5)
            p.stdin.write(b'after-keyupdate\n'); p.stdin.flush(); time.sleep(1.0)
            p.stdin.write(b'Q\n'); p.stdin.flush()
            out, _ = p.communicate(timeout=15)
            report(f'{runtime} KeyUpdate then a line', b'KEYUPDATE' in out and b'after-keyupdate' in out, f"keyupdate={b'KEYUPDATE' in out} echoed={b'after-keyupdate' in out}")
        except Exception as e:  # noqa: BLE001
            p.kill(); report(f'{runtime} KeyUpdate then a line', False, str(e))
        # 4. a client offering only a suite the cut leaves out
        rc, out, err = s_client(port, b'x\n', extra=['-ciphersuites', 'TLS_AES_256_GCM_SHA384'])
        report(f'{runtime} only AES-256-GCM offered -> refused', rc != 0 and b'handshake failure' in err.lower().replace(b'_', b' '), err.decode(errors='replace').strip().splitlines()[-1][:90] if err else 'no stderr')
        report(f'{runtime} still serving after the refusal', tls_echo(port, b'alive') == b'alive\n')
        # 5. fifty concurrent handshakes, each echoing its own line
        outs = [None] * 50
        def one(i):
            try:
                outs[i] = tls_echo(port, f'conn-{i}'.encode(), timeout=60)
            except Exception as e:  # noqa: BLE001
                outs[i] = repr(e).encode()
        ts = [threading.Thread(target=one, args=(i,)) for i in range(50)]
        [t.start() for t in ts]; [t.join() for t in ts]
        good = sum(1 for i, o in enumerate(outs) if o == f'conn-{i}\n'.encode())
        report(f'{runtime} 50 concurrent handshakes', good == 50, f'{good}/50 echoed')
        # 6. the certificate served is the file's
        der = ssl.PEM_cert_to_DER_cert(open(CERT).read())
        x = ctx(); s = x.wrap_socket(socket.create_connection(('127.0.0.1', port), timeout=20), server_hostname='localhost')
        served = s.getpeercert(binary_form=True); s.close()
        report(f'{runtime} served certificate equals cert.pem', served == der)
        # 7. a client trusting the other pair's certificate refuses this server
        try:
            tls_echo(port, b'x', cafile=str(c.CERTS / 'cert-p256.pem')); report(f'{runtime} wrong CA refused by client', False, 'client accepted')
        except ssl.SSLError as e:
            report(f'{runtime} wrong CA refused by client', 'CERTIFICATE_VERIFY_FAILED' in str(e), str(e)[:70])
        # 8. a client that drops the socket mid-line with no close_notify; the server serves on
        x = ctx(); s = x.wrap_socket(socket.create_connection(('127.0.0.1', port), timeout=20), server_hostname='localhost')
        s.sendall(b'half a line with no newline'); os.close(s.detach())
        report(f'{runtime} still serving after a dropped socket', tls_echo(port, b'after-drop') == b'after-drop\n')
        # 9. memory after 200 connections opened and closed
        before = c.rss_of(pid) // 1024
        for i in range(200):
            tls_echo(port, b'm')
        time.sleep(1.5)
        after = c.rss_of(pid) // 1024
        report(f'{runtime} resident memory after 200 connections', after - before < 8192, f'{before} -> {after} KiB (+{after-before})')
    finally:
        srv.stop() if hasattr(srv, 'stop') else srv.proc.kill()


if __name__ == '__main__':
    for rt in sys.argv[1:] or ['run', 'binary']:
        probe(rt)
    print(f'{sum(results)}/{len(results)} passed')
