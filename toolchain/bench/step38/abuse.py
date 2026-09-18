"""abuse.py [--runtimes run,binary]: step 38's handshake abuse rows, both runtimes.

At each state of the server's handshake and of the client's, the peer sends a fatal alert, a
close_notify, a reset, or nothing until the deadline, and the Mo side's answer is checked against
the cell's expected one; after each cell a good peer checks the Mo side is alive (the server takes
the next connection and echoes a line; the client handshakes with the next server and reads its
line). 20 server cells and 12 client cells a runtime, printed as a table with the date and
`uptime` at its head (`work/abuse.txt`).

The Mo side is `abuse-server.mo` (accept, the handshake within a second, then an echo until a read
gives no line) and `abuse-client.mo` (connect, the handshake within a second, then one read within
a second), run from `examples/effects` so `tls/` holds the chain. The peer is Python's `ssl` as an
engine over memory (`MemoryBIO`), so each state is a point between two records this script holds:

  server  hello        before the ClientHello
          partial      after the first part of a ClientHello split over two records
          flight       after the server's flight, the client's Finished held back
          finished     after the client's Finished (the handshake is done)
          record       after the first application record, echoed
  client  hello        before the ServerHello, the ClientHello read
          mid-flight   after the ServerHello and the first encrypted record of the flight
          finished     after the client's Finished (the handshake is done)

The peer's four acts: `alert`, a fatal alert: in the clear during the handshake (at `flight`, the
one OpenSSL 3.6's client writes itself when it refuses the server's chain, `unknown_ca`, which it
sends in the clear; mid-flight, `handshake_failure`, since OpenSSL has written its whole flight and
moved to its application keys), and encrypted once the handshake is done, by the peer's own
OpenSSL on meeting a record it cannot open (`bad_record_mac`); `close_notify` (in the clear before the handshake is done, and encrypted by
OpenSSL's own shutdown after); `reset` (SO_LINGER 0, then close); `nothing` (the socket held open
past the Mo side's one-second deadline).

Every process runs under step 36's guard.py; every socket read here has a deadline.
"""

from __future__ import annotations

import argparse
import datetime
import os
import socket
import ssl
import struct
import subprocess
import sys
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
EFFECTS = ROOT / "examples" / "effects"
TLS = EFFECTS / "tls"
GUARD = [sys.executable, str(HERE.parent / "step36" / "guard.py")]
MO = ROOT / "toolchain" / "zig-out" / "bin" / "mo"
WORK = HERE / "work"

SERVER_STATES = ["hello", "partial", "flight", "finished", "record"]
CLIENT_STATES = ["hello", "mid-flight", "finished"]
ACTS = ["alert", "close_notify", "reset", "nothing"]

# What the Mo side must say. A server cell is `accept=<outcome>`, and once handshaken the echo's
# end (`lines=<n> end=<read>`); a client cell is `connect=<outcome>`, and once handshaken
# `read=<read>`. A close_notify after the handshake is the end of the stream (`None`).
SERVER_EXPECTED = {
    ("hello", "alert"): "accept=Handshake",
    ("hello", "close_notify"): "accept=Closed",
    ("hello", "reset"): "accept=Closed",
    ("hello", "nothing"): "accept=Timeout",
    ("partial", "alert"): "accept=Handshake",
    ("partial", "close_notify"): "accept=Closed",
    ("partial", "reset"): "accept=Closed",
    ("partial", "nothing"): "accept=Timeout",
    ("flight", "alert"): "accept=Handshake",
    ("flight", "close_notify"): "accept=Closed",
    ("flight", "reset"): "accept=Closed",
    ("flight", "nothing"): "accept=Timeout",
    ("finished", "alert"): "accept=Ok lines=0 end=Closed",
    ("finished", "close_notify"): "accept=Ok lines=0 end=None",
    ("finished", "reset"): "accept=Ok lines=0 end=Closed",
    ("finished", "nothing"): "accept=Ok lines=0 end=Timeout",
    ("record", "alert"): "accept=Ok lines=1 end=Closed",
    ("record", "close_notify"): "accept=Ok lines=1 end=None",
    ("record", "reset"): "accept=Ok lines=1 end=Closed",
    ("record", "nothing"): "accept=Ok lines=1 end=Timeout",
}
CLIENT_EXPECTED = {
    ("hello", "alert"): "connect=Handshake",
    ("hello", "close_notify"): "connect=Closed",
    ("hello", "reset"): "connect=Closed",
    ("hello", "nothing"): "connect=Timeout",
    ("mid-flight", "alert"): "connect=Handshake",
    ("mid-flight", "close_notify"): "connect=Closed",
    ("mid-flight", "reset"): "connect=Closed",
    ("mid-flight", "nothing"): "connect=Timeout",
    ("finished", "alert"): "connect=Ok read=Closed",
    ("finished", "close_notify"): "connect=Ok read=None",
    ("finished", "reset"): "connect=Ok read=Closed",
    ("finished", "nothing"): "connect=Ok read=Timeout",
}
PROBE_SERVER = "accept=Ok lines=1 end=None"
PROBE_CLIENT = "connect=Ok read=Some"

