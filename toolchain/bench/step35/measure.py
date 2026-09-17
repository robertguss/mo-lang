"""Step 35's numbers, best of five, under `mo run` and as a binary, every mo process under guard.py.

    uv run python measure.py --mo ../../zig-out/bin/mo --before /path/to/mo-before

`--before` is a mo built without the brick in its link (the commit before part B), for the
`mo build` rows on examples/programs/jobq.
"""

import argparse
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
GUARD = os.path.join(HERE, "guard.py")
JOBQ = os.path.abspath(os.path.join(HERE, "../../../examples/programs/jobq"))

# (label, op, count, size, unit): unit "mbps" divides count * size by the time.
ROWS = [
    ("SHA-256, 1 MiB", "sha256", 50, 1 << 20, "mbps"),
    ("HMAC-SHA256, 64 B x 100,000", "hmac", 100_000, 64, "ms"),
    ("AES-256-GCM seal, 64 KiB", "gcm", 200, 64 << 10, "mbps"),
    ("Ed25519 sign x 10,000", "sign", 10_000, 64, "ms"),
    ("Ed25519 verify x 10,000", "verify", 10_000, 64, "ms"),
    ("Password.hash once", "password", 1, 0, "ms"),
]


def guarded(seconds, argv, **kw):
    return subprocess.run([sys.executable, GUARD, str(seconds), "--", *argv], capture_output=True, text=True, **kw)


def best_of(n, f):
    return min(f() for _ in range(n))


def build_seconds(mo, cwd, name):
    t0 = time.time()
    ran = guarded(900, [mo, "build", "-o", name, "main.mo"], cwd=cwd)
    if ran.returncode != 0:
        sys.exit(f"mo build failed: {ran.stderr}")
    return time.time() - t0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mo", default=os.path.join(HERE, "../../zig-out/bin/mo"))
    ap.add_argument("--before", required=True)
    ap.add_argument("--work", default=os.path.join(HERE, "work"))
    args = ap.parse_args()
    mo = os.path.abspath(args.mo)
    os.makedirs(args.work, exist_ok=True)
    bench = os.path.join(HERE, "bench.mo")
    if guarded(900, [mo, "build", "-o", "bench", bench], cwd=args.work).returncode != 0:
        sys.exit("mo build bench.mo failed")
    binary = os.path.join(args.work, "zig-out/mo-build/bench/bench")
    print("| measure | mo run | binary |")
    print("|---|---:|---:|")
    for label, op, count, size, unit in ROWS:
        cells = []
        for argv in ([mo, "run", bench, "--", op, str(count), str(size)], [binary, op, str(count), str(size)]):
            def once():
                ran = guarded(3600, argv, cwd=args.work)
                if ran.returncode != 0:
                    sys.exit(f"{argv}: {ran.stderr}")
                return int(ran.stdout.split()[3])
            ms = max(best_of(5, once), 1)
            cells.append(f"{count * size / (1 << 20) / (ms / 1000):,.1f} MB/s" if unit == "mbps" else f"{ms:,} ms")
        print(f"| {label} | {cells[0]} | {cells[1]} |", flush=True)
    raw = subprocess.run(["zig", "run", "-OReleaseFast", "--dep", "brick", f"-Mroot={HERE}/raw.zig",
                          f"-Mbrick={HERE}/../../src/bricks/crypto.zig", "--", "200"],
                         capture_output=True, text=True, cwd=os.path.join(HERE, "../.."), timeout=900)
    print(f"| {raw.stdout.strip()} | | |")
    # mo build on jobq: once to fill the caches, then five warm builds, before and after the brick.
    for label, which in (("before", os.path.abspath(args.before)), ("after", mo)):
        name = f"jobq-{label}"
        build_seconds(which, JOBQ, name)
        warm = best_of(5, lambda: build_seconds(which, JOBQ, name))
        size = os.path.getsize(os.path.join(JOBQ, "zig-out/mo-build", name, name))
        print(f"| mo build jobq warm, {label} | {warm:.2f} s | {size:,} bytes |", flush=True)


if __name__ == "__main__":
    main()
