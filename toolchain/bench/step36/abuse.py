"""abuse.py: seven clients that are not a TLS 1.3 client, each answered with the alert or the
timeout the brief names, and the server still serving after every one.

The seven, and what each must get back (RFC 8446 6.2, and the brief):

  http        a plain HTTP request where a hello belongs      alert 10, unexpected_message
  tls1_2      a client offering no TLS 1.3 (`-tls1_2`)        alert 70, protocol_version
  p256only    a client with no X25519 (`-groups P-256`)       alert 40, handshake_failure
  truncated   a hello cut off mid-record                      nothing: the deadline, and the socket closes
  silent      a client that sends nothing and never finishes  nothing: the deadline, and the socket closes
  oversized   a header declaring 65,535 bytes, and 64 bytes   alert 22, record_overflow
              of body: refused on the header
  64kib       a whole record of 65,535 bytes, header and      alert 22, record_overflow
              body, sent in one write

A seventh case, `retry`, is not abuse but the one handshake that takes two rounds: a client that
supports X25519 and shared a key for P-256 instead (`-groups P-256:X25519`) must take a
HelloRetryRequest and then finish. It is here because it is the same shape of run and the same
"still serving after" check.

Immediately after each one, before the next case starts, a good client echoes a line, so "the
server still serving" is a whole handshake and a round trip after that case, not just a socket
that accepted, and not a check after the whole batch. (Step 36's script built every case before it
checked any; `cases` is a generator since step 37, so the check runs between them.)
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
            try:
                s.sendall(payload)
            except OSError:
                # The server refused before the whole payload left: its answer may still be here.
                pass
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


def cases(port: int, wait: float):  # noqa: C901
    """Each case as it is run: the caller checks the server between one and the next."""

    # 1. A plain HTTP request where a hello belongs.
    what, desc, _ = raw_case(port, b"GET / HTTP/1.1\r\nhost: localhost\r\n\r\n", wait)
    yield ("http", "alert 10 unexpected_message", said(what, desc), desc == 10)

    # 2. A client that offers no TLS 1.3.
    text = s_client_case(port, ["-tls1_2"])
    got = alert_in(text)
    yield ("tls1_2", "alert 70 protocol_version", said("alert", got), got == 70)

    # 3. A client with no X25519 at all.
    text = s_client_case(port, ["-groups", "P-256"])
    got = alert_in(text)
    yield ("p256only", "alert 40 handshake_failure", said("alert", got), got == 40)

    # 4. A hello cut off mid-record: the header says 512 bytes and 8 follow.
    what, desc, held = raw_case(port, bytes([22, 3, 1, 2, 0]) + b"\x01\x00\x01\xfc\x03\x03\xaa\xbb", wait)
    # tls-echo.mo gives the handshake 10 s, so the connection must be held about that long and
    # then closed with nothing said: the accept timed out, it did not refuse at once.
    yield ("truncated", "held to the deadline, then closed", f"{what} after {held:.1f} s", what == "closed" and held > 8)

    # 5. A client that connects and never says anything.
    what, desc, held = raw_case(port, b"", wait)
    yield ("silent", "held to the deadline, then closed", f"{what} after {held:.1f} s", what == "closed" and held > 8)

    # 6. A header declaring 65,535 bytes, past the 16 KiB plus 256 a record may be, and 64 bytes of
    # body: the server refuses on the header without reading the body.
    what, desc, _ = raw_case(port, bytes([22, 3, 1, 0xFF, 0xFF]) + b"A" * 64, wait)
    yield ("oversized", "alert 22 record_overflow", said(what, desc), desc == 22)

    # 7. A whole record of 65,535 bytes, header and body in one write: what a client that means it
    # sends. The alert may reach the client before the last of the body leaves it.
    what, desc, _ = raw_case(port, bytes([22, 3, 1, 0xFF, 0xFF]) + b"A" * 0xFFFF, wait)
    yield ("64kib", "alert 22 record_overflow", said(what, desc), desc == 22)

    # 7. Not abuse: the one handshake that takes two rounds. The client supports X25519 and shared
    # a P-256 key instead, so the server must answer a HelloRetryRequest and then finish.
    back = common.echo_once(port, None, "ed25519", b"retry\n", extra=["-groups", "P-256:X25519"])
    took = back == b"retry\n"
    yield ("retry", "a HelloRetryRequest, then a handshake", "echoed" if took else "failed", took)


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
                # This case is over and the next has not begun: the server must serve now.
                serving = common.echo_once(server.port, None, "ed25519", b"after\n") == b"after\n"
                rows.append((runtime, name, want, got, "yes" if ok else "NO", "yes" if serving else "NO"))
                bad += 0 if (ok and serving) else 1
            if not server.alive():
                raise SystemExit(f"the {runtime} echo stopped serving")
        finally:
            server.stop()
    common.write_output("abuse.txt", common.table(
        rows, ("runtime", "case", "wanted", "got", "as named", "serving right after this case")))
    if bad:
        raise SystemExit(f"{bad} case(s) were not answered as named")


if __name__ == "__main__":
    main()