# A fatal handshake_failure and a close_notify, as records in the clear.
PLAIN_ALERT = bytes([0x15, 3, 3, 0, 2, 2, 40])
PLAIN_CLOSE = bytes([0x15, 3, 3, 0, 2, 1, 0])
# The Mo side's deadline is a second; "nothing" holds the socket past it.
HOLD = 1.6


def stamp() -> str:
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    up = subprocess.run(["uptime"], capture_output=True, text=True).stdout.strip()
    return f"{now}\n{up}\n"


def guarded(cmd: list, seconds: float) -> list[str]:
    return GUARD + [str(seconds), "--"] + [str(c) for c in cmd]


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


# ---- records and the engine over memory


def records(data: bytes) -> tuple[list[bytes], bytes]:
    """Whole TLS records in `data`, and the bytes after the last whole one."""
    out = []
    while len(data) >= 5:
        n = struct.unpack(">H", data[3:5])[0]
        if len(data) < 5 + n:
            break
        out.append(data[: 5 + n])
        data = data[5 + n:]
    return out, data


class Engine:
    """Python's ssl over memory on one socket: what it wants to write stays here until sent."""

    def __init__(self, sock: socket.socket, ctx: ssl.SSLContext, server: bool):
        self.sock = sock
        self.incoming = ssl.MemoryBIO()
        self.outgoing = ssl.MemoryBIO()
        self.obj = ctx.wrap_bio(self.incoming, self.outgoing, server_side=server,
                                server_hostname=None if server else "localhost")
        self.held = b""

    def step(self) -> bool:
        """One do_handshake; True when it is done. What it writes is held."""
        try:
            self.obj.do_handshake()
            done = True
        except ssl.SSLWantReadError:
            done = False
        self.held += self.outgoing.read()
        return done

    def take(self, k: int = -1) -> bytes:
        """The first `k` whole records held (all of them with -1)."""
        whole, rest = records(self.held)
        if k < 0:
            k = len(whole)
        taken = b"".join(whole[:k])
        self.held = b"".join(whole[k:]) + rest
        return taken

    def send(self, data: bytes) -> None:
        if data:
            self.sock.sendall(data)

    def recv_into(self, deadline: float) -> bool:
        """One read off the socket into the engine; False at the end of the stream."""
        self.sock.settimeout(max(deadline - time.time(), 0.01))
        data = self.sock.recv(65536)
        if not data:
            return False
        self.incoming.write(data)
        return True

    def spoil(self) -> bytes:
        """A record the engine cannot open, fed to it: OpenSSL answers with an encrypted fatal
        alert (bad_record_mac), which is returned."""
        self.incoming.write(bytes([0x17, 3, 3, 0, 32]) + os.urandom(32))
        try:
            self.obj.read(1024)
        except ssl.SSLError:
            pass
        try:
            self.obj.do_handshake()
        except ssl.SSLError:
            pass
        self.held += self.outgoing.read()
        return self.take()


