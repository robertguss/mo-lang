"""`jobq bench <dir>`: the speed budget's measurement, the same columns as the round's
`measure.py`: creates a second, lease-and-ack pairs a second at 1 and at `--workers`
workers, restart seconds to `/health`, and resident memory after the pairs.

The service runs as its own process (`python -m jobq serve <dir> --port 0`), so the numbers
are the served program's and not the bench's. `--serve-src <path>` serves the jobq package
under another `src` folder instead (the change-3 program from the history, for the budget);
the bench itself is always this one, so both programs meet the same client.
"""

import http.client
import json
import os
import signal
import subprocess
import sys
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import TextIO

HOST = "127.0.0.1"
PRODUCERS = 8  # measure.py's producers: 8 keep-alive connections
QUEUES = 4  # measure.py's queues: q0 to q3, round-robin
PAYLOAD = "x" * 100
SINGLE_WORKER_S = 5.0  # within: the one-worker run stops after this long (chosen)
MANY_WORKERS_S = 10.0  # within: the many-worker run stops after this long (measure.py's 10 s)
START_TIMEOUT_S = 300.0  # within: chosen, a start or a restart that takes longer fails the bench
REQUEST_TIMEOUT_S = 30.0  # within: every bench socket (measure.py's 30 s)
STOP_TIMEOUT_S = 30.0  # within: chosen


class BenchError(Exception):
    """The service did not start, did not answer, or answered a request wrongly."""


@dataclass(frozen=True)
class BenchOptions:
    jobs: int = 30_000
    workers: int = 32
    serve_src: Path | None = None


class Client:
    """One keep-alive connection for one token."""

    def __init__(self, port: int, token: str) -> None:
        self._http = http.client.HTTPConnection(HOST, port, timeout=REQUEST_TIMEOUT_S)
        self._token = token

    def send(
        self, method: str, path: str, body: dict[str, object] | None = None
    ) -> tuple[int, dict[str, object]]:
        data = None if body is None else json.dumps(body).encode()
        headers = {"authorization": f"Bearer {self._token}"}
        if data is not None:
            headers["content-type"] = "application/json"
        self._http.request(method, path, data, headers)
        response = self._http.getresponse()
        raw = response.read()
        parsed = json.loads(raw) if raw else {}
        if not isinstance(parsed, dict):
            raise BenchError(f"{method} {path}: the body is not an object")
        return response.status, parsed

    def close(self) -> None:
        self._http.close()


class Served:
    """The service in its own process group; `port` once it said where it listens."""

    def __init__(self, directory: Path, serve_src: Path | None) -> None:
        env = dict(os.environ)
        if serve_src is not None:
            env["PYTHONPATH"] = str(serve_src)
        started = time.perf_counter()
        self.process = subprocess.Popen(
            [sys.executable, "-m", "jobq", "serve", str(directory), "--port", "0"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            start_new_session=True,
        )
        assert self.process.stderr is not None
        line = self.process.stderr.readline()
        if ":" not in line:
            self.stop()
            raise BenchError(f"the service did not start: {line.strip()!r}")
        self.port = int(line.rsplit(":", 1)[1])
        self._drain = threading.Thread(target=self._read_rest, daemon=True)
        self._drain.start()
        wait_healthy(self.port, started)
        self.ready_s = time.perf_counter() - started

    def _read_rest(self) -> None:
        assert self.process.stderr is not None
        for _ in self.process.stderr:
            pass

    def rss_mib(self) -> float:
        status = Path(f"/proc/{self.process.pid}/status")
        for line in status.read_text().splitlines():
            if line.startswith("VmRSS:"):
                return int(line.split()[1]) / 1024
        return 0.0

    def stop(self) -> None:
        if self.process.poll() is None:
            os.killpg(self.process.pid, signal.SIGTERM)
            try:
                self.process.wait(STOP_TIMEOUT_S)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGKILL)
                self.process.wait(STOP_TIMEOUT_S)
        drain = getattr(self, "_drain", None)
        if drain is not None:
            drain.join(STOP_TIMEOUT_S)  # the pipe ends when the process does
        if self.process.stderr is not None:
            self.process.stderr.close()


