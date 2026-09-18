"""linux.py [--best-of 5] [--trees label=toolchain,...]: `measure.py`'s windows on Linux, where the
delayed ACK that Nagle's algorithm waits for lives (macOS's loopback shows none: step 38's
RESULTS.md). On the Mac, each tree's `mo` is cross-compiled for aarch64 Linux (`zig build
-Dtarget=aarch64-linux-musl`), and the echoes and `window-dial.mo` are built with each tree's own
`mo build --target aarch64-linux-musl`; then this script runs itself inside a Linux container
(OrbStack's Docker, `python:3.13-alpine`, 4 GB of memory) as `--inside`, which times each window
under `mo run` and as a binary, the best of five, each process with a timeout. The table goes to
`work/linux.txt` with the date, the host's `uptime`, and the container's `uname -r` at its head.
"""

from __future__ import annotations

import argparse
import datetime
import os
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
# Inside the container the script is a copy at /w, with no tree around it.
ROOT = HERE.parents[2] if len(HERE.parents) > 2 else HERE
WORK = HERE / "work"
GUARD = [sys.executable, str(HERE.parent / "step36" / "guard.py")]
SOURCES = {"plain-echo": HERE.parent / "step36" / "plain-echo.mo",
           "tls-echo": ROOT / "examples" / "effects" / "tls-echo.mo",
           "window-dial": HERE / "window-dial.mo"}
LINES = 3200
IMAGE = "python:3.13-alpine"


def stamp() -> str:
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    up = subprocess.run(["uptime"], capture_output=True, text=True).stdout.strip()
    return f"{now}\n{up}\n"


def guarded(cmd: list, seconds: float) -> list[str]:
    return GUARD + [str(seconds), "--"] + [str(c) for c in cmd]


def table(rows: list[tuple], header: tuple) -> str:
    widths = [max(len(str(r[i])) for r in [header] + rows) for i in range(len(header))]
    line = lambda r: "| " + " | ".join(str(c).ljust(w) for c, w in zip(r, widths)) + " |"
    return "\n".join([line(header), "|" + "|".join("-" * (w + 2) for w in widths) + "|"] + [line(r) for r in rows])


def prepare(label: str, toolchain: Path) -> None:
    """work/linux/<label>/: `mo` for Linux, and the three programs built for Linux by the Mac's."""
    out = WORK / "linux" / label
    if not (out / "bin" / "mo").exists():
        ran = subprocess.run(guarded(["zig", "build", "-Dtarget=aarch64-linux-musl", "--prefix", out], 1800),
                             cwd=toolchain, capture_output=True, text=True)
        if ran.returncode != 0:
            raise SystemExit(f"{label}: the Linux mo failed:\n{ran.stderr[-2000:]}")
    place = out / "build"
    place.mkdir(parents=True, exist_ok=True)
    for name, source in SOURCES.items():
        ran = subprocess.run(guarded([toolchain / "zig-out" / "bin" / "mo", "build", "--target", "aarch64-linux-musl",
                                      source], 900), cwd=place, capture_output=True, text=True)
        if ran.returncode != 0:
            raise SystemExit(f"{label}: mo build --target {source} failed:\n{ran.stdout}{ran.stderr}")
        shutil.copy(place / "zig-out" / "mo-build" / name / name, out / name)
        # The copy runs with no .mo.ids beside it, so its verified: line (which only mo test
        # --write records) is left off, as `mo run` would refuse it.
        text = source.read_text()
        (out / f"{name}.mo").write_text(text[:text.index("\nverified:") + 1] if "\nverified:" in text else text)
    tls = out / "tls"
    tls.mkdir(exist_ok=True)
    for pem in ("cert.pem", "key.pem", "root.pem"):
        shutil.copy(ROOT / "examples" / "effects" / "tls" / pem, tls / pem)


# ---- inside the container


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def run_inside(labels: list[str], best_of: int) -> None:
    base = Path("/w")
    rows = []
    for label in labels:
        tree = base / label
        mo = tree / "bin" / "mo"
        for runtime in ("run", "binary"):
            for over in ("plain", "tls"):
                echo = "plain-echo" if over == "plain" else "tls-echo"
                port = free_port()
                argv = [mo, "run", tree / f"{echo}.mo", "--", port, 3_600_000] if runtime == "run" \
                    else [tree / echo, port, 3_600_000]
                server = subprocess.Popen([str(a) for a in argv], cwd=tree, stdout=subprocess.DEVNULL,
                                          stderr=subprocess.DEVNULL)
                try:
                    for _ in range(400):
                        try:
                            socket.create_connection(("127.0.0.1", port), timeout=0.2).close()
                            break
                        except OSError:
                            time.sleep(0.05)
                    for window in (1, 16, 256):
                        args = ["127.0.0.1", port, LINES, window, over, tree / "tls" / "root.pem"]
                        dial = [mo, "run", tree / "window-dial.mo", "--", *args] if runtime == "run" \
                            else [tree / "window-dial", *args]
                        sent = LINES // window * window * 4096
                        best = None
                        for _ in range(best_of):
                            t0 = time.perf_counter()
                            ran = subprocess.run([str(a) for a in dial], cwd=tree, capture_output=True, text=True,
                                                 timeout=300)
                            took = time.perf_counter() - t0
                            if ran.stdout.strip() != f"{sent} bytes back":
                                raise SystemExit(f"window-dial said {ran.stdout!r} {ran.stderr[-500:]!r}")
                            best = took if best is None else min(best, took)
                        load = Path("/proc/loadavg").read_text().split()[:3]
                        rows.append((label, runtime, over, window, f"{best:.3f} s", f"{sent / best / 1e6:.1f}",
                                     " ".join(load)))
                        print(rows[-1], flush=True)
                finally:
                    server.terminate()
                    try:
                        server.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        server.kill()
    print("TABLE")
    print(table(rows, ("mo", "runtime", "over", "window", "time", "MB/s one way", "load (container)")))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--best-of", type=int, default=5)
    ap.add_argument("--trees", default="after=../..")
    ap.add_argument("--inside", default="")
    ap.add_argument("--out", default="linux.txt")
    args = ap.parse_args()
    if args.inside:
        run_inside(args.inside.split(","), args.best_of)
        return
    labels = []
    for spec in args.trees.split(","):
        label, path = spec.split("=", 1)
        prepare(label, (HERE / path).resolve() if not os.path.isabs(path) else Path(path))
        labels.append(label)
    head = stamp()
    shutil.copy(__file__, WORK / "linux" / "linux.py")
    ran = subprocess.run(guarded(["docker", "run", "--rm", "--memory", "4g", "-v", f"{WORK / 'linux'}:/w", IMAGE,
                                  "sh", "-c", f"uname -r; python3 /w/linux.py --inside {','.join(labels)} "
                                  f"--best-of {args.best_of}"], 3600), capture_output=True, text=True)
    if ran.returncode != 0:
        raise SystemExit(f"the container run failed:\n{ran.stdout[-3000:]}{ran.stderr[-3000:]}")
    kernel = ran.stdout.splitlines()[0]
    tab = ran.stdout.split("TABLE\n", 1)[1]
    text = (head + f"linux.py --best-of {args.best_of} --trees {args.trees}; container {IMAGE}, Linux {kernel}, "
            f"3,200 lines of 4 KiB, each window written whole and then read back whole\n\n" + tab + "\n" + stamp())
    (WORK / args.out).write_text(text)
    print(text, flush=True)


if __name__ == "__main__":
    main()
