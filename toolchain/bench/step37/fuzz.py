"""fuzz.py --seed S [--minutes 60] [--batch 40]: the fuzz budget the bricks page names, one
CPU-hour on the parser side of both roles of the TLS brick.

The corpus is the sixteen canonical sessions `mo-tls-fuzz` records (MO_FUZZ_RECORD): each suite,
each key type, with and without ALPN, with and without a HelloRetryRequest, every record and
every plaintext handshake message each side sent. Each input is one of them mutated from the
seed, one to four times: bits flipped, bytes set to the values parsers trip on (0, 1, 0x7f, 0x80,
0xff), a run of bytes inserted, deleted, or repeated, a length field (a record's 16 bits, a
handshake message's 24) set to its bounds, a frame cut short, dropped, duplicated, or taken from
another session. `mo-tls-fuzz` (bench/step37/fuzz.zig) feeds each input to a fresh server
connection and a fresh client connection at every state of the handshake and after it, both as
records and, behind the AEAD, as handshake messages.

A crash is a signal, an abort, a Zig panic (the driver is built ReleaseSafe), a step that runs
past its two seconds (the driver's watchdog, exit 3), or a batch that outlives guard.py. Before
the hour, a planted panic and a planted hang are each run and must each be seen as a crash. A batch
that crashes is run again an input at a time, and each input that crashes alone is kept under
`work/fuzz-<seed>/crashes/`. The run stops when the driver has used `--minutes` of CPU (user and
system, from the kernel's accounting of the children), and `work/fuzz-<seed>.txt`, which begins
with the date and `uptime`, has the count.
"""

from __future__ import annotations

import argparse
import os
import random
import resource
import struct
import subprocess
import time

import common37 as c

INTERESTING = [0, 1, 0x7F, 0x80, 0xFF]


def frames_of(data: bytes) -> tuple[int, list[tuple[int, bytes]]]:
    case = data[4]
    at = 5
    out = []
    while at + 5 <= len(data):
        kind = data[at]
        (n,) = struct.unpack("<I", data[at + 1:at + 5])
        at += 5
        out.append((kind, data[at:at + n]))
        at += n
    return case, out


def encode(case: int, frames: list[tuple[int, bytes]]) -> bytes:
    out = bytearray(b"MOFZ")
    out.append(case)
    for kind, b in frames:
        out.append(kind & 0xFF)
        out += struct.pack("<I", len(b))
        out += b
    return bytes(out)


def mutate(rng: random.Random, corpus: list[bytes]) -> tuple[bytes, list[str]]:
    case, frames = frames_of(rng.choice(corpus))
    frames = list(frames)
    done = []
    for _ in range(rng.randint(1, 4)):
        if not frames:
            break
        i = rng.randrange(len(frames))
        kind, b = frames[i]
        b = bytearray(b)
        op = rng.choice(["flip", "set", "insert", "delete", "repeat", "length", "cut", "drop", "dup",
                         "splice", "kind"])
        if op == "flip" and b:
            for _ in range(rng.randint(1, 4)):
                b[rng.randrange(len(b))] ^= 1 << rng.randrange(8)
        elif op == "set" and b:
            b[rng.randrange(len(b))] = rng.choice(INTERESTING)
        elif op == "insert":
            at = rng.randint(0, len(b))
            b[at:at] = bytes(rng.randrange(256) for _ in range(rng.randint(1, 32)))
        elif op == "delete" and b:
            at = rng.randrange(len(b))
            del b[at:at + rng.randint(1, 32)]
        elif op == "repeat" and b:
            at = rng.randrange(len(b))
            piece = b[at:at + rng.randint(1, 64)]
            b[at:at] = piece * rng.randint(1, 8)
        elif op == "length" and len(b) >= 5:
            # A record header's length (bytes 3..5) or a handshake message's (bytes 1..4).
            if kind in (0, 1):
                b[3:5] = struct.pack(">H", rng.choice([0, 1, 0x3FFF, 0x4000, 0x4100, 0x4101, 0xFFFF]))
            else:
                b[1:4] = rng.choice([0, 1, 0x3FFF, 0x4000, 0xFFFFFF]).to_bytes(3, "big")
        elif op == "cut" and b:
            del b[rng.randrange(len(b)):]
        elif op == "drop":
            frames.pop(i)
            done.append(op)
            continue
        elif op == "dup":
            frames.insert(i, (kind, bytes(b)))
        elif op == "splice":
            _, other = frames_of(rng.choice(corpus))
            if other:
                okind, ob = rng.choice(other)
                frames.insert(i, (kind, ob))
        elif op == "kind":
            kind = rng.randrange(4)
        frames[i] = (kind, bytes(b))
        done.append(op)
    return encode(case, frames), done