def wait_healthy(port: int, started: float) -> None:
    while True:
        try:
            client = Client(port, "bench")
            status, _ = client.send("GET", "/health")
            client.close()
            if status == 200:
                return
        except OSError, http.client.HTTPException:
            pass
        if time.perf_counter() - started > START_TIMEOUT_S:
            raise BenchError("the service did not answer /health")
        time.sleep(0.02)


def _create_all(port: int, jobs: int) -> tuple[int, float]:
    """`jobs` creates from `PRODUCERS` connections, round-robin over the queues."""
    per = jobs // PRODUCERS
    failures: list[str] = []

    def produce(n: int) -> None:
        client = Client(port, f"p{n}")
        try:
            for k in range(per):
                body: dict[str, object] = {
                    "queue": f"q{k % QUEUES}",
                    "payload": PAYLOAD,
                    "max_tries": 3,
                }
                status, _ = client.send("POST", "/jobs", body)
                if status != 201:
                    failures.append(f"create answered {status}")
                    return
        except (OSError, http.client.HTTPException, BenchError) as failed:
            failures.append(f"create failed: {failed}")
        finally:
            client.close()

    started = time.perf_counter()
    _run_threads(produce, PRODUCERS)
    elapsed = time.perf_counter() - started
    if failures:
        raise BenchError(failures[0])
    return per * PRODUCERS, elapsed


def _pairs(port: int, workers: int, seconds: float) -> tuple[int, float]:
    """Lease-and-ack pairs from `workers` connections until `seconds` pass or every queue is
    empty; (pairs, seconds taken). Worker n starts on queue n mod 4, as in measure.py."""
    counts = [0] * workers
    failures: list[str] = []
    stop_at = time.perf_counter() + seconds

    def work(n: int) -> None:
        client = Client(port, f"w{n}")
        queue, empty = n % QUEUES, 0
        try:
            while time.perf_counter() < stop_at and empty < QUEUES:
                path = f"/queues/q{queue}/lease"
                status, job = client.send("POST", path, {"lease_ms": 60_000})
                if status == 204:  # this queue is empty: the next one
                    queue, empty = (queue + 1) % QUEUES, empty + 1
                    continue
                empty = 0
                if status != 200:
                    failures.append(f"lease answered {status}")
                    return
                status, _ = client.send("POST", f"/jobs/{job['id']}/ack")
                if status != 200:
                    failures.append(f"ack answered {status}")
                    return
                counts[n] += 1
        except (OSError, http.client.HTTPException, BenchError) as failed:
            failures.append(f"a pair failed: {failed}")
        finally:
            client.close()

    started = time.perf_counter()
    _run_threads(work, workers)
    elapsed = time.perf_counter() - started
    if failures:
        raise BenchError(failures[0])
    return sum(counts), elapsed


def _run_threads(target: Callable[[int], None], count: int) -> None:
    threads = [threading.Thread(target=target, args=(n,)) for n in range(count)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()


def bench(directory: Path, options: BenchOptions, out: TextIO) -> None:
    """Serve `directory`, create, lease and ack, restart, and print one line per number."""
    served = Served(directory, options.serve_src)
    try:
        created, elapsed = _create_all(served.port, options.jobs)
        print(f"creates: {created} in {elapsed:.1f}s = {created / elapsed:.0f}/s", file=out)
        for workers, seconds in ((1, SINGLE_WORKER_S), (options.workers, MANY_WORKERS_S)):
            pairs, taken = _pairs(served.port, workers, seconds)
            rate = pairs / taken if taken else 0.0
            print(f"pairs, {workers} workers: {pairs} in {taken:.1f}s = {rate:.0f}/s", file=out)
        print(f"rss after pairs: {served.rss_mib():.1f} MiB", file=out)
    finally:
        served.stop()
    size = sum(entry.stat().st_size for entry in directory.iterdir() if entry.is_file())
    again = Served(directory, options.serve_src)
    try:
        print(
            f"restart with a {size / 1e6:.0f} MB folder: {again.ready_s:.2f}s to /health; "
            f"rss {again.rss_mib():.1f} MiB",
            file=out,
        )
    finally:
        again.stop()
