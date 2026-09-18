"""limbo.py [--limbo work/x509-limbo/limbo.json]: the TLS brick's chain check against x509-limbo
(github.com/C2SP/x509-limbo), the TLS-server cases inside the brick's cut.

In the cut: `validation_kind` SERVER; every certificate (roots, intermediates, the peer's) with an
Ed25519 or P-256 key and an Ed25519 or ECDSA-with-SHA-256 signature; and none of the inputs a
brick client has no way to be given: no CRL (the cut has no revocation), no `max_chain_depth`
(the brick's depth is five), no key usage or signature algorithm the validator is asked to want,
an extended key usage of none or server authentication (the brick's policy), and a peer name to
connect for. Each case's chain goes to the brick as a server sends one, leaf first, then the
intermediates that lead by name from it to a trusted root (the pool's first such path, found by
subject and issuer names alone, since choosing among intermediates is the server's work and the
brick does no path building); a pool with no such path is sent leaf first and then as listed.

`mo-tls-limbo` (bench/step39/limbo.zig, `zig build tls-tools`) runs the brick's `checkChain` on
every case under guard.py. The result is two numbers and a list: accepted but limbo says reject
(must be zero), rejected but limbo says accept (each with a reason), and the rest agree. Written
to `work/limbo.txt` with the date and `uptime` at its head, and every case's answer to
`work/limbo-cases.tsv`.
"""

from __future__ import annotations

import argparse
import collections
import functools
import datetime
import json
import subprocess
import sys
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec, ed25519

HERE = Path(__file__).resolve().parent
TOOLCHAIN = HERE.parents[1]
WORK = HERE / "work"
GUARD = [sys.executable, str(HERE.parent / "step36" / "guard.py")]
TOOL = TOOLCHAIN / "zig-out" / "bin" / "mo-tls-limbo"
SIGS = {"1.3.101.112", "1.2.840.10045.4.3.2"}
NAME_CONSTRAINTS = x509.oid.ExtensionOID.NAME_CONSTRAINTS


def stamp() -> str:
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    up = subprocess.run(["uptime"], capture_output=True, text=True).stdout.strip()
    top = subprocess.run(["ps", "-Ao", "pid,pcpu,rss,comm", "-r"], capture_output=True, text=True).stdout.splitlines()[:6]
    return f"{now}\n{up}\n" + "\n".join(top) + "\n"


@functools.lru_cache(maxsize=None)
def load(pem: str) -> x509.Certificate:
    """A certificate parsed once: each case's are read three times (the cut, the path, a reason)."""
    return x509.load_pem_x509_certificate(pem.encode())


def in_algorithms(cert: x509.Certificate) -> bool:
    if cert.signature_algorithm_oid.dotted_string not in SIGS:
        return False
    try:
        key = cert.public_key()
    except Exception:
        return False
    return isinstance(key, ed25519.Ed25519PublicKey) or (isinstance(key, ec.EllipticCurvePublicKey) and key.curve.name == "secp256r1")


def outside(case: dict) -> str | None:
    """Why a case is outside the cut, or None."""
    if case["validation_kind"] != "SERVER":
        return "not a server's chain"
    if case["crls"]:
        return "a CRL: no revocation in the cut"
    if case["max_chain_depth"] is not None:
        return "a max_chain_depth: the brick's depth is five"
    if case["signature_algorithms"] or case["key_usage"]:
        return "a signature algorithm or key usage asked for"
    if case["extended_key_usage"] not in ([], ["serverAuth"]):
        return "an extended key usage other than server authentication asked for"
    if not case["expected_peer_name"] or case["expected_peer_name"]["kind"] not in ("DNS", "IP"):
        return "no DNS name or address to connect for"
    try:
        certs = [load(p) for p in case["trusted_certs"] + case["untrusted_intermediates"] + [case["peer_certificate"]]]
    except Exception:
        return "a certificate Python's cryptography cannot read"
    if not all(in_algorithms(c) for c in certs):
        return "a key or signature outside Ed25519 and P-256"
    return None


def der(pem: str) -> bytes:
    return load(pem).public_bytes(serialization.Encoding.DER)


def signs(child: x509.Certificate, parent: x509.Certificate) -> bool:
    """`parent` issued `child`: the names link and the signature checks."""
    if child.issuer.public_bytes() != parent.subject.public_bytes():
        return False
    try:
        child.verify_directly_issued_by(parent)
        return True
    except Exception:
        return False


def sent_chain(case: dict) -> list[str]:
    """The chain as a server sends it: the leaf, then the intermediates of the shortest path whose
    names and signatures link it to a trusted root. Breadth first, each intermediate visited once
    (a depth-first walk trying every order was exponential on limbo's pools of look-alike
    intermediates). A pool with no such path is sent leaf first and then as listed."""
    leaf = load(case["peer_certificate"])
    pool = [load(p) for p in case["untrusted_intermediates"]]
    roots = [load(p) for p in case["trusted_certs"]]

    def rooted(cert: x509.Certificate) -> bool:
        return any(signs(cert, r) for r in roots)

    path = None
    if rooted(leaf):
        path = []
    else:
        came: dict[int, int | None] = {}
        frontier = [i for i, c in enumerate(pool) if signs(leaf, c)]
        for i in frontier:
            came[i] = None
        while frontier and path is None:
            nxt = []
            for i in frontier:
                if rooted(pool[i]):
                    path, k = [], i
                    while k is not None:
                        path.append(k)
                        k = came[k]
                    path.reverse()
                    break
                for j, c in enumerate(pool):
                    if j not in came and signs(pool[i], c):
                        came[j] = i
                        nxt.append(j)
            frontier = nxt
    if path is None:
        path = list(range(len(pool)))
    return [case["peer_certificate"]] + [case["untrusted_intermediates"][i] for i in path]


