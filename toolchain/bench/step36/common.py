"""What every step 36 run shares: where the echo server is, how it is started and stopped, and
how an `openssl s_client` is driven at it.

Nothing here talks TLS itself: OpenSSL 3.0 at /usr/bin/openssl is the client in every run, which
is the point -- the brick is held against an implementation nobody here wrote. OpenSSL is dev-time
tooling and is never linked into `mo` or into a binary it builds (the bricks page).

Every `mo` process, every binary, and every `openssl` is started under `guard.py SECONDS -- cmd`,
a timeout and a 4 GB resident watchdog, so no run of this folder can hang or eat the machine.
"""

from __future__ import annotations

import datetime
import os
import socket
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
GUARD = [sys.executable, str(HERE / "guard.py")]
OPENSSL = "/usr/bin/openssl"
ECHO = ROOT / "examples" / "effects" / "tls-echo.mo"
# The same echo with no handshake between the socket and the reader: the plain baseline.
PLAIN = HERE / "plain-echo.mo"
CERTS = ROOT / "examples" / "effects" / "tls"
WORK = HERE / "work"

SUITES = {
    "aes128gcm": "TLS_AES_128_GCM_SHA256",
    "chacha20": "TLS_CHACHA20_POLY1305_SHA256",
}
# The two key types the brick signs with, each a chain (leaf, intermediate), the leaf's key, and
# the root a client trusts (step 37's gen.sh); the Ed25519 one is what `tls-echo.mo` reads by name.
KEYS = {"ed25519": ("cert.pem", "key.pem", "root.pem"), "p256": ("cert-p256.pem", "key-p256.pem", "root-p256.pem")}


def stamp() -> str:
    """The first two lines of every file this folder writes under work/: the date, and `uptime`
    as it printed (step 37's fix: the load belongs beside every number)."""
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    up = subprocess.run(["uptime"], capture_output=True, text=True).stdout.strip()
    return f"{now}\n{up}\n"


def write_output(name: str, text: str) -> Path:
    """A run's table under work/, stamped, and printed."""
    WORK.mkdir(exist_ok=True)
    path = WORK / name
    path.write_text(stamp() + text + "\n")
    print(text)
    return path


def guarded(cmd: list[str], seconds: float, **kw) -> list[str]:
    return GUARD + [str(seconds), "--"] + [str(c) for c in cmd]


def run(cmd: list[str], seconds: float, **kw) -> subprocess.CompletedProcess:
    return subprocess.run(guarded(cmd, seconds), capture_output=True, **kw)


def mo_exe() -> str:
    return os.environ.get("MO", str(ROOT / "toolchain" / "zig-out" / "bin" / "mo"))


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def build(source: Path) -> str:
    """One of the echoes compiled; its path."""
    name = source.stem
    out = subprocess.run([mo_exe(), "build", str(source)], cwd=ROOT, capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"mo build {source} failed:\n{out.stdout}\n{out.stderr}")
    return str(ROOT / "zig-out" / "mo-build" / name / name)


@dataclass
class Server:
    """A running echo, plain or TLS, under `mo run` or as a binary."""

    proc: subprocess.Popen
    port: int
    log: Path

    def stop(self) -> None:
        # SIGTERM first: guard.py forwards it to the echo and exits as the echo does. A SIGKILL
        # reaches only the guard and leaves the echo running as an orphan (step 37 found one
        # still serving a minute after a handshake run), so it is the last resort.
        self.proc.terminate()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass

    def alive(self) -> bool:
        return self.proc.poll() is None


# Step 36's own pairs, self-signed, as the tree held them before step 37 made cert.pem a chain:
# `handshake.py --pairs step36` serves these, so its numbers can be set beside step 36's.
STEP36_COMMIT = "6f449c9"


def step36_pair(key: str) -> tuple[Path, Path]:
    """Step 36's certificate and key for `key`, from git, into work/ (stamped: PEM readers skip
    what comes before a BEGIN line). The certificate is its own trust anchor."""
    cert, secret, _ = KEYS[key]
    tree = WORK / "step36-pairs"
    tree.mkdir(parents=True, exist_ok=True)
    out = []
    for name in (cert, secret):
        text = subprocess.run(["git", "show", f"{STEP36_COMMIT}:examples/effects/tls/{name}"], cwd=ROOT,
                              capture_output=True, text=True, check=True).stdout
        path = tree / name
        path.write_text(stamp() + text)
        out.append(path)
    return out[0], out[1]


