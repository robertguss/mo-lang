"""diff.py --seed S [--sessions 1000]: the differential run the bricks page names, the TLS brick
against OpenSSL 3.0, one session at a time.

Each session draws its parameters from the seed: the role (the brick's server against
`openssl s_client`, or the brick's client against `openssl s_server`, about half each); the key
type; the OpenSSL client's suites (order and subset) or the OpenSSL server's; the OpenSSL side's
groups in either role, `P-256:X25519` among them for the HelloRetryRequest; an ALPN list on each
side or none; SNI on or off; a chain from gen.sh's fixture set or gen-constrained.sh's (step 39),
good or one of the refusals; the sizes of an echo exchange's writes, 0 to 20,000 bytes in all; a
KeyUpdate from OpenSSL (`K` on its stdin) or from the brick (`mo_tls_key_update`, asking for an
answer or not), or none; and who closes first.

The brick's side is `mo-tls-peer` (bench/step37/peer.zig: the brick's exports over a real socket,
as the runtimes drive them), which prints what the engine saw. OpenSSL's side is read from its
`-msg` log (every handshake message and alert, each way, with its bytes), its `-brief` summary
or its connection report, and what it echoed. For each session the facts are compared three
ways, the brick's view, OpenSSL's view, and what the parameters say should happen:

  handshake  whether it completed          suite     the one agreed
  alpn       the protocol agreed, or none  bytes     the echo came back whole
  alert      the alert that ended a failed handshake, and who sent it
  keyupdate  a KeyUpdate injected was sent by one side, read by the other, and answered when asked
  close      each side's close_notify, as the other saw it

A session where any two disagree is a mismatch; the count is the result (expected 0), and the
script exits 1 when it is not. Every session's parameters and both views are one line of
`work/diff-<seed>.log`, which begins with the date and `uptime`. Every process runs under guard.py.
"""

from __future__ import annotations

import argparse
import json
import random
import subprocess
import threading
import time
from dataclasses import asdict, dataclass

import common37 as c

# The echo's bytes: no command letter of s_client's (Q R K k) or s_server's (q Q r R k K c L P S s
# B) can open a read, and no letter or digit of what s_server prints between data (`Read BLOCK`,
# `SSL_do_handshake -> 1`, `DONE`, `shutting down SSL`) is one of them.
ALPHABET = "23456789bfjlmpvxyz"
NAMES = ["mo/1", "echo/1", "h2", "http/1.1"]

# Each chain: the chain and key files (gen.sh's, and gen-constrained.sh's `c-` chains of step 39),
# the trust file, the host the client names, and the alert each verifier sends (None: accepted):
# OpenSSL's `s_client` when it checks the brick's server, and the brick's client when it checks
# `s_server`. The two differ where the brick is stricter or names the refusal differently (step 39,
# part A): an unknown critical extension is OpenSSL's certificate_unknown (46) and the brick's
# unsupported_certificate (43); name constraints the leaf meets OpenSSL checks and accepts, and the
# brick refuses as unsupported (43). OpenSSL's column is what OpenSSL does. RSA is the brick's
# client's refusal alone: no brick server signs with RSA.
CHAINS = {
    "good": ("cert", "key", "root", "localhost", None, None),
    "depth5": ("depth5", "depth5-key", "root", "localhost", None, None),
    "host": ("refuse-host", "refuse-host-key", "root", "localhost", 42, 42),
    "name": ("cert", "key", "root", "example.org", 42, 42),
    "expired": ("refuse-expired", "refuse-expired-key", "root", "localhost", 45, 45),
    "link": ("refuse-link", "key", "root", "localhost", 48, 48),
    "depth6": ("refuse-depth", "refuse-depth-key", "root", "localhost", 48, 48),
    "notca": ("refuse-notca", "refuse-notca-key", "root", "localhost", 48, 48),
    "other-root": ("cert", "key", "root-other", "localhost", 48, 48),
    "rsa": ("refuse-rsa", "refuse-rsa-key", "root", "localhost", "rsa", "rsa"),
    "c-limit": ("c-limit", "c-limit-key", "c-root", "localhost", None, None),
    "c-pathlen": ("c-refuse-pathlen", "c-refuse-pathlen-key", "c-root", "localhost", 48, 48),
    "c-pathlen1": ("c-refuse-pathlen1", "c-refuse-pathlen1-key", "c-root", "localhost", 48, 48),
    "c-keyusage": ("c-refuse-keyusage", "c-refuse-keyusage-key", "c-root", "localhost", 48, 48),
    "c-eku": ("c-refuse-eku", "c-refuse-eku-key", "c-root", "localhost", 43, 43),
    "c-critical": ("c-refuse-critical", "c-refuse-critical-key", "c-root", "localhost", 46, 43),
    "c-names": ("c-refuse-names", "c-refuse-names-key", "c-root", "localhost", None, 43),
}


