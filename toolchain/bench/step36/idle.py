"""idle.py: the resident memory a thousand idle TLS connections cost, against a thousand idle
plain ones.

Each connection is handshook and then left alone: no bytes either way. The server's resident
memory is read from /proc before the first connection and after the last, and the difference
divided by the count is what one idle connection holds -- the socket, the `Conn`, its buffer if it
kept one, and the TLS engine with its ciphers and whatever its buffers still hold.

The client is Python's `ssl`, which is OpenSSL too (`ssl.OPENSSL_VERSION`) and is in the standard
library, so a thousand connections are a thousand sockets in one process rather than a thousand
`s_client` processes, whose own three megabytes each would swamp the machine and tell us nothing
about the server. The handshake on the wire is the same one `s_client` makes, and every other run
in this folder uses `s_client` itself.
"""

from __future__ import annotations

import argparse
import socket
import ssl
import time

import common


def context(key: str) -> ssl.SSLContext:
    """A client that trusts the fixture's certificate and speaks TLS 1.3 alone. Python's `ssl`
    has no way to narrow the TLS 1.3 suites, so the server picks from both it offers, which is
    the choice `handshake.py` and `bulk.py` measure apart."""
    cert, _ = common.KEYS[key]
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_3
    ctx.load_verify_locations(str(common.CERTS / cert))
    return ctx


def hold(port: int, key: str, count: int) -> tuple[list, str]:
    """`count` connections handshook and left open, with the certificate verified each time."""
    ctx = context(key)
    held = []
    suite = ""
    for _ in range(count):
        raw = socket.create_connection(("127.0.0.1", port), timeout=30)
        s = ctx.wrap_socket(raw, server_hostname="localhost")
        if s.version() != "TLSv1.3":
            raise SystemExit(f"the server spoke {s.version()}, not TLS 1.3")
        suite = s.cipher()[0]
        held.append(s)
    return held, suite


def hold_plain(port: int, count: int) -> list:
    return [socket.create_connection(("127.0.0.1", port), timeout=30) for _ in range(count)]


def settled(pid: int, want: int, seconds: float = 60) -> int:
    """The server's resident memory once it has stopped growing, or at the deadline."""
    end = time.time() + seconds
    last = -1
    steady = 0
    while time.time() < end:
        now = common.rss_of(pid)
        steady = steady + 1 if now == last else 0
        if steady >= 6:
            return now
        last = now
        time.sleep(0.25)
    return last


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--connections", type=int, default=1000)
    ap.add_argument("--runtimes", default="run,binary")
    args = ap.parse_args()

    rows = []
    for runtime in args.runtimes.split(","):
        for over in ["plain", "tls"]:
            server = common.start_echo(runtime, plain=(over == "plain"))
            held = []
            try:
                before = settled(server.proc.pid, 0, seconds=20)
                if over == "plain":
                    held = hold_plain(server.port, args.connections)
                else:
                    held, over = hold(server.port, "ed25519", args.connections)
                after = settled(server.proc.pid, args.connections, seconds=120)
                if not server.alive():
                    raise SystemExit(f"the echo stopped serving during {runtime}/{over}")
                per = (after - before) / args.connections
                rows.append((runtime, over, f"{before >> 10} KiB", f"{after >> 10} KiB", f"{per / 1024:.1f} KiB"))
            finally:
                for h in held:
                    try:
                        h.close()
                    except OSError:
                        pass
                server.stop()
    print(common.table(rows, ("runtime", "over", "before", f"after {args.connections}", "per connection")))


if __name__ == "__main__":
    main()