def cpu_seconds() -> float:
    r = resource.getrusage(resource.RUSAGE_CHILDREN)
    return r.ru_utime + r.ru_stime


def run(listing: str, seconds: float) -> tuple[int, str]:
    ran = subprocess.run(c.guarded([c.FUZZ], seconds), env={**os.environ, "MO_FUZZ_INPUTS": listing},
                         capture_output=True, text=True)
    return ran.returncode, ran.stdout + ran.stderr


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--minutes", type=float, default=60.0)
    ap.add_argument("--batch", type=int, default=40)
    args = ap.parse_args()
    c.ensure_tools()
    work = c.WORK / f"fuzz-{args.seed}"
    corpus_dir = work / "corpus"
    crash_dir = work / "crashes"
    batch_dir = work / "batch"
    for d in (corpus_dir, crash_dir, batch_dir):
        d.mkdir(parents=True, exist_ok=True)
    rec = subprocess.run(c.guarded([c.FUZZ], 120), env={**os.environ, "MO_FUZZ_RECORD": str(corpus_dir)},
                         capture_output=True, text=True)
    if rec.returncode != 0:
        raise SystemExit(f"the driver did not record its corpus:\n{rec.stdout}{rec.stderr}")
    corpus = [p.read_bytes() for p in sorted(corpus_dir.glob("case-*.bin"))]
    if len(corpus) != 16:
        raise SystemExit(f"the corpus has {len(corpus)} sessions, not 16")

    out = (c.WORK / f"fuzz-{args.seed}.txt").open("w")
    out.write(c.stamp())
    out.write(f"fuzz.py --seed {args.seed} --minutes {args.minutes} --batch {args.batch}\n")
    # The detector, checked before the hour: a planted panic (case byte 0xEE) and a planted hang
    # (0xED) among good inputs must each fail their batch; the hour does not start otherwise.
    for planted, name in ((0xEE, "panic"), (0xED, "hang")):
        p = batch_dir / f"planted-{name}.bin"
        p.write_bytes(b"MOFZ" + bytes([planted]))
        listing = batch_dir / "planted.txt"
        listing.write_text(f"{corpus_dir / 'case-00.bin'}\n{p}\n")
        code, text = run(str(listing), 60)
        seen = code != 0
        out.write(f"self-check: a planted {name}: exit {code}, {'counted as a crash' if seen else 'NOT SEEN'}\n")
        if not seen:
            raise SystemExit(f"the planted {name} was not seen: the detector does not work")
    out.flush()
    rng = random.Random(args.seed)
    budget = args.minutes * 60
    cpu0 = cpu_seconds()
    t0 = time.time()
    inputs = crashes = batches = 0
    ops: dict[str, int] = {}
    while cpu_seconds() - cpu0 < budget:
        paths = []
        for k in range(args.batch):
            data, done = mutate(rng, corpus)
            for op in done:
                ops[op] = ops.get(op, 0) + 1
            p = batch_dir / f"in-{k:03d}.bin"
            p.write_bytes(data)
            paths.append(p)
        listing = batch_dir / "list.txt"
        listing.write_text("\n".join(str(p) for p in paths) + "\n")
        code, text = run(str(listing), 300)
        batches += 1
        inputs += len(paths)
        if code != 0:
            # Which input: each again, alone.
            for p in paths:
                one = batch_dir / "one.txt"
                one.write_text(f"{p}\n")
                code1, text1 = run(str(one), 60)
                if code1 != 0:
                    crashes += 1
                    kept = crash_dir / f"crash-{crashes:03d}.bin"
                    kept.write_bytes(p.read_bytes())
                    (crash_dir / f"crash-{crashes:03d}.txt").write_text(f"exit {code1}\n{text1[-4000:]}")
                    out.write(f"CRASH {kept.name}: exit {code1}\n")
                    out.flush()
                    print(f"CRASH {kept.name}: exit {code1}", flush=True)
        if batches % 25 == 0:
            line = f"{inputs} inputs, {crashes} crashes, {cpu_seconds() - cpu0:.0f} CPU s, {time.time() - t0:.0f} s"
            out.write(line + "\n")
            out.flush()
            print(line, flush=True)
    cpu = cpu_seconds() - cpu0
    summary = (f"{inputs} inputs in {batches} batches, seed {args.seed}: {crashes} crashes; "
               f"{cpu:.0f} CPU s ({cpu / 60:.1f} min), {time.time() - t0:.0f} s wall")
    out.write("# " + summary + "\n")
    out.write("# mutations: " + ", ".join(f"{k} {v}" for k, v in sorted(ops.items())) + "\n")
    out.write(c.stamp())
    out.close()
    print(summary)


if __name__ == "__main__":
    main()
