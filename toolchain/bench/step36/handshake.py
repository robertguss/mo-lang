"""handshake.py: handshakes a second against the TLS echo, each suite and each key pair, under
`mo run` and as a binary.

`openssl s_time -new` is the client: it opens connections back to back in one process, so what is
measured is the server's handshake and not a process start, which is what a loop of `s_client`
would measure instead (about 38 a second on this machine, all of it `fork` and `exec`). Every
connection is a fresh session: the brick has no session tickets and no resumption, so every one is
a full handshake.

Alongside each measurement one `s_client` writes a line and reads it back, so a run that handshook
fast but echoed nothing is caught; the count of those that did not come back is the failed column,
and the server must still be serving at the end of every measurement.
"""

from __future__ import annotations

import argparse
import re
import subprocess

import common

CONNECTIONS = re.compile(r"(\d+) connections in ([0-9.]+) real seconds")


def s_time(port: int, suite: str, key: str, seconds: float) -> float:
    cert, _ = common.KEYS[key]
    argv = [
        common.OPENSSL, "s_time",
        "-connect", f"127.0.0.1:{port}",
        "-CAfile", str(common.CERTS / cert),
        "-verify", "3",
        "-new", "-time", str(int(seconds)),
        "-ciphersuites", suite,
    ]
    # s_time prints its counts on stderr and its progress on stdout.
    ran = subprocess.run(common.guarded(argv, seconds * 4 + 30), capture_output=True, text=True)
    out = ran.stdout + ran.stderr
    m = CONNECTIONS.search(out)
    if not m:
        raise SystemExit(f"openssl s_time said nothing countable:\n{out[-400:]}")
    return int(m.group(1)) / float(m.group(2))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seconds", type=float, default=3.0, help="the wall each measurement fills")
    ap.add_argument("--best-of", type=int, default=5)
    ap.add_argument("--runtimes", default="run,binary")
    args = ap.parse_args()

    rows = []
    for runtime in args.runtimes.split(","):
        for key in common.KEYS:
            server = common.start_echo(runtime, key)
            try:
                for name, suite in common.SUITES.items():
                    best = 0.0
                    failed = 0
                    for _ in range(args.best_of):
                        best = max(best, s_time(server.port, suite, key, args.seconds))
                        if common.echo_once(server.port, suite, key, b"handshake\n") != b"handshake\n":
                            failed += 1
                    rows.append((runtime, key, name, f"{best:.0f}", failed))
                    if not server.alive():
                        raise SystemExit(f"the echo stopped serving during {runtime}/{key}/{name}")
            finally:
                server.stop()
    print(common.table(rows, ("runtime", "key", "suite", "handshakes/s", "echoes lost")))


if __name__ == "__main__":
    main()