def wire(data: bytes) -> str:
    """The act's records as they went: each one's type and length, `alert` in the clear read out."""
    whole, rest = records(data)
    said = []
    for r in whole:
        if r[0] == 0x15 and len(r) == 7:
            said.append(f"alert {r[5]}/{r[6]} clear")
        else:
            said.append({0x15: "alert", 0x16: "handshake", 0x17: "encrypted", 0x14: "ccs"}.get(r[0], hex(r[0])) + f" {len(r) - 5} B")
    if rest:
        said.append(f"{len(rest)} B more")
    return ", ".join(said) or "no bytes"


def reset(sock: socket.socket) -> None:
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
    sock.close()


def finish(sock: socket.socket, act: str) -> None:
    """After the act: a reset has closed the socket; anything else is held a moment, or past the
    deadline for `nothing`, then closed."""
    if act == "reset":
        return
    time.sleep(HOLD if act == "nothing" else 0.3)
    sock.close()


def client_ctx(trust: str = "root.pem") -> ssl.SSLContext:
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_3
    ctx.load_verify_locations(str(TLS / trust))
    return ctx


def server_ctx() -> ssl.SSLContext:
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_3
    ctx.load_cert_chain(str(TLS / "cert.pem"), str(TLS / "key.pem"))
    return ctx


# ---- the server's cells: this script is the client


def client_cell(port: int, state: str, act: str) -> str:
    sock = socket.create_connection(("127.0.0.1", port), timeout=5)
    deadline = time.time() + 5
    # At `flight` the alert is a client that refuses the server's chain: it trusts another root.
    e = Engine(sock, client_ctx("root-other.pem" if (state, act) == ("flight", "alert") else "root.pem"), server=False)
    e.step()
    hello = e.take()
    if state == "hello":
        pass
    elif state == "partial":
        # The ClientHello's message split over two records: the first goes, the second never.
        body = hello[5:]
        cut = len(body) // 2
        e.send(hello[:3] + struct.pack(">H", cut) + body[:cut])
    else:
        e.send(hello)
        while True:
            try:
                if e.step():
                    break
            except ssl.SSLCertVerificationError:
                # The refusal's encrypted alert is what `flight`'s alert sends.
                e.held += e.outgoing.read()
                break
            if not e.recv_into(deadline):
                break
        if state in ("finished", "record"):
            e.send(e.take())
            if state == "record":
                e.obj.write(b"hello\n")
                e.send(e.outgoing.read())
                got = b""
                while b"\n" not in got and e.recv_into(deadline):
                    try:
                        got += e.obj.read(1024)
                    except ssl.SSLWantReadError:
                        pass
    sent = act_on(e, sock, act, state in ("finished", "record"),
                  e.take() if (state, act) == ("flight", "alert") else None)
    finish(sock, act)
    return sent


def act_on(e: Engine, sock: socket.socket, act: str, done: bool, alert: bytes | None = None) -> str:
    """The act, and what it put on the wire. `done`: the handshake is over, so an alert or a
    close_notify goes encrypted by the peer's OpenSSL; before, in the clear, unless `alert` holds
    the one the peer's OpenSSL already wrote."""
    data = b""
    if act == "alert":
        data = alert if alert is not None else (e.spoil() if done else PLAIN_ALERT)
    elif act == "close_notify":
        if done:
            try:
                e.obj.unwrap()
            except ssl.SSLError:
                pass
            data = e.outgoing.read()
        else:
            data = PLAIN_CLOSE
    elif act == "reset":
        reset(sock)
        return "RST"
    else:
        return "(held open)"
    e.send(data)
    return wire(data)


def probe_server(port: int) -> bool:
    """A good client: a handshake, a line, its echo."""
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=5) as raw:
            with client_ctx().wrap_socket(raw, server_hostname="localhost") as t:
                t.settimeout(5)
                t.sendall(b"ping\n")
                got = b""
                while b"\n" not in got:
                    chunk = t.recv(100)
                    if not chunk:
                        break
                    got += chunk
                return got == b"ping\n"
    except OSError:
        return False