@dataclass
class Params:
    n: int
    role: str
    key: str
    chain: str
    sni: bool
    suites: list[str]
    groups: str
    client_alpn: list[str]
    server_alpn: list[str]
    sizes: list[int]
    keyupdate: str
    closer: str


def draw(rng: random.Random, n: int) -> Params:
    role = rng.choice(["mo-server", "mo-client"])
    key = rng.choice(["ed25519", "p256"])
    names = [k for k in CHAINS if not (k == "rsa" and role == "mo-server")]
    chain = "good" if rng.random() < 0.6 else rng.choice(names)
    suites = rng.sample(list(c.SUITES.values()), k=rng.choice([1, 2, 2]))
    if rng.random() < 0.04:
        suites = ["TLS_AES_256_GCM_SHA384"]
    elif rng.random() < 0.2:
        suites.insert(rng.randrange(len(suites) + 1), "TLS_AES_256_GCM_SHA384")
    groups = rng.choice(["X25519", "X25519", "P-256:X25519", "X25519:P-256", "P-384:P-256:X25519"])
    if rng.random() < 0.03:
        groups = "P-256"
    def alpn() -> list[str]:
        return rng.sample(NAMES, k=rng.randint(1, 3)) if rng.random() < 0.5 else []
    sizes: list[int] = []
    for _ in range(rng.randint(0, 6)):
        size = rng.choice([0, 1, 2, 7, 100, 1000, 4096, 16383, 16384, 16385, rng.randint(0, 20000)])
        if sum(sizes) + size <= 20000:
            sizes.append(size)
    total = sum(sizes)
    keyupdate = rng.choice(["none", "openssl", "mo", "mo-request"]) if total >= 2 else "none"
    return Params(n, role, key, chain, rng.random() < 0.5, suites, groups, alpn(), alpn(), sizes,
                  keyupdate, rng.choice(["mo", "openssl"]))


def expected(p: Params) -> dict:
    """What the parameters say the session comes to."""
    _, _, _, _, by_openssl, by_mo = CHAINS[p.chain]
    refusal = by_openssl if p.role == "mo-server" else by_mo
    ours = [s for s in ("TLS_AES_128_GCM_SHA256", "TLS_CHACHA20_POLY1305_SHA256") if s in p.suites]
    groups = p.groups.split(":")
    out = {"handshake": False, "suite": "", "alpn": "", "alert": None, "alert_by": None}
    if p.role == "mo-server":
        # The brick's server: TLS 1.3 alone, AES-128-GCM when offered, then ChaCha20, ALPN, and
        # X25519 alone, checked in that order (readHello).
        if not ours:
            return {**out, "alert": 40, "alert_by": "mo"}
        suite = ours[0] if len(ours) == 1 else "TLS_AES_128_GCM_SHA256"
        if p.client_alpn and p.server_alpn:
            shared = [x for x in p.server_alpn if x in p.client_alpn]
            if not shared:
                return {**out, "alert": 120, "alert_by": "mo"}
            alpn = shared[0]
        else:
            alpn = ""
        if "X25519" not in groups:
            return {**out, "alert": 40, "alert_by": "mo"}
        if refusal is not None:
            return {**out, "alert": refusal, "alert_by": "openssl"}
    else:
        # OpenSSL's server takes the client's order (the brick offers AES-128-GCM first) among
        # the suites it allows, and ALPN as the brick's server does (RFC 7301 3.2): its own first
        # that the client offered, `no_application_protocol` when none is.
        if not ours:
            return {**out, "alert": 40, "alert_by": "openssl"}
        suite = "TLS_AES_128_GCM_SHA256" if "TLS_AES_128_GCM_SHA256" in ours else ours[0]
        if "X25519" not in groups:
            # The brick's client offers X25519 alone (its supported_groups), so a server without
            # it shares no group.
            return {**out, "alert": 40, "alert_by": "openssl"}
        alpn = ""
        if p.client_alpn and p.server_alpn:
            shared = [x for x in p.server_alpn if x in p.client_alpn]
            if not shared:
                return {**out, "alert": 120, "alert_by": "openssl"}
            alpn = shared[0]
        if refusal == "rsa":
            # An RSA key can sign none of the schemes the brick offers (Ed25519, ECDSA P-256).
            return {**out, "alert": 40, "alert_by": "openssl"}
        if refusal is not None:
            return {**out, "alert": refusal, "alert_by": "mo"}
    return {**out, "handshake": True, "suite": suite, "alpn": alpn}


