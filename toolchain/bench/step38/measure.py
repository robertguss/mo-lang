"""measure.py [--best-of 5] [--parts windows,echo,duplex,jobq] [--trees label=toolchain,...]: step
38's numbers, each tree's `mo` against itself, the best of five, with the date and `uptime` at the
head of the output (`work/measure.txt`) and the load average beside each table.

  windows  3,200 lines of 4 KiB through a Mo-to-Mo connection, `window-dial.mo` writing a window
           of 1, 16, or 256 lines whole and then reading the window back whole, to step 36's
           `plain-echo.mo` or `examples/effects/tls-echo.mo` under the same runtime: the write-
           then-read pattern that waits out the peer's delayed ACK under Nagle's algorithm
  echo     `mo-bench --network`'s `echo-1k` and `echo-1k-c` (1,000 round trips of one line)
  duplex   `examples/effects/duplex.mo` whole under `mo run` and as a binary: four legs of 1,600
           lines each way on one connection, and the Busy checks' pauses (about 0.3 s of waits)
  jobq     `mo build examples/programs/jobq` warm, and its binary's size

A tree is a toolchain folder whose `zig-out/bin` holds `mo` and `mo-bench`: `--trees
before=work/trees/<sha>/toolchain,after=../..` (the default is this tree alone, as `after`).
`--worktree label=<commit>` makes one first, under work/trees/, and builds it. Every process runs
under step 36's guard.py.
"""

from __future__ import annotations

import argparse
import datetime
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
TOOLCHAIN = ROOT / "toolchain"
EFFECTS = ROOT / "examples" / "effects"
GUARD = [sys.executable, str(HERE.parent / "step36" / "guard.py")]
WORK = HERE / "work"
PLAIN = HERE.parent / "step36" / "plain-echo.mo"
TLS_ECHO = EFFECTS / "tls-echo.mo"
DIAL = HERE / "window-dial.mo"
DUPLEX = EFFECTS / "duplex.mo"
ROOTS = EFFECTS / "tls" / "root.pem"
LINES = 3200


def stamp() -> str:
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    up = subprocess.run(["uptime"], capture_output=True, text=True).stdout.strip()
    return f"{now}\n{up}\n"


def load() -> str:
    up = subprocess.run(["uptime"], capture_output=True, text=True).stdout
    return up.rsplit("averages:", 1)[-1].rsplit("average:", 1)[-1].strip()


def guarded(cmd: list, seconds: float) -> list[str]:
    return GUARD + [str(seconds), "--"] + [str(c) for c in cmd]


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def table(rows: list[tuple], header: tuple) -> str:
    widths = [max(len(str(r[i])) for r in [header] + rows) for i in range(len(header))]
    line = lambda r: "| " + " | ".join(str(c).ljust(w) for c, w in zip(r, widths)) + " |"
    return "\n".join([line(header), "|" + "|".join("-" * (w + 2) for w in widths) + "|"] + [line(r) for r in rows])


class Tree:
    def __init__(self, label: str, toolchain: Path):
        self.label = label
        self.toolchain = toolchain.resolve()
        self.mo = self.toolchain / "zig-out" / "bin" / "mo"
        self.bench = self.toolchain / "zig-out" / "bin" / "mo-bench"
        self.place = WORK / f"build-{label}"

    def build(self, source: Path) -> Path:
        self.place.mkdir(parents=True, exist_ok=True)
        ran = subprocess.run(guarded([self.mo, "build", source], 900), cwd=self.place, capture_output=True, text=True)
        if ran.returncode != 0:
            raise SystemExit(f"{self.label}: mo build {source} failed:\n{ran.stdout}{ran.stderr}")
        return self.place / "zig-out" / "mo-build" / source.stem / source.stem


