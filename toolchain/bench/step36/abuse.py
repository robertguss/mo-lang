"""abuse.py: six clients that are not a TLS 1.3 client, each answered with the alert or the
timeout the brief names, and the server still serving after every one.

The six, and what each must get back (RFC 8446 6.2, and the brief):

  http        a plain HTTP request where a hello belongs      alert 10, unexpected_message
  tls1_2      a client offering no TLS 1.3 (`-tls1_2`)        alert 70, protocol_version
  p256only    a client with no X25519 (`-groups P-256`)       alert 40, handshake_failure
  truncated   a hello cut off mid-record                      nothing: the deadline, and the socket closes
  silent      a client that sends nothing and never finishes  nothing: the deadline, and the socket closes
  oversized   a record body of 64 KiB                         alert 22, record_overflow

A seventh case, `retry`, is not abuse but the one handshake that takes two rounds: a client that
supports X25519 and shared a key for P-256 instead (`-groups P-256:X25519`) must take a
HelloRetryRequest and then finish. It is here because it is the same shape of run and the same
"still serving after" check.

After each one a good client echoes a line, so "the server still serving" is a whole handshake and
a round trip, not just a socket that accepted.
"""

from __future__ import annotations

import argparse
import socket
import subprocess
import time

import common

ALERTS = {10: "unexpected_message", 22: "record_overflow", 40: "handshake_failure", 70: "protocol_version"}


def read_alert(s: socket.socket, seconds: float = 10) -> tuple[str, int | None]:
    """What came back on a raw socket: an alert and its description, the end of the stream, or
    nothing before the deadline."""
    s.settimeout(seconds)
    got = b""
    try:
        while len(got) < 7:
            more = s.recv(64)
            if not more:
                return ("closed", None) if not got else ("short", None)
            got += more
    except TimeoutError:
        return ("nothing", None)
    except OSError:
        return ("closed", None)
    if got[0] != 21:
        return (f"record type {got[0]}", None)
    return ("alert", got[6])


def raw_case(port: int, payload: bytes, wait: float) -> tuple[str, int | None, float]:
    """What came back, and how long the server held the connection before it did."""
    s = socket.create_connection(("127.0.0.1", port), timeout=10)
    t0 = time.time()
    try:
        if payload:
            s.sendall(payload)
        what, desc = read_alert(s, wait)
        return what, desc, time.time() - t0
    finally:
        s.close()


def s_client_case(port: int, extra: list[str], seconds: float = 20) -> str:
    """What `openssl s_client` said it got. Its alert number is in its error text."""
    ran = subprocess.run(
        common.guarded(common.s_client_argv(port, None, "ed25519", extra), seconds),
        input=b"", capture_output=True,
    )
    return (ran.stdout + ran.stderr).decode(errors="replace")


def alert_in(text: str) -> int | None:
    for line in text.splitlines():
        if "alert number" in line:
            return int(line.rsplit(" ", 1)[1])
    return None


def cases(port: int, wait: float) -> list[tuple[str, str, str, bool]]:  # noqa: C901
    out = []

    # 1. A plain HTTP request where a hello belongs.
    what, desc, _ = raw_case(port, b"GET / HTTP/1.1\r\nhost: localhost\r\n\r\n", wait)
    out.append(("http", "alert 10 unexpected_message", said(what, desc), desc == 10))

    # 2. A client that offers no TLS 1.3.
    text = s_client_case(port, ["-tls1_2"])
    got = alert_in(text)
    out.append(("tls1_2", "alert 70 protocol_version", said("alert", got), got == 70))

    # 3. A client with no X25519 at all.
    text = s_client_case(port, ["-groups", "P-256"])
    got = alert_in(text)
    out.append(("p256only", "alert 40 handshake_failure", said("alert", got), got == 40))

    # 4. A hello cut off mid-record: the header says 512 bytes and 8 follow.
    what, desc, held = raw_case(port, bytes([22, 3, 1, 2, 0]) + b"\x01\x00\x01\xfc\x03\x03\xaa\xbb", wait)
    # tls-echo.mo gives the handshake 10 s, so the connection must be held about that long and
    # then closed with nothing said: the accept timed out, it did not refuse at once.
    out.append(("truncated", "held to the deadline, then closed", f"{what} after {held:.1f} s", what == "closed" and held > 8))

    # 5. A client that connects and never says anything.
    what, desc, held = raw_case(port, b"", wait)
    out.append(("silent", "held to the deadline, then closed", f"{what} after {held:.1f} s", what == "closed" and held > 8))

    # 6. A record body of 64 KiB, past the 16 KiB plus 256 a record may be.
    what, desc, _ = raw_case(port, bytes([22, 3, 1, 0xFF, 0xFF]) + b"A" * 64, wait)
    out.append(("oversized", "alert 22 record_overflow", said(what, desc), desc == 22))

    # 7. Not abuse: the one handshake that takes two rounds. The client supports X25519 and shared
    # a P-256 key instead, so the server must answer a HelloRetryRequest and then finish.
    back = common.echo_once(port, None, "ed25519", b"retry\n", extra=["-groups", "P-256:X25519"])
    took = back == b"retry\n"
    out.append(("retry", "a HelloRetryRequest, then a handshake", "echoed" if took else "failed", took))
    return out


def said(what: str, desc: int | None) -> str:
    if what != "alert":
        return what
    if desc is None:
        return "no alert"
    return f"alert {desc} {ALERTS.get(desc, 'other')}"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runtimes", default="run,binary")
    ap.add_argument("--wait", type=float, default=12.0, help="how long a silent client waits for the deadline")
    args = ap.parse_args()

    rows = []
    bad = 0
    for runtime in args.runtimes.split(","):
        # The handshake deadline in tls-echo.mo is 10 s, so `--wait` must be past it.
        server = common.start_echo(runtime)
        try:
            for name, want, got, ok in cases(server.port, args.wait):
                serving = common.echo_once(server.port, None, "ed25519", b"after\n") == b"after\n"
                rows.append((runtime, name, want, got, "yes" if ok else "NO", "yes" if serving else "NO"))
                bad += 0 if (ok and serving) else 1
            if not server.alive():
                raise SystemExit(f"the {runtime} echo stopped serving")
        finally:
            server.stop()
    print(common.table(rows, ("runtime", "case", "wanted", "got", "as named", "serving after")))
    if bad:
        raise SystemExit(f"{bad} case(s) were not answered as named")


if __name__ == "__main__":
    main()