def start_echo(runtime: str, key: str = "ed25519", idle_ms: int = 600_000, seconds: float = 900,
               plain: bool = False, pairs: str = "chain") -> Server:
    """An echo listening on a free port. `runtime` is "run" or "binary"; `plain` is the baseline
    with no handshake.

    The TLS echo reads `tls/cert.pem` and `tls/key.pem` relative to its working directory, and
    runs from `examples/effects` as the corpus test runs it, so a run on the P-256 pair copies
    that pair over those names under `tls/` in a working tree of its own.
    """
    WORK.mkdir(exist_ok=True)
    port = free_port()
    cwd = ECHO.parent
    source = PLAIN if plain else ECHO
    if not plain and pairs == "step36":
        cwd = WORK / f"tree-step36-{key}"
        (cwd / "tls").mkdir(parents=True, exist_ok=True)
        cert, secret = step36_pair(key)
        (cwd / "tls/cert.pem").write_text(cert.read_text())
        (cwd / "tls/key.pem").write_text(secret.read_text())
    elif not plain and key != "ed25519":
        cwd = WORK / f"tree-{key}"
        (cwd / "tls").mkdir(parents=True, exist_ok=True)
        cert, secret, _ = KEYS[key]
        # Stamped like every file under work/: PEM readers skip what comes before a BEGIN line.
        (cwd / "tls/cert.pem").write_text(stamp() + (CERTS / cert).read_text())
        (cwd / "tls/key.pem").write_text(stamp() + (CERTS / secret).read_text())
    argv = (
        [mo_exe(), "run", str(source), "--", str(port), str(idle_ms)]
        if runtime == "run"
        else [build(source), str(port), str(idle_ms)]
    )
    log = WORK / f"echo-{'plain' if plain else 'tls'}-{runtime}-{key}-{port}.log"
    sink = log.open("w")
    sink.write(stamp())
    sink.flush()
    proc = subprocess.Popen(guarded(argv, seconds), cwd=cwd, stdout=sink, stderr=subprocess.STDOUT)
    wait_for_port(port, proc)
    return Server(proc, port, log)


def wait_for_port(port: int, proc: subprocess.Popen, seconds: float = 20) -> None:
    deadline = time.time() + seconds
    while time.time() < deadline:
        if proc.poll() is not None:
            raise SystemExit(f"the echo exited before it listened (code {proc.returncode})")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise SystemExit(f"nothing listened on {port} within {seconds} s")


def s_client_argv(port: int, suite: str | None = None, key: str = "ed25519", extra: list[str] = (),
                  trust: str | None = None) -> list[str]:
    _, _, root = KEYS[key]
    argv = [
        OPENSSL, "s_client",
        "-connect", f"127.0.0.1:{port}",
        "-CAfile", trust or str(CERTS / root),
        "-verify_return_error",
        "-servername", "localhost",
        "-quiet", "-no_ign_eof",
    ]
    if suite:
        argv += ["-ciphersuites", suite]
    return argv + list(extra)


def echo_once(port: int, suite: str | None, key: str, text: bytes, seconds: float = 15,
              extra: list[str] = (), trust: str | None = None) -> bytes | None:
    """One handshake, one line written and read back. None when anything went wrong."""
    p = subprocess.Popen(
        guarded(s_client_argv(port, suite, key, extra, trust), seconds),
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    try:
        p.stdin.write(text)
        p.stdin.flush()
        back = p.stdout.readline()
        return back if back else None
    except OSError:
        return None
    finally:
        p.kill()
        p.wait(timeout=5)


def rss_of(pid: int) -> int:
    """A process's resident memory in bytes, its children's included (the guard's child is the one
    that matters, and `mo run` is one process)."""
    total = 0
    for target in [pid] + children_of(pid):
        try:
            with open(f"/proc/{target}/statm") as f:
                total += int(f.read().split()[1]) * os.sysconf("SC_PAGESIZE")
        except OSError:
            pass
    return total


def children_of(pid: int) -> list[int]:
    out = subprocess.run(["ps", "-o", "pid=", "--ppid", str(pid)], capture_output=True, text=True).stdout
    kids = [int(line) for line in out.split()]
    return kids + [g for k in kids for g in children_of(k)]


def best_of(runs: int, f) -> float:
    """The best of `runs` measurements: the least noisy number a machine gives."""
    return max(f() for _ in range(runs))


def table(rows: list[tuple], header: tuple) -> str:
    widths = [max(len(str(r[i])) for r in [header] + rows) for i in range(len(header))]
    line = lambda r: "| " + " | ".join(str(c).ljust(w) for c, w in zip(r, widths)) + " |"
    return "\n".join([line(header), "|" + "|".join("-" * (w + 2) for w in widths) + "|"] + [line(r) for r in rows])
