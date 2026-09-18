"""bulk.py: bytes a second through the echo and back, over TLS against a plain `Conn`, each suite
and both runtimes, and the same comparison for round trips, which is what `echo-1k` measures.

The echo answers a line at a time, so the load is lines: `--mib` mebibytes of them, written to the
server and read back, and the rate is what went one way (the machine moved twice that). Over TLS
the client is `openssl s_client`, which does the record layer on its side; the plain column is the
same program on a plain socket through a socket of Python's, so the difference is the records.

A big echo deadlocks a client that writes everything before it reads: the server's answers fill
the kernel's buffers while the client is still writing. So the client here writes on a thread of
its own and reads on the main one, as a real client would.
"""

from __future__ import annotations

import argparse
import socket
import subprocess
import threading
import time

import common

LINE = 4096


def payload(mib: int) -> bytes:
    """Lines of `LINE` bytes: the echo reads and writes a line at a time."""
    line = bytes((i * 31 + 7) % 256 for i in range(LINE - 1)).replace(b"\n", b".") + b"\n"
    return line * ((mib << 20) // LINE)


def pump(write, read, data: bytes) -> float:
    """Writes `data` and reads it all back; seconds it took. The write runs on its own thread so
    neither side waits for the other to drain."""
    got = bytearray()
    failed: list[BaseException] = []

    def writer():
        try:
            write(data)
        except BaseException as e:  # noqa: BLE001 -- the reader reports what it saw
            failed.append(e)

    t0 = time.time()
    thread = threading.Thread(target=writer, daemon=True)
    thread.start()
    while len(got) < len(data):
        chunk = read(1 << 16)
        if not chunk:
            break
        got += chunk
    took = time.time() - t0
    thread.join(timeout=30)
    if failed:
        raise failed[0]
    if bytes(got) != data:
        raise SystemExit(f"the echo gave back {len(got)} of {len(data)} bytes, or other bytes")
    return took


def over_tls(port: int, suite: str, key: str, data: bytes, seconds: float) -> float:
    p = subprocess.Popen(
        common.guarded(common.s_client_argv(port, suite, key), seconds),
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    try:
        def write(b):
            p.stdin.write(b)
            p.stdin.flush()
        return pump(write, p.stdout.read1, data)
    finally:
        p.kill()
        p.wait(timeout=10)


def over_plain(port: int, data: bytes) -> float:
    s = socket.create_connection(("127.0.0.1", port), timeout=120)
    try:
        return pump(s.sendall, s.recv, data)
    finally:
        s.close()


def rate(mib: int, took: float) -> str:
    """Decimal megabytes a second (10^6 bytes) of the `mib` mebibytes (2^20 bytes each) that went
    one way: 100 MiB is 104.9 MB."""
    return f"{(mib << 20) / took / 1e6:.1f}"


def trips_tls(port: int, suite: str, count: int, seconds: float) -> float:
    """`count` lines written and read back one at a time; microseconds a round trip. This is what
    `echo-1k` times on `examples/programs/echo`, on this echo and through a record layer."""
    p = subprocess.Popen(
        common.guarded(common.s_client_argv(port, suite, "ed25519"), seconds),
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    try:
        p.stdin.write(b"warm\n")
        p.stdin.flush()
        if p.stdout.readline() != b"warm\n":
            raise SystemExit("the echo did not answer before the round trips")
        t0 = time.time()
        for i in range(count):
            p.stdin.write(b"trip %d\n" % i)
            p.stdin.flush()
            if p.stdout.readline() != b"trip %d\n" % i:
                raise SystemExit("a round trip came back wrong")
        return (time.time() - t0) / count * 1e6
    finally:
        p.kill()
        p.wait(timeout=10)


def trips_plain(port: int, count: int) -> float:
    s = socket.create_connection(("127.0.0.1", port), timeout=60)
    f = s.makefile("rwb", buffering=0)
    try:
        f.write(b"warm\n")
        if f.readline() != b"warm\n":
            raise SystemExit("the echo did not answer before the round trips")
        t0 = time.time()
        for i in range(count):
            f.write(b"trip %d\n" % i)
            if f.readline() != b"trip %d\n" % i:
                raise SystemExit("a round trip came back wrong")
        return (time.time() - t0) / count * 1e6
    finally:
        f.close()
        s.close()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mib", type=int, default=100)
    ap.add_argument("--best-of", type=int, default=5)
    ap.add_argument("--runtimes", default="run,binary")
    ap.add_argument("--trips", type=int, default=1000, help="round trips, as `echo-1k` counts them")
    args = ap.parse_args()

    data = payload(args.mib)
    trips = []
    rows = []
    for runtime in args.runtimes.split(","):
        # The plain baseline is the same echo with no handshake (plain-echo.mo).
        plain = common.start_echo(runtime, plain=True)
        try:
            best = min(over_plain(plain.port, data) for _ in range(args.best_of))
            rows.append((runtime, "plain", rate(args.mib, best)))
            best = min(trips_plain(plain.port, args.trips) for _ in range(args.best_of))
            trips.append((runtime, "plain", f"{best:.0f}"))
        finally:
            plain.stop()
        server = common.start_echo(runtime)
        try:
            for name, suite in common.SUITES.items():
                best = min(
                    over_tls(server.port, suite, "ed25519", data, 600)
                    for _ in range(args.best_of)
                )
                rows.append((runtime, name, rate(args.mib, best)))
                best = min(trips_tls(server.port, suite, args.trips, 600) for _ in range(args.best_of))
                trips.append((runtime, name, f"{best:.0f}"))
            if not server.alive():
                raise SystemExit("the echo stopped serving during the run")
        finally:
            server.stop()
    common.write_output("bulk.txt", common.table(
        rows, ("runtime", "over", f"MB/s: 10^6 bytes a second, {args.mib} MiB (2^20 bytes each) each way"))
        + "\n\n" + common.table(trips, ("runtime", "over", f"µs a round trip ({args.trips} of them)")))


if __name__ == "__main__":
    main()