def timed(argv: list, cwd: Path, seconds: float = 300) -> tuple[float, str]:
    t0 = time.perf_counter()
    ran = subprocess.run(guarded(argv, seconds), cwd=cwd, capture_output=True, text=True)
    took = time.perf_counter() - t0
    if ran.returncode != 0:
        raise SystemExit(f"{argv} exited {ran.returncode}:\n{ran.stdout}{ran.stderr}")
    return took, ran.stdout.strip()


def start_echo(tree: Tree, runtime: str, over: str, binaries: dict) -> tuple[subprocess.Popen, int]:
    port = free_port()
    source = PLAIN if over == "plain" else TLS_ECHO
    argv = [tree.mo, "run", source, "--", port, 3_600_000] if runtime == "run" else [binaries[source], port, 3_600_000]
    log = (WORK / f"echo-{tree.label}-{runtime}-{over}.log").open("w")
    log.write(stamp())
    log.flush()
    proc = subprocess.Popen(guarded(argv, 3600), cwd=EFFECTS, stdout=log, stderr=subprocess.STDOUT)
    deadline = time.time() + 30
    while time.time() < deadline:
        if proc.poll() is not None:
            raise SystemExit(f"the echo exited before it listened ({proc.returncode})")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return proc, port
        except OSError:
            time.sleep(0.05)
    raise SystemExit(f"nothing listened on {port}")


def stop(proc: subprocess.Popen) -> None:
    # SIGTERM, which guard.py forwards; a SIGKILL would orphan the process under it.
    proc.terminate()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=10)


def windows(trees: list[Tree], best_of: int) -> list[tuple]:
    rows = []
    for tree in trees:
        binaries = {s: tree.build(s) for s in (PLAIN, TLS_ECHO)}
        dial_bin = tree.build(DIAL)
        for runtime in ("run", "binary"):
            for over in ("plain", "tls"):
                proc, port = start_echo(tree, runtime, over, binaries)
                try:
                    for window in (1, 16, 256):
                        args = ["127.0.0.1", port, LINES, window, over, ROOTS]
                        argv = [tree.mo, "run", DIAL, "--", *args] if runtime == "run" else [dial_bin, *args]
                        # Whole windows only: 3,200 lines are 12 windows of 256 (3,072 lines).
                        sent = LINES // window * window * 4096
                        best = None
                        for _ in range(best_of):
                            took, said = timed(argv, WORK, 600)
                            if said != f"{sent} bytes back":
                                raise SystemExit(f"window-dial said {said!r}")
                            best = took if best is None else min(best, took)
                        rows.append((tree.label, runtime, over, window, f"{best:.3f} s",
                                     f"{sent / best / 1e6:.1f}", load()))
                        print(rows[-1], flush=True)
                finally:
                    stop(proc)
    return rows


def echo(trees: list[Tree], best_of: int) -> list[tuple]:
    rows = []
    for tree in trees:
        ran = subprocess.run(guarded([tree.bench, ROOT / "examples", best_of, "--network"], 1800), cwd=tree.toolchain,
                             capture_output=True, text=True)
        if ran.returncode != 0:
            raise SystemExit(f"mo-bench failed:\n{ran.stdout}{ran.stderr}")
        for line in ran.stdout.splitlines():
            if line.startswith("echo-1k"):
                # `--network` prints the row and its best total: 1,000 round trips.
                parts = line.split()
                rows.append((tree.label, parts[0], f"{int(parts[1]):,} µs", f"{int(parts[1]) / 1000:.1f} µs", load()))
                print(rows[-1], flush=True)
    return rows


def duplex(trees: list[Tree], best_of: int) -> list[tuple]:
    rows = []
    want = (EFFECTS / "duplex.expected").read_text().strip()
    for tree in trees:
        binary = tree.build(DUPLEX)
        for runtime in ("run", "binary"):
            argv = [tree.mo, "run", DUPLEX] if runtime == "run" else [binary]
            best = None
            for _ in range(best_of):
                took, said = timed(argv, EFFECTS, 300)
                if said != want:
                    raise SystemExit(f"duplex said {said!r}")
                best = took if best is None else min(best, took)
            rows.append((tree.label, runtime, f"{best:.3f} s", load()))
            print(rows[-1], flush=True)
    return rows


