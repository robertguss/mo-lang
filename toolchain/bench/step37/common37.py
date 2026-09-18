"""What the step 37 runs share: paths, the guard, the stamp every output file begins with, the
fixture chains, and a reader for OpenSSL's `-msg` log.

OpenSSL 3.0 at /usr/bin/openssl is the reference in every run and is never linked into `mo` or
into a binary it builds (the bricks page). Every `mo` process, every binary, every `openssl`, and
every tool built from the brick runs under step 36's `guard.py SECONDS -- cmd`, a timeout and a
4 GB resident watchdog.
"""

from __future__ import annotations

import datetime
import re
import socket
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
TOOLCHAIN = ROOT / "toolchain"
GUARD = [sys.executable, str(HERE.parent / "step36" / "guard.py")]
OPENSSL = "/usr/bin/openssl"
FIX = ROOT / "examples" / "effects" / "tls"
BIN = TOOLCHAIN / "zig-out" / "bin"
PEER = BIN / "mo-tls-peer"
FUZZ = BIN / "mo-tls-fuzz"
WORK = HERE / "work"

SUITES = {"aes128gcm": "TLS_AES_128_GCM_SHA256", "chacha20": "TLS_CHACHA20_POLY1305_SHA256"}
# The two key types, as the suffix gen.sh gives their files.
KEYS = {"ed25519": "", "p256": "-p256"}

ALERTS = {
    0: "close_notify", 10: "unexpected_message", 20: "bad_record_mac", 22: "record_overflow",
    40: "handshake_failure", 42: "bad_certificate", 43: "unsupported_certificate",
    45: "certificate_expired", 47: "illegal_parameter", 48: "unknown_ca", 50: "decode_error",
    51: "decrypt_error", 70: "protocol_version", 80: "internal_error", 109: "missing_extension",
    110: "unsupported_extension", 120: "no_application_protocol",
}


def guarded(cmd: list, seconds: float) -> list[str]:
    return GUARD + [str(seconds), "--"] + [str(c) for c in cmd]


def stamp() -> str:
    """The first two lines of every output file: the date, and `uptime` as it printed."""
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    up = subprocess.run(["uptime"], capture_output=True, text=True).stdout.strip()
    return f"{now}\n{up}\n"


def load() -> str:
    """The load average `uptime` prints, for the tables."""
    up = subprocess.run(["uptime"], capture_output=True, text=True).stdout
    return up.rsplit("load average:", 1)[-1].strip()


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def fixture(stem: str, key: str) -> Path:
    """A file gen.sh wrote, for a key type: `root`, `cert`, `refuse-host-key`, ..."""
    return FIX / f"{stem}{KEYS[key]}.pem"


def split_chain(chain: Path, into: Path) -> tuple[Path, Path | None]:
    """A chain file as `s_server` takes it: the leaf alone, and the rest (None when there is none),
    since `-cert_chain` with the whole file sends the leaf twice."""
    text = chain.read_text()
    end = "-----END CERTIFICATE-----"
    at = text.index(end) + len(end)
    into.mkdir(parents=True, exist_ok=True)
    leaf = into / f"{chain.stem}.leaf.pem"
    leaf.write_text(text[:at] + "\n")
    rest_text = text[at:].strip()
    if not rest_text:
        return leaf, None
    rest = into / f"{chain.stem}.rest.pem"
    rest.write_text(rest_text + "\n")
    return leaf, rest


MSG_LINE = re.compile(r"^(>>>|<<<) (\S+ \S+), (\w+)(?: \[length ([0-9a-f]+)\])?(?:, (.*))?$")


class Msgs:
    """What `openssl ... -msg -msgfile F` logged: each message with its direction and bytes."""

    def __init__(self, text: str):
        self.items: list[tuple[str, str, str, bytes]] = []
        current = None
        for line in text.splitlines():
            m = MSG_LINE.match(line)
            if m:
                current = [m.group(1), m.group(3), m.group(5) or "", bytearray()]
                self.items.append(current)
                continue
            if current is not None and line.startswith("    "):
                try:
                    current[3].extend(bytes.fromhex(line.strip()))
                except ValueError:
                    pass
        self.items = [(d, kind, what, bytes(b)) for d, kind, what, b in self.items]

    def alerts(self, direction: str) -> list[int]:
        return [b[1] for d, kind, _, b in self.items if d == direction and kind == "Alert" and len(b) >= 2]

    def count(self, direction: str, what: str) -> int:
        return sum(1 for d, kind, w, _ in self.items if d == direction and kind == "Handshake" and w == what)

    def alpn(self, direction: str) -> str:
        """The protocol an EncryptedExtensions going `direction` named, or ""."""
        for d, kind, w, b in self.items:
            if d != direction or w != "EncryptedExtensions" or len(b) < 6:
                continue
            at = 6
            end = 6 + int.from_bytes(b[4:6], "big")
            while at + 4 <= min(end, len(b)):
                et = int.from_bytes(b[at:at + 2], "big")
                n = int.from_bytes(b[at + 2:at + 4], "big")
                body = b[at + 4:at + 4 + n]
                if et == 16 and len(body) >= 3:
                    return body[3:3 + body[2]].decode(errors="replace")
                at += 4 + n
        return ""

    def closes(self, direction: str) -> bool:
        return 0 in self.alerts(direction)


def table(rows: list[tuple], header: tuple) -> str:
    widths = [max(len(str(r[i])) for r in [header] + rows) for i in range(len(header))]
    line = lambda r: "| " + " | ".join(str(c).ljust(w) for c, w in zip(r, widths)) + " |"
    return "\n".join([line(header), "|" + "|".join("-" * (w + 2) for w in widths) + "|"] + [line(r) for r in rows])


def ensure_tools() -> None:
    if not PEER.exists() or not FUZZ.exists():
        ran = subprocess.run(["zig", "build", "tls-tools"], cwd=TOOLCHAIN, capture_output=True, text=True)
        if ran.returncode != 0:
            raise SystemExit(f"zig build tls-tools failed:\n{ran.stderr}")

