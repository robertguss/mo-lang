"""measure.py [--best-of 5] [--handshakes 300] [--mib 100]: step 37's numbers, both runtimes,
the best of five each, with the date and `uptime` at the head of the output
(`work/measure.txt`) and the load average beside each table.

  client        handshakes a second, the brick's client (`tls-dial.mo`, under `mo run` and as a
                binary) against `openssl s_server`, each key type, the chain of three checked
  mo-to-mo      handshakes a second, `tls-dial.mo` against `tls-echo.mo`, each runtime against
                itself
  bulk          100 MiB through a Mo-to-Mo connection and back, `tls-dial.mo` sending 4 KiB lines
                to `tls-echo.mo` with two windows of 64 in flight, over TLS and over a plain `Conn`
                (step 36's `plain-echo.mo`), in decimal megabytes a second of what went one way
  chain         the chain check's cost: the client's handshakes a second against `s_server`
                presenting the chain of three (leaf, intermediate, trusted root) and presenting a
                self-signed leaf the client trusts itself (made here with `openssl req -x509`)
  build         `mo build examples/programs/jobq` warm, and its binary's size, with the `mo` of
                the commit before step 37 (6f449c9, built in a worktree under work/) and this one

A rate is `count / (t(count) - t(0))`: the same program run with nothing to do is its start-up,
taken off. Every process runs under step 36's guard.py.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import common37 as c

sys.path.insert(0, str(c.HERE.parent / "step36"))
import common as c36  # noqa: E402

DIAL = c.HERE / "tls-dial.mo"
ECHO = c.ROOT / "examples" / "effects" / "tls-echo.mo"
PLAIN = c.HERE.parent / "step36" / "plain-echo.mo"
BEFORE = "6f449c9"


def mo_exe() -> str:
    return str(c.BIN / "mo")


def build(mo: str, source: Path, into: Path) -> Path:
    into.mkdir(parents=True, exist_ok=True)
    ran = subprocess.run(c.guarded([mo, "build", source], 600), cwd=into, capture_output=True, text=True)
    if ran.returncode != 0:
        raise SystemExit(f"mo build {source} failed:\n{ran.stdout}{ran.stderr}")
    return into / "zig-out" / "mo-build" / source.stem / source.stem


def dial_argv(runtime: str, binary: Path, args: list) -> list:
    args = [str(a) for a in args]
    return [mo_exe(), "run", DIAL, "--"] + args if runtime == "run" else [binary] + args


def timed(argv: list, cwd: Path, seconds: float = 600) -> tuple[float, str]:
    t0 = time.perf_counter()
    ran = subprocess.run(c.guarded(argv, seconds), cwd=cwd, capture_output=True, text=True)
    took = time.perf_counter() - t0
    if ran.returncode != 0:
        raise SystemExit(f"{argv} exited {ran.returncode}:\n{ran.stdout}{ran.stderr}")
    return took, ran.stdout.strip()


def rate(runtime: str, binary: Path, cwd: Path, port: int, count: int, trust: str, best_of: int) -> tuple[float, str]:
    """Handshakes a second: the best of `best_of` runs of `count`, less the best start-up."""
    idle = min(timed(dial_argv(runtime, binary, ["127.0.0.1", port, 0, 0, "tls", trust]), cwd)[0] for _ in range(best_of))
    best = None
    said = ""
    for _ in range(best_of):
        took, said = timed(dial_argv(runtime, binary, ["127.0.0.1", port, count, 0, "tls", trust]), cwd)
        best = took if best is None else min(best, took)
        if said != f"{count} handshakes":
            raise SystemExit(f"the client said {said!r}, not {count} handshakes")
    return count / max(best - idle, 1e-9), said


def s_server(chain: Path, key: Path, work: Path) -> tuple[subprocess.Popen, int]:
    port = c.free_port()
    leaf, rest = c.split_chain(chain, work)
    argv = [c.OPENSSL, "s_server", "-accept", port, "-cert", leaf, "-key", key, "-quiet"]
    if rest:
        argv += ["-cert_chain", rest]
    proc = subprocess.Popen(c.guarded(argv, 3600), stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    c36.wait_for_port(port, proc)
    return proc, port


def stop(proc: subprocess.Popen) -> None:
    # SIGTERM, which guard.py forwards; a SIGKILL would orphan the process under it.
    proc.terminate()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=10)


def self_signed(key: str, work: Path) -> tuple[Path, Path]:
    """A leaf that signs itself, for localhost and 127.0.0.1, of the key type."""
    cert, secret = work / f"self-{key}.pem", work / f"self-{key}-key.pem"
    algo = ["-newkey", "ed25519"] if key == "ed25519" else ["-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256"]
    subprocess.run(c.guarded([c.OPENSSL, "req", "-x509", *algo, "-nodes", "-days", "3650", "-subj", "/CN=localhost",
                              "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1", "-keyout", secret, "-out", cert], 60),
                   check=True, capture_output=True)
    return cert, secret


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--best-of", type=int, default=5)
    ap.add_argument("--handshakes", type=int, default=300)
    ap.add_argument("--mib", type=int, default=100)
    ap.add_argument("--parts", default="client,mo-to-mo,bulk,chain,build")
    args = ap.parse_args()
    parts = args.parts.split(",")
    work = c.WORK / "measure"
    work.mkdir(parents=True, exist_ok=True)
    for key in c.KEYS:
        shutil.copy(c.fixture("root", key), work / f"root{c.KEYS[key]}.pem")
    out = [c.stamp().rstrip("\n"), f"measure.py --best-of {args.best_of} --handshakes {args.handshakes} --mib {args.mib}", ""]
    print("\n".join(out), flush=True)
    dial_bin = build(mo_exe(), DIAL, work / "build")

    def emit(title: str, rows: list, header: tuple) -> None:
        block = [f"## {title} (load average {c.load()})", "", c.table(rows, header), ""]
        out.extend(block)
        print("\n".join(block), flush=True)

    if "client" in parts:
        rows = []
        for key in c.KEYS:
            proc, port = s_server(c.fixture("cert", key), c.fixture("key", key), work)
            try:
                for runtime in ("run", "binary"):
                    r, _ = rate(runtime, dial_bin, work, port, args.handshakes, f"root{c.KEYS[key]}.pem", args.best_of)
                    rows.append((runtime, key, f"{r:.0f}"))
            finally:
                stop(proc)
        emit("The brick's client against openssl s_server, the chain of three checked", rows,
             ("runtime", "key", "handshakes/s"))

    if "mo-to-mo" in parts:
        rows = []
        for runtime in ("run", "binary"):
            for key in c.KEYS:
                server = c36.start_echo(runtime, key, idle_ms=3_600_000, seconds=3600)
                try:
                    r, _ = rate(runtime, dial_bin, work, server.port, args.handshakes, f"root{c.KEYS[key]}.pem", args.best_of)
                    rows.append((runtime, key, f"{r:.0f}"))
                finally:
                    server.stop()
        emit("Mo client to Mo server (tls-dial.mo to tls-echo.mo, each runtime against itself)", rows,
             ("runtime", "key", "handshakes/s"))

    if "bulk" in parts:
        lines = (args.mib << 20) // 4096
        rows = []
        for runtime in ("run", "binary"):
            for over in ("plain", "tls"):
                server = c36.start_echo(runtime, "ed25519", idle_ms=3_600_000, seconds=3600, plain=(over == "plain"))
                try:
                    idle = min(timed(dial_argv(runtime, dial_bin, ["127.0.0.1", server.port, 0, 0, over, "root.pem"]), work)[0]
                               for _ in range(args.best_of))
                    best = None
                    for _ in range(args.best_of):
                        took, said = timed(dial_argv(runtime, dial_bin, ["127.0.0.1", server.port, 0, lines, over, "root.pem"]), work)
                        if said != f"{lines * 4096} bytes back":
                            raise SystemExit(f"the bulk client said {said!r}")
                        best = took if best is None else min(best, took)
                    mbs = (lines * 4096) / (best - idle) / 1e6
                    rows.append((runtime, over, f"{mbs:.1f}"))
                finally:
                    server.stop()
        base = {r[0]: float(r[2]) for r in rows if r[1] == "plain"}
        rows = [(r[0], r[1], r[2], "" if r[1] == "plain" else f"{base[r[0]] / float(r[2]):.1f}×") for r in rows]
        emit(f"{args.mib} MiB through a Mo-to-Mo connection and back (tls-dial.mo to tls-echo.mo / plain-echo.mo), "
             "MB/s = 10^6 bytes a second one way", rows, ("runtime", "over", "MB/s", "against plain"))

    if "chain" in parts:
        rows = []
        for key in c.KEYS:
            cert, secret = self_signed(key, work)
            shutil.copy(cert, work / f"trust-self-{key}.pem")
            for form, chain, keyfile, trust in (
                ("chain of three", c.fixture("cert", key), c.fixture("key", key), f"root{c.KEYS[key]}.pem"),
                ("self-signed leaf", cert, secret, f"trust-self-{key}.pem"),
            ):
                proc, port = s_server(chain, keyfile, work)
                try:
                    for runtime in ("binary", "run"):
                        r, _ = rate(runtime, dial_bin, work, port, args.handshakes, trust, args.best_of)
                        rows.append((runtime, key, form, f"{r:.0f}", f"{1e6 / r:.0f}"))
                finally:
                    stop(proc)
        emit("The chain check's cost: the client's handshakes against openssl s_server", rows,
             ("runtime", "key", "server presents", "handshakes/s", "µs a handshake"))

    if "build" in parts:
        before_tree = c.WORK / "before"
        if not (before_tree / "toolchain" / "zig-out" / "bin" / "mo").exists():
            subprocess.run(["git", "worktree", "add", "-f", "--detach", before_tree, BEFORE], cwd=c.ROOT, check=True,
                           capture_output=True)
            ran = subprocess.run(c.guarded(["zig", "build"], 1800), cwd=before_tree / "toolchain", capture_output=True, text=True)
            if ran.returncode != 0:
                raise SystemExit(f"zig build at {BEFORE} failed:\n{ran.stderr[-2000:]}")
        rows = []
        jobq = c.ROOT / "examples" / "programs" / "jobq" / "main.mo"
        for label, mo in ((f"before ({BEFORE})", str(before_tree / "toolchain" / "zig-out" / "bin" / "mo")), ("after", mo_exe())):
            place = work / f"jobq-{label.split()[0]}"
            shutil.rmtree(place, ignore_errors=True)
            place.mkdir(parents=True)
            cold, _ = timed([mo, "build", jobq], place, 1800)
            warm = min(timed([mo, "build", jobq], place, 600)[0] for _ in range(args.best_of))
            size = (place / "zig-out" / "mo-build" / "jobq" / "jobq").stat().st_size
            rows.append((label, f"{warm:.2f} s", f"{cold:.1f} s", f"{size:,} bytes"))
        emit("mo build examples/programs/jobq, warm (best of five) and cold, and the binary's size", rows,
             ("mo", "warm", "cold (bricks compiled)", "binary"))

    (c.WORK / "measure.txt").write_text("\n".join(out) + "\n" + c.stamp())


if __name__ == "__main__":
    os.environ.setdefault("MO", str(c.BIN / "mo"))
    main()