def jobq(trees: list[Tree], best_of: int) -> list[tuple]:
    rows = []
    main = ROOT / "examples" / "programs" / "jobq" / "main.mo"
    for tree in trees:
        place = WORK / f"jobq-{tree.label}"
        shutil.rmtree(place, ignore_errors=True)
        place.mkdir(parents=True)
        cold, _ = timed([tree.mo, "build", main], place, 1800)
        warm = min(timed([tree.mo, "build", main], place, 600)[0] for _ in range(best_of))
        size = (place / "zig-out" / "mo-build" / "jobq" / "jobq").stat().st_size
        rows.append((tree.label, f"{warm:.2f} s", f"{cold:.1f} s", f"{size:,} bytes", load()))
        print(rows[-1], flush=True)
    return rows


def worktree(label: str, commit: str) -> Path:
    tree = WORK / "trees" / commit
    toolchain = tree / "toolchain"
    if not (toolchain / "zig-out" / "bin" / "mo-bench").exists():
        if not tree.exists():
            subprocess.run(["git", "worktree", "add", "-f", "--detach", tree, commit], cwd=ROOT, check=True,
                           capture_output=True)
        # `zig build` installs mo-bench too; `zig build bench` would also run all of it.
        ran = subprocess.run(guarded(["zig", "build"], 1800), cwd=toolchain, capture_output=True, text=True)
        if ran.returncode != 0:
            raise SystemExit(f"zig build at {commit} failed:\n{ran.stderr[-2000:]}")
    return toolchain


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--best-of", type=int, default=5)
    ap.add_argument("--parts", default="windows,echo,duplex,jobq")
    ap.add_argument("--trees", default="")
    ap.add_argument("--worktree", action="append", default=[])
    ap.add_argument("--out", default="measure.txt")
    args = ap.parse_args()
    WORK.mkdir(exist_ok=True)
    trees = []
    for spec in args.worktree:
        label, commit = spec.split("=", 1)
        trees.append(Tree(label, worktree(label, commit)))
    for spec in filter(None, args.trees.split(",")):
        label, path = spec.split("=", 1)
        trees.append(Tree(label, Path(path)))
    if not trees:
        trees = [Tree("after", TOOLCHAIN)]
    out = [stamp().rstrip("\n"), f"measure.py --best-of {args.best_of} --parts {args.parts} "
           + " ".join(f"{t.label}={t.toolchain}" for t in trees), ""]
    print("\n".join(out), flush=True)

    def emit(title: str, rows: list, header: tuple) -> None:
        block = [f"## {title} (load average at the start {load()}; each row's beside it)", "", table(rows, header), ""]
        out.extend(block)
        print("\n".join(block), flush=True)

    parts = args.parts.split(",")
    if "windows" in parts:
        emit(f"{LINES:,} lines of 4 KiB, each window written whole and then read back whole, best of {args.best_of}",
             windows(trees, args.best_of), ("mo", "runtime", "over", "window", "time", "MB/s one way", "load"))
    if "echo" in parts:
        emit(f"mo-bench --network's echo-1k rows, best of {args.best_of}", echo(trees, args.best_of),
             ("mo", "row", "1,000 round trips", "a round trip", "load"))
    if "duplex" in parts:
        emit(f"examples/effects/duplex.mo whole, best of {args.best_of}", duplex(trees, args.best_of),
             ("mo", "runtime", "time", "load"))
    if "jobq" in parts:
        emit(f"mo build examples/programs/jobq, warm (best of {args.best_of}) and cold, and the binary's size",
             jobq(trees, args.best_of), ("mo", "warm", "cold (bricks compiled)", "binary", "load"))
    (WORK / args.out).write_text("\n".join(out) + "\n" + stamp())


if __name__ == "__main__":
    main()