def wait_for_port(port: int, proc: subprocess.Popen) -> None:
    for _ in range(400):
        if proc.poll() is not None:
            raise SystemExit(f"the server exited before it listened ({proc.returncode})")
        try:
            # A bare TCP connection counts as one of the server's connections, so none is made:
            # the port is taken once bind succeeds for nobody else.
            with socket.socket() as s:
                s.bind(("127.0.0.1", port))
            time.sleep(0.05)
        except OSError:
            return
    raise SystemExit(f"nothing listened on {port}")


def server_rows(runtime: str, binary: Path) -> list[tuple]:
    cells = [(s, a) for s in SERVER_STATES for a in ACTS]
    port = free_port()
    count = 2 * len(cells)
    argv = [MO, "run", HERE / "abuse-server.mo", "--", port, count] if runtime == "run" else [binary, port, count]
    out = WORK / f"abuse-server-{runtime}.txt"
    with out.open("w") as sink:
        proc = subprocess.Popen(guarded(argv, 600), cwd=EFFECTS, stdout=sink, stderr=subprocess.STDOUT)
    wait_for_port(port, proc)
    alive, sent = [], []
    for state, act in cells:
        try:
            sent.append(client_cell(port, state, act))
        except OSError as e:
            # A server that is gone refuses the connection: the cell fails, and the table says why.
            sent.append(f"({type(e).__name__})")
        alive.append(probe_server(port) and proc.poll() is None)
    try:
        proc.wait(timeout=60)
    except subprocess.TimeoutExpired:
        proc.terminate()
        proc.wait(timeout=10)
    said = out.read_text().splitlines()
    rows = []
    for i, (state, act) in enumerate(cells):
        got = said[2 * i] if 2 * i < len(said) else "(nothing)"
        probe = said[2 * i + 1] if 2 * i + 1 < len(said) else "(nothing)"
        want = SERVER_EXPECTED[(state, act)]
        live = alive[i] and probe == PROBE_SERVER
        rows.append((runtime, "server", state, act, sent[i], want, got, "yes" if live else "NO",
                     "pass" if got == want and live else "FAIL"))
    if proc.returncode != 0:
        rows.append((runtime, "server", "exit", "", "", "0", str(proc.returncode), "", "FAIL"))
    return rows


# ---- the client's cells: this script is the server


def server_cell(conn: socket.socket, state: str, act: str) -> str:
    deadline = time.time() + 5
    e = Engine(conn, server_ctx(), server=True)
    # The ClientHello, whole: the engine has its flight to write once it has read it.
    while not e.held:
        if not e.recv_into(deadline):
            return "(no hello)"
        try:
            e.step()
        except ssl.SSLError:
            return "(hello refused)"
    if state == "mid-flight":
        # The ServerHello (and the compatibility ChangeCipherSpec, if OpenSSL sent one) and the
        # first encrypted record; the rest of the flight never goes.
        whole, _ = records(e.held)
        k = 0
        while k < len(whole) and whole[k][0] != 0x17:
            k += 1
        e.send(e.take(k + 1))
    elif state == "finished":
        e.send(e.take())
        while True:
            try:
                if e.step():
                    break
            except ssl.SSLError:
                return "(handshake refused)"
            if not e.recv_into(deadline):
                return "(no Finished)"
        e.send(e.take())
    # The rest of a flight held back never goes. Mid-flight the alert is in the clear: OpenSSL has
    # written its whole flight at once and moved to its application keys, so it cannot write one
    # under the handshake keys the client reads with there.
    e.held = b""
    sent = act_on(e, conn, act, state == "finished")
    finish(conn, act)
    return sent


def probe_client(conn: socket.socket) -> None:
    """A good server: a handshake, then one line to the client."""
    try:
        with server_ctx().wrap_socket(conn, server_side=True) as t:
            t.settimeout(5)
            t.sendall(b"ping\n")
            time.sleep(0.2)
    except OSError:
        pass