def reason(case: dict, answer: str) -> str:
    """Why the brick refused a case limbo accepts."""
    certs = [load(p) for p in case["trusted_certs"] + case["untrusted_intermediates"] + [case["peer_certificate"]]]
    if answer == "unsupported_certificate":
        for c in certs:
            try:
                c.extensions.get_extension_for_oid(NAME_CONSTRAINTS)
                return "name constraints in the path: refused as unsupported by design (step 39 part A)"
            except x509.ExtensionNotFound:
                pass
        leaf = load(case["peer_certificate"])
        try:
            ku = leaf.extensions.get_extension_for_class(x509.KeyUsage).value
            if not ku.digital_signature:
                return "the leaf's key usage lacks digitalSignature: refused by design (RFC 8446 4.4.2.2, step 39 decision 4)"
        except x509.ExtensionNotFound:
            pass
    if case["id"].startswith("bettertls::pathbuilding::"):
        return "path building: the pool holds several paths and the brick checks the one a server sends (limbo.py sends the shortest whose signatures link); the brick does no path building"
    return f"{answer}: see the case"


def accept_reason(cid: str) -> str:
    """Why the brick accepts a case limbo refuses: none of these is an RFC 5280 path rule the
    brick could add without refusing chains it must accept."""
    control = {"rfc5280::aki::leaf-missing-aki", "rfc5280::aki::intermediate-missing-aki",
               "rfc5280::aki::cross-signed-root-missing-aki", "rfc5280::ski::root-missing-ski",
               "rfc5280::ski::intermediate-missing-ski", "webpki::eku::ee-without-eku"}
    if cid in control:
        return ("a rule on what a conforming CA must include (AKI, SKI, or the leaf's EKU), which the auditor's "
                "valid control in chain-checks.py omits: enforcing it refuses that control; the lead's to decide")
    if cid.startswith("webpki::cn::"):
        return ("CA/B Forum BR 7.1.4.3, the common name one of the SAN's values: not enforced (the brick does not "
                "read the common name; a private CA's descriptive common name would be refused)")
    if cid.startswith("webpki::san::public-suffix"):
        return "a wildcard over a public suffix: needs the public suffix list, which the brick does not carry"
    return "a CA/B Forum Baseline Requirements profile rule (web PKI), not RFC 5280's: not enforced"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limbo", default=str(WORK / "x509-limbo" / "limbo.json"))
    args = ap.parse_args()
    WORK.mkdir(exist_ok=True)
    head = stamp()
    doc = json.loads(Path(args.limbo).read_text())
    cases = doc["testcases"]
    kept = []
    skipped: collections.Counter[str] = collections.Counter()
    for case in cases:
        why = outside(case)
        if why:
            skipped[why] += 1
            continue
        kept.append(case)
    lines = []
    for case in kept:
        when = case["validation_time"]
        now = int(datetime.datetime.fromisoformat(when).timestamp()) if when else int(datetime.datetime.now().timestamp())
        chain = ",".join(der(p).hex() for p in sent_chain(case))
        trust = ",".join(der(p).hex() for p in case["trusted_certs"])
        lines.append("\t".join([case["id"], chain, trust, case["expected_peer_name"]["value"], str(now)]))
    inputs = WORK / "limbo-input.tsv"
    inputs.write_text("\n".join(lines) + "\n")
    ran = subprocess.run(GUARD + ["600", "--", str(TOOL), str(inputs)], capture_output=True, text=True)
    if ran.returncode != 0:
        raise SystemExit(f"mo-tls-limbo exited {ran.returncode}:\n{ran.stderr[-4000:]}")
    answers = dict(line.split("\t") for line in ran.stdout.splitlines())
    by_id = {c["id"]: c for c in kept}
    wrong_accept, wrong_reject, agree = [], [], 0
    out = []
    for cid, answer in answers.items():
        want = by_id[cid]["expected_result"]
        out.append(f"{cid}\t{want}\t{answer}")
        if answer == "ok" and want == "FAILURE":
            wrong_accept.append(cid)
        elif answer != "ok" and want == "SUCCESS":
            wrong_reject.append((cid, answer, reason(by_id[cid], answer)))
        else:
            agree += 1
    (WORK / "limbo-cases.tsv").write_text(head + "id\tlimbo\tbrick\n" + "\n".join(out) + "\n")
    reasons = collections.Counter(r for _, _, r in wrong_reject)
    report = [head, f"limbo.py --limbo {args.limbo} (limbo version {doc.get('version')}, {len(cases)} cases)", ""]
    report.append(f"in the cut: {len(kept)}; outside it: {sum(skipped.values())}")
    for why, n in skipped.most_common():
        report.append(f"  outside, {why}: {n}")
    report.append("")
    report.append(f"accepted but limbo says reject: {len(wrong_accept)}")
    for why, n in collections.Counter(accept_reason(cid) for cid in wrong_accept).most_common():
        report.append(f"  {n}: {why}")
    for cid in wrong_accept:
        report.append(f"    {cid}: {accept_reason(cid)}")
    report.append(f"rejected but limbo says accept: {len(wrong_reject)}")
    for why, n in reasons.most_common():
        report.append(f"  {n}: {why}")
    for cid, answer, why in wrong_reject:
        report.append(f"    {cid}: {answer}: {why}")
    report.append(f"agreeing: {agree} (limbo's expected result and the brick's answer the same)")
    text = "\n".join(report) + "\n"
    (WORK / "limbo.txt").write_text(text)
    print(text)
    sys.exit(1 if wrong_accept else 0)


if __name__ == "__main__":
    main()
