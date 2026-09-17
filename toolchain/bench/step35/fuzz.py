"""Step 35's fuzz harness: PHC strings and hex text, mutated at a fixed seed, fed to
`Password.verify?` and `Hash.from_hex` through driver.mo built as a binary, in batches, for a
time budget. A crash is a batch that does not answer every line or exits other than 0; each such
batch is replayed line by line and every line that crashes alone is counted and kept.

    uv run python fuzz.py [--minutes 10] [--seed 35] [--mo ../../zig-out/bin/mo]
"""

import argparse
import os
import random
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
GUARD = os.path.join(HERE, "guard.py")

# Password.hash("password", "0123456789abcdef") and ("", sixteen 0x02 bytes).
SEEDS_PHC = [
    "$argon2id$v=19$m=65536,t=3,p=1$MDEyMzQ1Njc4OWFiY2RlZg$2vFngNy3PoYhRil/oXuBuGtIDzPAtn2u8PLHyAnFeXs",
    "$argon2id$v=19$m=65536,t=3,p=1$AgICAgICAgICAgICAgICAg$/lJatZ7TuTaSDjIMDIEqRyHH6CE7S9S5YMnxW0CclUA",
    "$argon2i$v=19$m=4096,t=3,p=1$c29tZXNhbHQ$iWh06vD8Fy27wf9npn6FXWiCX4K6pW6Ue1Bnzz07Z8A",
    "$scrypt$ln=15,r=8,p=1$c2FsdA$aGFzaA",
    "$argon2id$m=65536,t=3,p=1$MDEyMzQ1Njc4OWFiY2RlZg$2vFngNy3PoYhRil/oXuBuGtIDzPAtn2u8PLHyAnFeXs",
]
SEEDS_HEX = ["", "00", "deadBEEF", "0123456789abcdefABCDEF", "a", "zz", "0x10", "ff" * 64]
ALPHABET = "$=,0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ+/-_.:v" + "\x00\t é€𝄞"
NUMBERS = ["0", "1", "19", "-1", "65536", "4294967295", "4294967296", "18446744073709551616", "9" * 40, ""]


def mutate(rng, s):
    for _ in range(rng.randint(1, 4)):
        op = rng.randrange(9)
        i = rng.randint(0, len(s))
        if op == 0 and s:
            s = s[: i - 1] + rng.choice(ALPHABET) + s[i:]
        elif op == 1:
            s = s[:i] + rng.choice(ALPHABET) + s[i:]
        elif op == 2 and s:
            j = rng.randint(i, len(s))
            s = s[:i] + s[j:]
        elif op == 3 and s:
            j = rng.randint(i, len(s))
            s = s[:i] + s[i:j] * rng.randint(2, 4) + s[j:]
        elif op == 4:
            s = s[:i] + rng.choice(NUMBERS) + s[i:]
        elif op == 5:
            # A parameter's number replaced whole.
            for key in ("m=", "t=", "p=", "v="):
                if key in s and rng.random() < 0.5:
                    a = s.index(key) + 2
                    b = a
                    while b < len(s) and s[b].isdigit():
                        b += 1
                    s = s[:a] + rng.choice(NUMBERS) + s[b:]
        elif op == 6:
            s = s + "$" * rng.randint(1, 3)
        elif op == 7 and s:
            s = s.swapcase() if rng.random() < 0.5 else s[::-1]
        elif op == 8:
            other = rng.choice(SEEDS_PHC + SEEDS_HEX)
            s = s[:i] + other[rng.randint(0, len(other)) :]
    return s.replace("\n", "")


def line_for(rng):
    if rng.random() < 0.5:
        text = mutate(rng, rng.choice(SEEDS_PHC))
        password = rng.choice(["password", "", "pass word", "é" * rng.randint(0, 40)])
        return f"password_verify {password.encode().hex()} {text.encode('utf-8', 'surrogatepass').hex()}"
    text = mutate(rng, rng.choice(SEEDS_HEX))
    return f"from_hex {text.encode('utf-8', 'surrogatepass').hex()}"


def guarded(seconds, argv, **kw):
    return subprocess.run([sys.executable, GUARD, str(seconds), "--", *argv], capture_output=True, text=True, **kw)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--minutes", type=float, default=10)
    ap.add_argument("--seed", type=int, default=35)
    ap.add_argument("--batch", type=int, default=400)
    ap.add_argument("--mo", default=os.path.join(HERE, "../../zig-out/bin/mo"))
    ap.add_argument("--work", default=os.path.join(HERE, "work"))
    args = ap.parse_args()
    os.makedirs(args.work, exist_ok=True)
    built = guarded(900, [os.path.abspath(args.mo), "build", "-o", "driver", os.path.join(HERE, "driver.mo")], cwd=args.work)
    if built.returncode != 0:
        sys.exit(f"mo build failed:\n{built.stdout}{built.stderr}")
    binary = os.path.join(args.work, "zig-out/mo-build/driver/driver")
    rng = random.Random(args.seed)
    path = os.path.join(args.work, "fuzz.txt")
    deadline = time.time() + args.minutes * 60
    inputs = batches = crashes = verified = 0
    crashed = []
    while time.time() < deadline:
        lines = [line_for(rng) for _ in range(args.batch)]
        with open(path, "w") as f:
            f.write("".join(line + "\n" for line in lines))
        ran = guarded(600, [binary, path], cwd=args.work)
        got = ran.stdout.split("\n")[:-1]
        batches += 1
        inputs += len(lines)
        verified += sum(1 for g in got if g == "true")
        if ran.returncode == 0 and len(got) == len(lines):
            continue
        for line in lines:
            with open(path, "w") as f:
                f.write(line + "\n")
            alone = guarded(60, [binary, path], cwd=args.work)
            if alone.returncode != 0 or alone.stdout.count("\n") != 1:
                crashes += 1
                crashed.append((line, alone.returncode, alone.stderr[-500:]))
    with open(os.path.join(args.work, "fuzz-crashes.txt"), "w") as f:
        for line, rc, err in crashed:
            f.write(f"{line}\n  exit {rc}: {err}\n")
    print(f"seed {args.seed}, {args.minutes:g} min: {inputs} inputs in {batches} batches, {verified} verified true, {crashes} crashes")
    sys.exit(1 if crashes else 0)


if __name__ == "__main__":
    main()