def reader(stream, sink: bytearray, done: threading.Event) -> None:
    while True:
        chunk = stream.read1(65536) if hasattr(stream, "read1") else stream.read(65536)
        if not chunk:
            break
        sink.extend(chunk)
    done.set()


def payload(sizes: list[int], seed: int) -> list[bytes]:
    rng = random.Random(seed)
    return [bytes(rng.choice(ALPHABET.encode()) for _ in range(n)) for n in sizes]


def peer_json(text: str) -> dict:
    for line in reversed(text.splitlines()):
        line = line.strip()
        if line.startswith("{"):
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                pass
    return {"handshake": False, "end": "no-report", "alert": -1}


def run_mo_server(p: Params, work) -> tuple[dict, dict]:
    chain_file, key_file, trust, host, _, _ = CHAINS[p.chain]
    port = c.free_port()
    total = sum(p.sizes)
    argv = [c.PEER, "server", "--port", port, "--cert", c.fixture(chain_file, p.key), "--key", c.fixture(key_file, p.key),
            "--expect", total, "--wait-ms", 8000]
    if p.server_alpn:
        argv += ["--alpn", ",".join(p.server_alpn)]
    if p.keyupdate in ("mo", "mo-request"):
        argv += ["--ku-after", max(1, total // 2)] + (["--ku-request"] if p.keyupdate == "mo-request" else [])
    if p.closer == "mo":
        argv += ["--close-first"]
    peer = subprocess.Popen(c.guarded(argv, 20), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    first = peer.stdout.readline()
    if b"listening" not in first:
        peer.wait(timeout=25)
        return peer_json(first.decode() + peer.stdout.read().decode()), {"handshake": False, "error": "peer did not listen"}
    msgfile = work / f"msg-{p.n}.txt"
    s_argv = [c.OPENSSL, "s_client", "-connect", f"127.0.0.1:{port}", "-CAfile", c.fixture(trust, p.key),
              "-verify_return_error", "-verify_hostname", host, "-verify_depth", "4", "-brief",
              "-msg", "-msgfile", msgfile, "-ciphersuites", ":".join(p.suites), "-groups", p.groups]
    s_argv += ["-servername", host] if p.sni else ["-noservername"]
    if p.client_alpn:
        s_argv += ["-alpn", ",".join(p.client_alpn)]
    ssl = subprocess.Popen(c.guarded(s_argv, 20), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
    got = bytearray()
    err = bytearray()
    out_done, err_done = threading.Event(), threading.Event()
    threading.Thread(target=reader, args=(ssl.stdout, got, out_done), daemon=True).start()
    threading.Thread(target=reader, args=(ssl.stderr, err, err_done), daemon=True).start()
    chunks = payload(p.sizes, p.n)
    sent = b"".join(chunks)
    try:
        # The handshake first: s_client reads stdin only once it is connected.
        t0 = time.time()
        while b"CONNECTION ESTABLISHED" not in err and ssl.poll() is None and time.time() - t0 < 5:
            time.sleep(0.01)
        # s_client's KeyUpdate goes before a chunk that carries data, so records flow after it
        # (and a brick that closes once the last byte is echoed cannot close before it).
        filled = [i for i, chunk in enumerate(chunks) if chunk]
        k_at = filled[len(filled) // 2] if filled else -1
        for i, chunk in enumerate(chunks):
            if p.keyupdate == "openssl" and i == k_at and b"CONNECTION ESTABLISHED" in err:
                time.sleep(0.15)
                ssl.stdin.write(b"K\n")
                ssl.stdin.flush()
                time.sleep(0.15)
            if chunk:
                ssl.stdin.write(chunk)
                ssl.stdin.flush()
                time.sleep(0.02)
        t0 = time.time()
        while len(got) < len(sent) and ssl.poll() is None and time.time() - t0 < 5:
            time.sleep(0.01)
        if p.closer == "openssl":
            ssl.stdin.close()
        t0 = time.time()
        while ssl.poll() is None and time.time() - t0 < 5:
            time.sleep(0.01)
        if ssl.poll() is None:
            ssl.stdin.close()
    except (BrokenPipeError, OSError):
        pass
    try:
        ssl.wait(timeout=25)
    except subprocess.TimeoutExpired:
        ssl.kill()
    out_done.wait(5)
    err_done.wait(5)
    peer_out = peer.communicate(timeout=25)[0].decode(errors="replace")
    msgs = c.Msgs(msgfile.read_text() if msgfile.exists() else "")
    brief = err.decode(errors="replace")
    suite = ""
    for line in brief.splitlines():
        if line.startswith("Ciphersuite: "):
            suite = line.split(": ", 1)[1].strip()
    ossl = {
        "handshake": "CONNECTION ESTABLISHED" in brief,
        "suite": suite,
        "alpn": msgs.alpn("<<<"),
        "echo_ok": bytes(got) == sent,
        "sent_alerts": [a for a in msgs.alerts(">>>") if a != 0],
        "received_alerts": [a for a in msgs.alerts("<<<") if a != 0],
        "ku_sent": msgs.count(">>>", "KeyUpdate"),
        "ku_read": msgs.count("<<<", "KeyUpdate"),
        "sent_close": msgs.closes(">>>"),
        "received_close": msgs.closes("<<<"),
        "exit": ssl.returncode,
    }
    return peer_json(peer_out), ossl


def run_mo_client(p: Params, work) -> tuple[dict, dict]:
    chain_file, key_file, trust, host, _, _ = CHAINS[p.chain]
    if not p.sni and host == "localhost":
        host = "127.0.0.1"
    port = c.free_port()
    total = sum(p.sizes)
    leaf, rest = c.split_chain(c.fixture(chain_file, p.key), work)
    msgfile = work / f"msg-{p.n}.txt"
    s_argv = [c.OPENSSL, "s_server", "-accept", port, "-naccept", "1", "-cert", leaf, "-key", c.fixture(key_file, p.key),
              "-msg", "-msgfile", msgfile, "-ciphersuites", ":".join(p.suites), "-groups", p.groups]
    if rest:
        s_argv += ["-cert_chain", rest]
    if p.server_alpn:
        s_argv += ["-alpn", ",".join(p.server_alpn)]
    ssl = subprocess.Popen(c.guarded(s_argv, 20), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
    out = bytearray()
    done = threading.Event()
    threading.Thread(target=reader, args=(ssl.stdout, out, done), daemon=True).start()
    t0 = time.time()
    while b"ACCEPT" not in out and ssl.poll() is None and time.time() - t0 < 5:
        time.sleep(0.01)
    argv = [c.PEER, "client", "--port", port, "--host", host, "--trust", c.fixture(trust, p.key),
            "--send", ",".join(str(s) for s in p.sizes) or "0", "--wait-ms", 8000]
    if p.client_alpn:
        argv += ["--alpn", ",".join(p.client_alpn)]
    if p.keyupdate in ("mo", "mo-request"):
        argv += ["--ku-after", max(1, total // 2)] + (["--ku-request"] if p.keyupdate == "mo-request" else [])
    if p.closer == "mo":
        argv += ["--close-first"]
    peer = subprocess.Popen(c.guarded(argv, 20), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    # The echo: what s_server prints of the client's bytes goes back on its stdin, after the
    # connection report ends; a KeyUpdate from s_server (`K`) before any of it goes back.
    marker = b"Secure Renegotiation IS"
    echoed = 0
    sent_k = p.keyupdate != "openssl"
    wanted = set(ALPHABET.encode())
    try:
        t0 = time.time()
        while time.time() - t0 < 12 and peer.poll() is None:
            at = out.find(marker)
            if at >= 0:
                line_end = out.find(b"\n", at)
                if line_end >= 0:
                    data = bytes(x for x in out[line_end + 1:] if x in wanted)
                    if len(data) > echoed:
                        # s_server's KeyUpdate goes before the echo, so records flow after it.
                        if not sent_k:
                            time.sleep(0.15)
                            ssl.stdin.write(b"K\n")
                            ssl.stdin.flush()
                            time.sleep(0.15)
                            sent_k = True
                            continue
                        ssl.stdin.write(data[echoed:])
                        ssl.stdin.flush()
                        echoed = len(data)
                        time.sleep(0.02)
                    if echoed >= total:
                        if not sent_k:
                            time.sleep(0.15)
                            ssl.stdin.write(b"K\n")
                            ssl.stdin.flush()
                            time.sleep(0.15)
                            sent_k = True
                        if p.closer == "openssl":
                            time.sleep(0.1)
                            ssl.stdin.close()
                            break
            time.sleep(0.01)
    except (BrokenPipeError, OSError, ValueError):
        pass
    try:
        peer_out = peer.communicate(timeout=25)[0].decode(errors="replace")
    except subprocess.TimeoutExpired:
        peer.kill()
        peer_out = ""
    try:
        if not ssl.stdin.closed:
            ssl.stdin.close()
    except OSError:
        pass
    try:
        ssl.wait(timeout=25)
    except subprocess.TimeoutExpired:
        ssl.kill()
    done.wait(5)
    report = out.decode(errors="replace")
    msgs = c.Msgs(msgfile.read_text() if msgfile.exists() else "")
    suite = ""
    alpn = ""
    for line in report.splitlines():
        if line.startswith("CIPHER is "):
            suite = line.split("CIPHER is ", 1)[1].strip()
        if line.startswith("ALPN protocols selected: "):
            alpn = line.split(": ", 1)[1].strip()
    ossl = {
        "handshake": "CIPHER is " in report,
        "suite": suite,
        "alpn": alpn,
        "alpn_sent": msgs.alpn(">>>"),
        "echoed": echoed,
        "sent_alerts": [a for a in msgs.alerts(">>>") if a != 0],
        "received_alerts": [a for a in msgs.alerts("<<<") if a != 0],
        "ku_sent": msgs.count(">>>", "KeyUpdate"),
        "ku_read": msgs.count("<<<", "KeyUpdate"),
        "sent_close": msgs.closes(">>>"),
        "received_close": msgs.closes("<<<"),
        "exit": ssl.returncode,
    }
    return peer_json(peer_out), ossl


def compare(p: Params, mo: dict, ossl: dict) -> list[str]:
    """Every fact on which the brick, OpenSSL, and the parameters do not all agree."""
    want = expected(p)
    wrong = []
    total = sum(p.sizes)

    def check(fact: str, *views):
        if len(set(json.dumps(v) for v in views)) > 1:
            wrong.append(f"{fact}: " + " / ".join(json.dumps(v) for v in views))

    check("handshake", want["handshake"], mo.get("handshake"), ossl.get("handshake"))
    if want["handshake"]:
        check("suite", want["suite"], mo.get("suite"), ossl.get("suite"))
        check("alpn", want["alpn"], mo.get("alpn"), ossl.get("alpn"))
        if p.role == "mo-server":
            check("bytes", total, mo.get("bytes_in"))
            check("echo", True, ossl.get("echo_ok"))
        else:
            check("bytes", total, mo.get("bytes_in"))
            check("echo", True, mo.get("echo_ok"))
        check("alerts", [], ossl.get("sent_alerts"), ossl.get("received_alerts"))
        # A KeyUpdate injected went out, arrived, and was answered when it asked.
        ku_out, ku_in = mo.get("ku_sent", 0), mo.get("ku_read", 0)
        check("keyupdate seen", [ku_out, ku_in], [ossl.get("ku_read"), ossl.get("ku_sent")])
        want_ku = {"none": [0, 0], "openssl": [1, 1], "mo": [1, 0], "mo-request": [1, 1]}[p.keyupdate]
        if p.keyupdate == "mo-request" and p.role == "mo-server" and ku_in == 0:
            # RFC 8446 4.6.3: the answer is owed before the requested side's next application
            # data; an s_client that has written its last byte owes none, and sends none.
            want_ku = [1, 0]
        check("keyupdate", want_ku, [ku_out, ku_in])
        # The first close_notify, as the other side saw it (the side that sent it need not stay
        # for the answer: s_client, its stdin closed, sends one and exits; s_server, its stdin
        # closed, drops the connection with none).
        if p.closer == "mo":
            check("close to openssl", True, mo.get("sent_close"), ossl.get("received_close"))
        else:
            mo_heard = mo.get("end") in ("closed-peer-first", "closed-self-first")
            check("close to mo", ossl.get("sent_close"), mo_heard)
    else:
        by, alert = want["alert_by"], want["alert"]
        mo_alert = mo.get("alert")
        if by == "mo":
            check("alert", [alert, False], [mo_alert, mo.get("alert_from_peer")], [ossl["received_alerts"][:1] and ossl["received_alerts"][0], False])
        else:
            check("alert", [alert, True], [mo_alert, mo.get("alert_from_peer")], [ossl["sent_alerts"][:1] and ossl["sent_alerts"][0], True])
        if by == "mo" and p.role == "mo-client":
            check("untrusted", alert in (42, 43, 45, 48), mo.get("untrusted"))
    return wrong


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--sessions", type=int, default=1000)
    args = ap.parse_args()
    c.ensure_tools()
    work = c.WORK / f"diff-{args.seed}"
    work.mkdir(parents=True, exist_ok=True)
    log = (c.WORK / f"diff-{args.seed}.log").open("w")
    log.write(c.stamp())
    log.write(f"diff.py --seed {args.seed} --sessions {args.sessions}\n")
    rng = random.Random(args.seed)
    mismatches = 0
    tally: dict[str, int] = {}
    t0 = time.time()
    for n in range(args.sessions):
        p = draw(rng, n)
        mo, ossl = (run_mo_server if p.role == "mo-server" else run_mo_client)(p, work)
        wrong = compare(p, mo, ossl)
        mismatches += bool(wrong)
        key = f"{p.role} {'handshake' if expected(p)['handshake'] else 'refused'} ku={p.keyupdate}"
        tally[key] = tally.get(key, 0) + 1
        log.write(json.dumps({"params": asdict(p), "expected": expected(p), "mo": mo, "openssl": ossl, "mismatch": wrong}) + "\n")
        log.flush()
        if wrong:
            print(f"session {n}: MISMATCH {wrong}", flush=True)
        if (n + 1) % 50 == 0:
            print(f"{n + 1} sessions, {mismatches} mismatches, {time.time() - t0:.0f} s", flush=True)
    summary = f"{args.sessions} sessions, seed {args.seed}: {mismatches} mismatches ({time.time() - t0:.0f} s)"
    log.write("# " + summary + "\n")
    for k in sorted(tally):
        log.write(f"#   {k}: {tally[k]}\n")
    log.close()
    print(summary)
    for k in sorted(tally):
        print(f"  {k}: {tally[k]}")
    return 1 if mismatches else 0


if __name__ == "__main__":
    raise SystemExit(main())
