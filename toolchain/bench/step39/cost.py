"""cost.py [--before ../../mo-lang-worktrees/step39-before] [--best-of 5]: part A's cost, the chain
check before and after step 39, each key type.

`cost.zig` is built twice, ReleaseSafe as the runtimes build the brick: against this tree's
`src/bricks/tls.zig`, and against the tree before step 39 (`d6534b3`), whose `checkChain` is made
`pub` in a copy under work/ (the one change; it was private then). Each binary runs 20,000 chain
checks and 2,000 handshakes a key type, five times; the best of five is kept (the lowest µs a
check, the most handshakes a second). The date, `uptime`, and the top of `ps` head the output,
`work/cost.txt`. Every process runs under step 36's guard.py.
"""

from __future__ import annotations

import argparse
import datetime
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOLCHAIN = HERE.parents[1]
WORK = HERE / "work"
GUARD = [sys.executable, str(HERE.parent / "step36" / "guard.py")]
FIX = TOOLCHAIN.parent / "examples" / "effects" / "tls"


def stamp() -> str:
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    up = subprocess.run(["uptime"], capture_output=True, text=True).stdout.strip()
    top = subprocess.run(["ps", "-Ao", "pid,pcpu,rss,comm", "-r"], capture_output=True, text=True).stdout.splitlines()[:6]
    return f"{now}\n{up}\n" + "\n".join(top) + "\n"


def build(brick: Path, out: Path) -> Path:
    argv = ["zig", "build-exe", "-O", "ReleaseSafe", "-lc", "--dep", "tls_brick", f"-Mroot={HERE / 'cost.zig'}",
            f"-Mtls_brick={brick}", f"-femit-bin={out}"]
    subprocess.run(GUARD + ["900", "--"] + argv, check=True, cwd=WORK)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--before", default=str(TOOLCHAIN.parents[1] / "mo-lang-worktrees" / "step39-before"))
    ap.add_argument("--best-of", type=int, default=5)
    ap.add_argument("--calls", type=int, default=20000)
    ap.add_argument("--handshakes", type=int, default=2000)
    args = ap.parse_args()
    WORK.mkdir(exist_ok=True)
    before_src = (Path(args.before) / "toolchain" / "src" / "bricks" / "tls.zig").read_text()
    before_src, n = re.subn(r"^fn checkChain\(", "pub fn checkChain(", before_src, flags=re.M)
    assert n == 1, "the before tree's checkChain was not found"
    (WORK / "tls-before.zig").write_text(before_src)
    bins = {
        "before (d6534b3)": build(WORK / "tls-before.zig", WORK / "mo-tls-cost-before"),
        "after": build(TOOLCHAIN / "src" / "bricks" / "tls.zig", WORK / "mo-tls-cost-after"),
    }
    best: dict[tuple[str, str], list[float]] = {}
    for _ in range(args.best_of):
        for label, binary in bins.items():
            ran = subprocess.run(GUARD + ["600", "--", str(binary), str(FIX), str(args.calls), str(args.handshakes)],
                                 capture_output=True, text=True, check=True)
            for line in ran.stdout.splitlines():
                key, us, hs = line.split()
                old = best.get((label, key))
                best[(label, key)] = [min(float(us), old[0]) if old else float(us), max(float(hs), old[1]) if old else float(hs)]
    rows = [stamp(), f"cost.py --best-of {args.best_of} --calls {args.calls} --handshakes {args.handshakes}", "",
            "| brick | key | µs a chain check (chain of three) | handshakes a second (in memory) |", "|---|---|---:|---:|"]
    for (label, key), (us, hs) in best.items():
        rows.append(f"| {label} | {'Ed25519' if key == 'ed25519' else 'P-256'} | {us:,.1f} | {hs:,.0f} |")
    text = "\n".join(rows) + "\n"
    (WORK / "cost.txt").write_text(text)
    print(text)


if __name__ == "__main__":
    main()