def client_rows(runtime: str, binary: Path) -> list[tuple]:
    cells = [(s, a) for s in CLIENT_STATES for a in ACTS]
    listener = socket.socket()
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(8)
    listener.settimeout(15)
    port = listener.getsockname()[1]
    count = 2 * len(cells)
    argv = [MO, "run", HERE / "abuse-client.mo", "--", port, count] if runtime == "run" else [binary, port, count]
    out = WORK / f"abuse-client-{runtime}.txt"
    with out.open("w") as sink:
        proc = subprocess.Popen(guarded(argv, 600), cwd=EFFECTS, stdout=sink, stderr=subprocess.STDOUT)
    sent = []
    for state, act in cells:
        # A client that is gone connects no more: the cells left fail, and the table says why.
        try:
            conn, _ = listener.accept()
        except OSError as e:
            sent.append(f"({type(e).__name__}: the client is gone)")
            break
        sent.append(server_cell(conn, state, act))
        try:
            conn, _ = listener.accept()
        except OSError:
            break
        probe_client(conn)
    sent += ["(not run)"] * (len(cells) - len(sent))
    listener.close()
    try:
        proc.wait(timeout=60)
    except subprocess.TimeoutExpired:
        proc.terminate()
        proc.wait(timeout=10)
    said = out.read_text().splitlines()
    alive = proc.returncode == 0 and said[-1:] == ["alive"]
    rows = []
    for i, (state, act) in enumerate(cells):
        got = said[2 * i] if 2 * i < len(said) else "(nothing)"
        probe = said[2 * i + 1] if 2 * i + 1 < len(said) else "(nothing)"
        want = CLIENT_EXPECTED[(state, act)]
        live = alive and probe == PROBE_CLIENT
        rows.append((runtime, "client", state, act, sent[i], want, got, "yes" if live else "NO",
                     "pass" if got == want and live else "FAIL"))
    return rows


def table(rows: list[tuple], header: tuple) -> str:
    widths = [max(len(str(r[i])) for r in [header] + rows) for i in range(len(header))]
    line = lambda r: "| " + " | ".join(str(c).ljust(w) for c, w in zip(r, widths)) + " |"
    return "\n".join([line(header), "|" + "|".join("-" * (w + 2) for w in widths) + "|"] + [line(r) for r in rows])


def build(source: Path) -> Path:
    place = WORK / ("build" if MO == ROOT / "toolchain" / "zig-out" / "bin" / "mo" else f"build-{MO.parents[2].parent.name}")
    place.mkdir(parents=True, exist_ok=True)
    ran = subprocess.run(guarded([MO, "build", source], 900), cwd=place, capture_output=True, text=True)
    if ran.returncode != 0:
        raise SystemExit(f"mo build {source} failed:\n{ran.stdout}{ran.stderr}")
    return place / "zig-out" / "mo-build" / source.stem / source.stem


def main() -> None:
    global MO
    ap = argparse.ArgumentParser()
    ap.add_argument("--runtimes", default="run,binary")
    ap.add_argument("--mo", default=str(MO), help="another mo, for a control run against an older toolchain")
    ap.add_argument("--out", default="abuse.txt")
    args = ap.parse_args()
    MO = Path(args.mo).resolve()
    WORK.mkdir(exist_ok=True)
    head = stamp()
    print(head, flush=True)
    server_bin = build(HERE / "abuse-server.mo")
    client_bin = build(HERE / "abuse-client.mo")
    rows = []
    for runtime in args.runtimes.split(","):
        rows += server_rows(runtime, server_bin)
        rows += client_rows(runtime, client_bin)
    passed = sum(1 for r in rows if r[-1] == "pass")
    text = (head + f"abuse.py --runtimes {args.runtimes} --mo {MO} (Python {sys.version.split()[0]}, {ssl.OPENSSL_VERSION})\n\n"
            + table(rows, ("runtime", "side", "state", "peer sends", "on the wire", "expected", "the Mo side said", "alive after", ""))
            + f"\n\n{passed} of {len(rows)} cells pass\n" + stamp())
    (WORK / args.out).write_text(text)
    print(text, flush=True)
    sys.exit(0 if passed == len(rows) else 1)


if __name__ == "__main__":
    main()
