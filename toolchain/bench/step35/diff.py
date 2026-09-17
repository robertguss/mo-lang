"""Step 35's differential run: 1,000 random inputs per crypto row, at random lengths from 0 to
4,096 bytes, through driver.mo under `mo run` and as a binary, each answer held against Python's
cryptography (OpenSSL) and hashlib. Prints the mismatch count per row and runtime.

    uv run python diff.py [--n 1000] [--seed 35] [--mo ../../zig-out/bin/mo] [--only row,row]
"""

import argparse
import base64
import hashlib
import hmac
import os
import random
import subprocess
import sys
import time

from cryptography.exceptions import InvalidSignature, InvalidTag
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM, ChaCha20Poly1305
from cryptography.hazmat.primitives.kdf.argon2 import Argon2id
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

HERE = os.path.dirname(os.path.abspath(__file__))
GUARD = os.path.join(HERE, "guard.py")
RAW = serialization.Encoding.Raw
RAW_PUB = serialization.PublicFormat.Raw
# The low-order points of Curve25519 (RFC 7748 and libsodium's blocklist), which agree to None.
LOW_ORDER = [
    bytes(32),
    b"\x01" + bytes(31),
    bytes.fromhex("e0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800"),
    bytes.fromhex("5f9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f1157"),
    bytes.fromhex("ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f"),
]


def h(b):
    return b.hex()


def blob(rng, top=4096):
    return rng.randbytes(rng.randint(0, top))


def opened(f):
    try:
        return h(f())
    except InvalidTag:
        return "none"


def case_sha256(rng):
    m = blob(rng)
    return f"sha256 {h(m)}", hashlib.sha256(m).hexdigest()


def case_sha512(rng):
    m = blob(rng)
    return f"sha512 {h(m)}", hashlib.sha512(m).hexdigest()


def case_hmac(rng):
    k, m = blob(rng), blob(rng)
    return f"hmac {h(k)} {h(m)}", hmac.new(k, m, hashlib.sha256).hexdigest()


def case_hkdf(rng):
    ikm, salt, info = blob(rng), blob(rng), blob(rng)
    size = rng.randint(0, 255 * 32)
    if size == 0:
        want = ""
    else:
        want = HKDF(hashes.SHA256(), size, salt, info).derive(ikm).hex()
    return f"hkdf {h(ikm)} {h(salt)} {h(info)} {size}", want


def case_hex(rng):
    m = blob(rng)
    return f"hex {h(m)}", m.hex()


def case_from_hex(rng):
    m = blob(rng)
    text = "".join(c.upper() if rng.random() < 0.5 else c for c in m.hex())
    if rng.random() < 0.3 and text:
        i = rng.randrange(len(text))
        text = text[:i] + rng.choice("gxz-: G") + text[i + 1 :]
    if rng.random() < 0.1:
        text += "a"
    valid = len(text) % 2 == 0 and all(c in "0123456789abcdefABCDEF" for c in text)
    return f"from_hex {h(text.encode())}", bytes.fromhex(text).hex() if valid else "none"


def case_equal(rng):
    a = blob(rng)
    r = rng.random()
    if r < 0.4:
        b = a
    elif r < 0.8 and a:
        i = rng.randrange(len(a))
        b = a[:i] + bytes([a[i] ^ (1 << rng.randrange(8))]) + a[i + 1 :]
    else:
        b = blob(rng)
    return f"equal {h(a)} {h(b)}", "true" if a == b else "false"


def aead_seal(name, cls):
    def case(rng):
        k, n, p, a = rng.randbytes(32), rng.randbytes(12), blob(rng), blob(rng)
        return f"{name}_seal {h(k)} {h(n)} {h(p)} {h(a)}", cls(k).encrypt(n, p, a).hex()

    return case


def aead_open(name, cls):
    def case(rng):
        k, n, p, a = rng.randbytes(32), rng.randbytes(12), blob(rng), blob(rng)
        sealed = cls(k).encrypt(n, p, a)
        r = rng.random()
        if r < 0.25:
            i = rng.randrange(len(sealed))
            sealed = sealed[:i] + bytes([sealed[i] ^ 1]) + sealed[i + 1 :]
        elif r < 0.35:
            a = a + b"x"
        elif r < 0.45:
            sealed = sealed[: rng.randrange(16)]
        want = "none" if len(sealed) < 16 else opened(lambda: cls(k).decrypt(n, sealed, a))
        return f"{name}_open {h(k)} {h(n)} {h(sealed)} {h(a)}", want

    return case


def case_x25519_public(rng):
    s = rng.randbytes(32)
    pub = X25519PrivateKey.from_private_bytes(s).public_key().public_bytes(RAW, RAW_PUB)
    return f"x25519_public {h(s)}", pub.hex()


def case_x25519_shared(rng):
    s = rng.randbytes(32)
    if rng.random() < 0.05:
        p = rng.choice(LOW_ORDER)
    else:
        p = rng.randbytes(32)
    try:
        want = X25519PrivateKey.from_private_bytes(s).exchange(X25519PublicKey.from_public_bytes(p)).hex()
    except ValueError:
        want = "none"
    return f"x25519_shared {h(s)} {h(p)}", want


def case_ed25519_public(rng):
    seed = rng.randbytes(32)
    pub = Ed25519PrivateKey.from_private_bytes(seed).public_key().public_bytes(RAW, RAW_PUB)
    return f"ed25519_public {h(seed)}", pub.hex()


