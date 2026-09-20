"""Exercise Conn.chunks over real sockets with hard deadlines in either executable runtime."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import socket
import subprocess
import sys
import time
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
EXECUTOR = ROOT / "toolchain/harness/executor"
sys.path.insert(0, str(EXECUTOR))
sys.path.insert(0, str(EXECUTOR / "workspace_http"))

from workspace_http import client  # noqa: E402
from workspace_http import protocol as wire  # noqa: E402

TOKEN = "a" * 64


def free_port() -> int:
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        return int(reservation.getsockname()[1])


def server_command(runtime: str, binary: str | None, port: int, mode: str) -> list[str]:
    guard = ["python3", "toolchain/bench/step36/guard.py", "20", "--"]
    if runtime == "run":
        target = ["toolchain/zig-out/bin/mo", "run", "toolchain/bench/step44/http_chunks_probe.mo", "--", str(port), mode]
    else:
        if not binary:
            raise ValueError("--binary is required for the binary runtime")
        target = [binary, str(port), mode]
    return guard + target


def start_server(runtime: str, binary: str | None, port: int, mode: str) -> tuple[subprocess.Popen[str], str]:
    command = server_command(runtime, binary, port, mode)
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    assert process.stdout is not None
    # guard.py captures its child, so readiness output is not streaming. The listener is normally
    # live in milliseconds; wait briefly without opening a sacrificial connection.
    time.sleep(0.2)
    if process.poll() is not None:
        raise RuntimeError(f"server exited before the probe: {process.stdout.read()}")
    return process, "$ " + " ".join(command) + "\n"

def connect_socket(port: int) -> socket.socket:
    deadline = time.monotonic() + 4
    while True:
        try:
            return socket.create_connection(("127.0.0.1", port), timeout=3)
        except ConnectionRefusedError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.05)


def connect_exact(bridge: SimpleNamespace, body: dict[str, object]) -> socket.socket:
    deadline = time.monotonic() + 4
    while True:
        try:
            return client.connect(bridge, body, timeout=3)
        except ConnectionRefusedError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.05)


def raw_response(conn: socket.socket) -> tuple[int, dict[str, int], bytes]:
    conn.settimeout(3)
    raw = bytearray()
    while True:
        part = conn.recv(4096)
        if not part:
            break
        raw.extend(part)
    head, body = bytes(raw).split(b"\r\n\r\n", 1)
    status = int(head.split(b" ", 2)[1])
    return status, json.loads(body or b"{}"), bytes(raw)


def exact_client(port: int) -> None:
    bridge = SimpleNamespace(port=port, token=TOKEN, run_id="run-1", workspace_id="0123456789abcdef0123456789abcdef")
    body = client.request(bridge, call_id="call-1")
    encoded = wire.encode(body)
    conn = connect_exact(bridge, body)
    status, response = client.response(conn, timeout=3)
    if status != 200 or response != {}:
        raise AssertionError((status, response))
    print("client implementation=workspace_http.client.connect")
    print(f"client body_bytes={len(encoded)}")
    print(f"client request_ends_in_newline={str(encoded.endswith(b'\\n')).lower()}")
    print("client shutdown_called=false")
    print("client response_before_close=true status=200")


def oversized_header(port: int) -> None:
    sent = b"POST /tool HTTP/1.1\r\nX-Unfinished: " + b"x" * 2048
    with connect_socket(port) as conn:
        conn.sendall(sent)
        status, _, raw = raw_response(conn)
    if status != 431:
        raise AssertionError((status, raw[:120]))
    print(f"client unfinished_header_bytes={len(sent)}")
    print("client shutdown_called=false")
    print("client response_before_close=true status=431")


def half_close_bytes(port: int) -> None:
    parts = [b"A\x00\xe2", b"\x82", b"\xac\xf0(\x8c(", b"B"]
    payload = b"".join(parts)
    with connect_socket(port) as conn:
        for part in parts:
            conn.sendall(part)
            time.sleep(0.01)
        conn.shutdown(socket.SHUT_WR)
        status, body, _ = raw_response(conn)
    expected = {"bytes": len(payload), "sum": sum(payload)}
    if status != 200 or body.get("bytes") != expected["bytes"] or body.get("sum") != expected["sum"] or body.get("chunks", 0) < 1:
        raise AssertionError((status, body, expected))
    print(f"client payload_bytes={len(payload)} byte_sum={sum(payload)} sends={len(parts)}")
    print("client contains_nul=true contains_invalid_utf8=true split_multibyte=true")
    print("client shutdown_write=true")
    print(f"client post_eof_response=true status=200 chunks={body['chunks']}")


def run_case(runtime: str, binary: str | None, case: str) -> int:
    port = free_port()
    mode = "eof" if case == "half-close" else "http"
    server, transcript = start_server(runtime, binary, port, mode)
    failure: BaseException | None = None
    try:
        if case == "exact":
            exact_client(port)
        elif case == "oversize":
            oversized_header(port)
        else:
            half_close_bytes(port)
    except BaseException as exc:  # preserve server evidence before returning failure
        failure = exc
    assert server.stdout is not None
    try:
        remainder = server.stdout.read()
        exit_code = server.wait(timeout=8)
    except subprocess.TimeoutExpired:
        server.terminate()
        try:
            exit_code = server.wait(timeout=2)
        except subprocess.TimeoutExpired:
            server.kill()
            exit_code = server.wait(timeout=2)
        remainder = server.stdout.read()
        failure = failure or RuntimeError("server did not exit")
    print(transcript + remainder, end="")
    print(f"server_guard_exit={exit_code}")
    print(f"runtime={runtime} case={case}")
    if failure is not None:
        print(f"probe_error={failure!r}")
        return 1
    return 0 if exit_code == 0 else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", choices=("run", "binary"), required=True)
    parser.add_argument("--binary")
    parser.add_argument("--case", choices=("exact", "oversize", "half-close"), required=True)
    args = parser.parse_args()
    return run_case(args.runtime, args.binary, args.case)


if __name__ == "__main__":
    raise SystemExit(main())
