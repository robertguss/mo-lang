#!/usr/bin/env python3
"""Drive the step 44 corrective real-socket controls in either executable runtime."""
from __future__ import annotations

import argparse
from pathlib import Path
import socket
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
PROGRAM = "toolchain/bench/step44/review-fixes/control_probe.mo"
GUARD = [sys.executable, "toolchain/bench/step36/guard.py", "20", "--"]
DATA_RCVBUF_REQUEST = 4_096
DATA_RCVBUF_MAX = 16_384


def target(runtime: str, binary: str | None, *args: str) -> list[str]:
    if runtime == "run":
        command = ["toolchain/zig-out/bin/mo", "run", PROGRAM, "--", *args]
    else:
        if not binary:
            raise ValueError("--binary is required for the binary runtime")
        command = [binary, *args]
    return GUARD + command


def show(command: list[str], completed: subprocess.CompletedProcess[str]) -> None:
    print("$ " + " ".join(command))
    print(completed.stdout, end="")
    print(completed.stderr, end="", file=sys.stderr)
    print(f"guard_exit={completed.returncode}")


def run_command(runtime: str, binary: str | None, *args: str) -> subprocess.CompletedProcess[str]:
    command = target(runtime, binary, *args)
    completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=25)
    show(command, completed)
    return completed


def require(completed: subprocess.CompletedProcess[str], *, zero: bool, contains: tuple[str, ...]) -> None:
    combined = completed.stdout + completed.stderr
    if "guard: killed" in combined or completed.returncode < 0 or completed.returncode >= 128:
        raise AssertionError(("guard or signal termination is never an expected result", completed.returncode, combined))
    expected = 0 if zero else 70
    if completed.returncode != expected:
        raise AssertionError((completed.returncode, expected, combined))
    missing = [text for text in contains if text not in combined]
    if missing:
        raise AssertionError((missing, combined))


def bounds(runtime: str, binary: str | None) -> None:
    for value in ("1", "65536"):
        completed = run_command(runtime, binary, "bounds", value)
        require(
            completed,
            zero=True,
            contains=(f"bound-request={value} parsed={value}", f"bound={value}", "exact_bounded=true"),
        )
    for value in ("0", "65537", "18446744073709551615"):
        completed = run_command(runtime, binary, "bounds", value)
        require(
            completed,
            zero=False,
            contains=(
                f"bound-request={value} parsed={value}",
                "Conn.chunks max_bytes must be from 1 through 65,536",
            ),
        )
    print("bounds valid=1,65536 invalid=0,65537,18446744073709551615 full_width=true")


def pending_pull(runtime: str, binary: str | None) -> None:
    completed = run_command(runtime, binary, "pending-pull")
    require(
        completed,
        zero=False,
        contains=(
            "pull-reader waiting_in=Conn.read_line confirmed=true",
            "Conn.read_line is already waiting on this connection: a connection has one reader",
        ),
    )
    print("pending_pull actual_wait=true registration_refused=true")


def late_tls(runtime: str, binary: str | None) -> None:
    completed = run_command(runtime, binary, "late-tls")
    require(
        completed,
        zero=False,
        contains=(
            "late-tls registration=complete handshake=starting",
            "takes a connection nothing has read or written",
            "Conn.chunks was called on this one",
        ),
    )
    print("late_tls actual_handshake_call=true registration_refused=true")


def free_port() -> int:
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        return int(reservation.getsockname()[1])


def connect(port: int) -> socket.socket:
    deadline = time.monotonic() + 4
    while True:
        try:
            conn = socket.create_connection(("127.0.0.1", port), timeout=3)
            conn.settimeout(5)
            return conn
        except ConnectionRefusedError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.02)

def connect_unread(port: int) -> tuple[socket.socket, int]:
    deadline = time.monotonic() + 4
    while True:
        conn = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        conn.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, DATA_RCVBUF_REQUEST)
        conn.settimeout(3)
        try:
            conn.connect(("127.0.0.1", port))
        except ConnectionRefusedError:
            conn.close()
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.02)
            continue
        pre_reapply = int(conn.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF))
        conn.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, DATA_RCVBUF_REQUEST)
        post_reapply = int(conn.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF))
        print(
            f"data_socket rcvbuf_requested={DATA_RCVBUF_REQUEST} "
            f"rcvbuf_pre_reapply={pre_reapply} "
            f"rcvbuf_post_reapply={post_reapply}",
            flush=True,
        )
        if post_reapply <= 0 or post_reapply > DATA_RCVBUF_MAX:
            conn.close()
            raise AssertionError(("data receive buffer is not small and bounded", post_reapply))
        return conn, post_reapply


def line(conn: socket.socket) -> bytes:
    data = bytearray()
    while not data.endswith(b"\n"):
        part = conn.recv(128)
        if not part:
            raise RuntimeError(f"control connection ended after {bytes(data)!r}")
        data.extend(part)
        if len(data) > 1024:
            raise RuntimeError("control line exceeded 1024 bytes")
    return bytes(data)


def stop(process: subprocess.Popen[str]) -> tuple[str, int]:
    assert process.stdout is not None
    try:
        output, _ = process.communicate(timeout=8)
        return output, process.returncode
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            output, _ = process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            output, _ = process.communicate(timeout=2)
        return output, process.returncode


def blocked_writer(runtime: str, binary: str | None) -> None:
    data_port = free_port()
    control_port = free_port()
    while control_port == data_port:
        control_port = free_port()
    command = target(runtime, binary, "blocked-writer", str(data_port), str(control_port))
    process = subprocess.Popen(
        command,
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    data: socket.socket | None = None
    control: socket.socket | None = None
    failure: BaseException | None = None
    first = second = b""
    data_rcvbuf = 0
    try:
        data, data_rcvbuf = connect_unread(data_port)
        control = connect(control_port)
        first = line(control)
        if first != b"writer-blocked\n":
            raise AssertionError(first)
        payload = b"input-progress"
        data.sendall(payload)
        second = line(control)
        if second != b"input-progress\n":
            raise AssertionError(second)
    except BaseException as exc:
        failure = exc
    finally:
        if data is not None:
            data.close()
        if control is not None:
            control.close()
    output, exit_code = stop(process)
    print("$ " + " ".join(command))
    print(output, end="")
    print(f"guard_exit={exit_code}")
    print(f"control_first={first!r} control_second={second!r}")
    if failure is not None:
        raise failure
    if exit_code != 0:
        raise AssertionError((exit_code, output))
    required = (
        "blocked-writer waiting_in=Conn.write confirmed=true",
        "blocked-writer post-input waiting_in=Conn.write confirmed=true",
        "blocked-writer signalled=true input_exact=true answered=true",
    )
    missing = [text for text in required if text not in output]
    if missing:
        raise AssertionError((missing, output))
    print(
        f"blocked_writer pre_and_post_wait=true exact_input_progress=true "
        f"data_peer_unread=true rcvbuf_effective={data_rcvbuf}"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", choices=("run", "binary"), required=True)
    parser.add_argument("--binary")
    parser.add_argument("--case", choices=("bounds", "pending-pull", "late-tls", "blocked-writer"), required=True)
    args = parser.parse_args()
    cases = {
        "bounds": bounds,
        "pending-pull": pending_pull,
        "late-tls": late_tls,
        "blocked-writer": blocked_writer,
    }
    cases[args.case](args.runtime, args.binary)
    print(f"runtime={args.runtime} case={args.case} result=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