def case_ed25519_sign(rng):
    seed, m = rng.randbytes(32), blob(rng)
    return f"ed25519_sign {h(seed)} {h(m)}", Ed25519PrivateKey.from_private_bytes(seed).sign(m).hex()


def case_ed25519_verify(rng):
    key = Ed25519PrivateKey.from_private_bytes(rng.randbytes(32))
    m = blob(rng)
    pub = key.public_key().public_bytes(RAW, RAW_PUB)
    sig = key.sign(m)
    r = rng.random()
    if r < 0.2:
        i = rng.randrange(64)
        sig = sig[:i] + bytes([sig[i] ^ (1 << rng.randrange(8))]) + sig[i + 1 :]
    elif r < 0.3 and m:
        m = m[:-1]
    elif r < 0.4:
        pub = rng.randbytes(32)
    try:
        Ed25519PublicKey.from_public_bytes(pub).verify(sig, m)
        want = "true"
    except (InvalidSignature, ValueError):
        want = "false"
    return f"ed25519_verify {h(pub)} {h(m)} {h(sig)}", want


def password(rng, top):
    return bytes(rng.randint(32, 126) for _ in range(rng.randint(0, top)))


def phc(pw, salt):
    tag = Argon2id(salt=salt, length=32, iterations=3, lanes=1, memory_cost=65536).derive(pw)
    b64 = lambda b: base64.b64encode(b).decode().rstrip("=")
    return f"$argon2id$v=19$m=65536,t=3,p=1${b64(salt)}${b64(tag)}"


def case_password_hash(rng):
    pw, salt = password(rng, 4096), rng.randbytes(16)
    return f"password_hash {h(pw)} {h(salt)}", phc(pw, salt)


def case_password_verify(rng):
    pw, salt = password(rng, 4096), rng.randbytes(16)
    text = phc(pw, salt)
    r = rng.random()
    want = "true"
    if r < 0.3:
        pw, want = pw + b"!", "false"
    elif r < 0.5:
        i = rng.randrange(len(text))
        mutated = text[:i] + chr(rng.randint(33, 126)) + text[i + 1 :]
        if mutated != text:
            text, want = mutated, "false"
    return f"password_verify {h(pw)} {h(text.encode())}", want


CASES = {
    "sha256": case_sha256,
    "sha512": case_sha512,
    "hmac": case_hmac,
    "hkdf": case_hkdf,
    "hex": case_hex,
    "from_hex": case_from_hex,
    "equal": case_equal,
    "gcm_seal": aead_seal("gcm", AESGCM),
    "gcm_open": aead_open("gcm", AESGCM),
    "chacha_seal": aead_seal("chacha", ChaCha20Poly1305),
    "chacha_open": aead_open("chacha", ChaCha20Poly1305),
    "x25519_public": case_x25519_public,
    "x25519_shared": case_x25519_shared,
    "ed25519_public": case_ed25519_public,
    "ed25519_sign": case_ed25519_sign,
    "ed25519_verify": case_ed25519_verify,
    "password_hash": case_password_hash,
    "password_verify": case_password_verify,
}


def guarded(seconds, argv, **kw):
    return subprocess.run([sys.executable, GUARD, str(seconds), "--", *argv], capture_output=True, text=True, **kw)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=1000)
    ap.add_argument("--seed", type=int, default=35)
    ap.add_argument("--mo", default=os.path.join(HERE, "../../zig-out/bin/mo"))
    ap.add_argument("--only", default="")
    ap.add_argument("--work", default=os.path.join(HERE, "work"))
    args = ap.parse_args()
    mo = os.path.abspath(args.mo)
    os.makedirs(args.work, exist_ok=True)
    built = guarded(900, [mo, "build", "-o", "driver", os.path.join(HERE, "driver.mo")], cwd=args.work)
    if built.returncode != 0:
        sys.exit(f"mo build failed:\n{built.stdout}{built.stderr}")
    binary = os.path.join(args.work, "zig-out/mo-build/driver/driver")
    rows = [r for r in CASES if not args.only or r in args.only.split(",")]
    total = 0
    print(f"{'row':16} {'n':>5} {'mo run':>7} {'binary':>7}  seconds (run, binary)")
    for row in rows:
        rng = random.Random(f"{args.seed}:{row}")
        cases = [CASES[row](rng) for _ in range(args.n)]
        path = os.path.join(args.work, f"{row}.txt")
        with open(path, "w") as f:
            f.write("".join(line + "\n" for line, _ in cases))
        wants = [want for _, want in cases]
        counts, seconds = [], []
        for argv in ([mo, "run", os.path.join(HERE, "driver.mo"), "--", path], [binary, path]):
            t0 = time.time()
            ran = guarded(7200, argv, cwd=args.work)
            seconds.append(time.time() - t0)
            got = ran.stdout.split("\n")[:-1]
            bad = sum(1 for i, want in enumerate(wants) if i >= len(got) or got[i] != want)
            if ran.returncode != 0:
                sys.stderr.write(f"{row}: {argv[0]} exited {ran.returncode}: {ran.stderr[-2000:]}\n")
                bad = max(bad, 1)
            for i, want in enumerate(wants):
                if i < len(got) and got[i] != want:
                    sys.stderr.write(f"{row} #{i} ({os.path.basename(argv[0])}): want {want[:80]} got {got[i][:80]}\n")
                    break
            counts.append(bad)
        total += sum(counts)
        print(f"{row:16} {args.n:>5} {counts[0]:>7} {counts[1]:>7}  {seconds[0]:.1f}, {seconds[1]:.1f}", flush=True)
    print(f"total mismatches: {total}")
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
