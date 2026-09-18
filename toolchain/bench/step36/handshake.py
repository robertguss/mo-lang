"""handshake.py: handshakes a second against the TLS echo, each suite and each key pair, under
`mo run` and as a binary.

`openssl s_time -new` is the client: it opens connections back to back in one process, so what is
measured is the server's handshake and not a process start, which is what a loop of `s_client`
would measure instead (about 38 a second on this machine, all of it `fork` and `exec`). Every
connection is a fresh session: the brick has no session tickets and no resumption, so every one is
a full handshake.

Alongside each measurement one `s_client` writes a line and reads it back, so a run that handshook
fast but echoed nothing is caught; the count of those that did not come back is the echoes-lost
column, and the server must still be serving at the end of every measurement. `s_time`'s own exit
code is checked (0, or the 1 OpenSSL 3.0's `s_time -new` gives on a good run, with its count
printed and no error line; anything else stops the script), and the connections it counted in the
best measurement are a column of their own: the rate is that count over `s_time`'s seconds, and
`echoes lost` is not a count of failed handshakes among them (step 37's fix, after the auditor's
reading of step 36).
"""

from __future__ import annotations

import argparse
import re
import subprocess

import common

CONNECTIONS = re.compile(r"(\d+) connections in ([0-9.]+) real seconds")


def s_time(port: int, suite: str, key: str, seconds: float, trust: str) -> tuple[float, int]:
    """Handshakes a second, and the connections `s_time` counted."""
    argv = [
        common.OPENSSL, "s_time",
        "-connect", f"127.0.0.1:{port}",
        "-CAfile", trust,
        "-verify", "3",
        "-new", "-time", str(int(seconds)),
        "-ciphersuites", suite,
    ]
    # s_time prints its counts on stderr and its progress on stdout.
    ran = subprocess.run(common.guarded(argv, seconds * 4 + 30), capture_output=True, text=True)
    out = ran.stdout + ran.stderr
    # OpenSSL 3.0's s_time exits 1 after a -new run even against OpenSSL's own s_server, having
    # counted its connections and printed no error (checked on this machine, 18 Sep 2026: 1,244
    # connections, exit 1), so its exit code alone cannot say a run failed. A run failed when it
    # exited otherwise (a signal, the guard), printed no count, or printed an error.
    errors = [line for line in out.splitlines() if "error" in line.lower() or line.strip() == "ERROR"]
    if ran.returncode not in (0, 1) or errors:
        raise SystemExit(f"openssl s_time exited {ran.returncode}:\n{out[-400:]}")
    m = CONNECTIONS.search(out)
    if not m:
        raise SystemExit(f"openssl s_time said nothing countable:\n{out[-400:]}")
    return int(m.group(1)) / float(m.group(2)), int(m.group(1))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seconds", type=float, default=3.0, help="the wall each measurement fills")
    ap.add_argument("--best-of", type=int, default=5)
    ap.add_argument("--runtimes", default="run,binary")
    ap.add_argument("--pairs", default="chain", choices=["chain", "step36"],
                    help="chain: gen.sh's chain of three (step 37); step36: step 36's self-signed pairs")
    args = ap.parse_args()

    rows = []
    for runtime in args.runtimes.split(","):
        for key in common.KEYS:
            if args.pairs == "step36":
                trust = str(common.step36_pair(key)[0])
            else:
                trust = str(common.CERTS / common.KEYS[key][2])
            server = common.start_echo(runtime, key, pairs=args.pairs)
            try:
                for name, suite in common.SUITES.items():
                    best = 0.0
                    connections = 0
                    failed = 0
                    for _ in range(args.best_of):
                        rate, count = s_time(server.port, suite, key, args.seconds, trust)
                        if rate > best:
                            best, connections = rate, count
                        if common.echo_once(server.port, suite, key, b"handshake\n", trust=trust) != b"handshake\n":
                            failed += 1
                    rows.append((runtime, key, name, f"{best:.0f}", connections, failed))
                    if not server.alive():
                        raise SystemExit(f"the echo stopped serving during {runtime}/{key}/{name}")
            finally:
                server.stop()
    common.write_output(f"handshake{'-step36' if args.pairs == 'step36' else ''}.txt", common.table(
        rows, ("runtime", "key", "suite", "handshakes/s", "connections s_time counted", "echoes lost")))


if __name__ == "__main__":
    main()
