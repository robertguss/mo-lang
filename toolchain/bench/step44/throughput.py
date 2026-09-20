"""Best-of-N fixed-volume Conn.chunks throughput and Conn.lines before/after control."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import socket
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
GUARD = ["python3", "toolchain/bench/step36/guard.py"]


def payload(mode: str, mib: int) -> bytes:
    size = mib << 20
    if mode == "chunks":
        block = bytes(range(256))
    else:
        block = bytes((i * 31 + 7) % 256 for i in range(4095)).replace(b"\n", b".") + b"\n"
    return (block * ((size + len(block) - 1) // len(block)))[:size]


def free_port() -> int:
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        return int(reservation.getsockname()[1])


def guarded(seconds: int, target: list[str]) -> list[str]:
    return GUARD + [str(seconds), "--"] + target


def built_binary(mo: str, source: Path, name: str) -> str:
    command = guarded(180, [mo, "build", str(source), "-o", name])
    result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print("$ " + " ".join(command))
    print(result.stdout, end="")
    if result.returncode != 0:
        raise RuntimeError(f"build failed with {result.returncode}")
    lines = [line for line in result.stdout.splitlines() if line]
    if not lines:
        raise RuntimeError("build did not report its binary")
    path = Path(lines[-1])
    return str(path if path.is_absolute() else ROOT / path)


def connect(port: int) -> socket.socket:
    deadline = time.monotonic() + 6
    while True:
        try:
            return socket.create_connection(("127.0.0.1", port), timeout=10)
        except ConnectionRefusedError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.02)


def one(command: list[str], port: int, data: bytes) -> tuple[float, str, int]:
    server = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert server.stdout is not None
    try:
        with connect(port) as conn:
            started = time.perf_counter()
            conn.sendall(data)
            answer = bytearray()
            while len(answer) < 3:
                part = conn.recv(3 - len(answer))
                if not part:
                    break
                answer.extend(part)
            took = time.perf_counter() - started
        output = server.stdout.read()
        code = server.wait(timeout=10)
        if answer != b"ok\n" or code != 0:
            raise RuntimeError(f"server answer={bytes(answer)!r} exit={code} output={output!r}")
        return took, output, code
    except BaseException:
        if server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=3)
        raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mo", required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--mode", choices=("chunks", "lines"), required=True)
    parser.add_argument("--runtimes", default="run,binary")
    parser.add_argument("--mib", type=int, default=16)
    parser.add_argument("--best-of", type=int, default=5)
    args = parser.parse_args()

    mo = str(Path(args.mo).resolve())
    source = HERE / ("chunks_throughput.mo" if args.mode == "chunks" else "lines_throughput.mo")
    data = payload(args.mode, args.mib)
    binary = None
    if "binary" in args.runtimes.split(","):
        binary = built_binary(mo, source, f"step44-{args.label}-{args.mode}")

    print(f"load_average_start={','.join(f'{n:.2f}' for n in os.getloadavg())}")
    print(f"label={args.label} mode={args.mode} payload_bytes={len(data)} best_of={args.best_of}")
    for runtime in args.runtimes.split(","):
        samples: list[float] = []
        for index in range(args.best_of):
            port = free_port()
            target = [mo, "run", str(source), "--", str(port), str(len(data))] if runtime == "run" else [binary, str(port), str(len(data))]
            command = guarded(90, target)
            took, output, code = one(command, port, data)
            samples.append(took)
            print(f"sample runtime={runtime} n={index + 1} seconds={took:.6f} MBps={len(data) / took / 1e6:.3f} exit={code}")
            if output:
                print(output, end="")
        best = min(samples)
        print(f"best runtime={runtime} seconds={best:.6f} MBps={len(data) / best / 1e6:.3f}")
    print(f"load_average_end={','.join(f'{n:.2f}' for n in os.getloadavg())}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
