"""The spec's measurements, against `python -m jobq serve` as its own process.

uv run python -m bench.bench [throughput|lag|memory|replay|restart]...
"""

import http.client
import json
import statistics
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ProcessPoolExecutor
from datetime import datetime
from pathlib import Path

from jobq.clock import SystemClock
from jobq.jobs import Job
from jobq.queue import Queue
from jobq.store import LOG_NAME, PutRecord, Store

HOST = "127.0.0.1"
TIMEOUT_S = 60.0  # within: chosen, every bench socket and process wait
THROUGHPUT_SECONDS = 5.0


def write_log(directory: Path, jobs: int, history: str = "queued", lease_until_ms: int = 0) -> int:
    """A log of `jobs` jobs; `history` is queued (1 record), leased (1), or full (4 records)."""
    now = SystemClock().now_ms()
    with (directory / LOG_NAME).open("w") as log:
        for number in range(1, jobs + 1):
            base = Job(
                number=number,
                queue="bench",
                state="queued",
                payload="x" * 100,
                tries=0,
                max_tries=3,
                backoff_ms=0,
                created_ms=now,
                updated_ms=now,
            )
            leased = base.model_copy(
                update={
                    "state": "leased",
                    "tries": 1,
                    "worker": "w",
                    "lease_until_ms": lease_until_ms,
                }
            )
            records = {
                "queued": [base],
                "leased": [leased],
                "full": [
                    base,
                    leased,
                    base.model_copy(update={"tries": 1, "reason": "r"}),
                    base.model_copy(update={"state": "done", "tries": 2, "reason": "r"}),
                ],
            }[history]
            log.writelines(PutRecord(job=job).model_dump_json() + "\n" for job in records)
    return (directory / LOG_NAME).stat().st_size


class Served:
    """`python -m jobq serve <dir> --port 0` in its own process."""

    def __init__(self, directory: Path) -> None:
        started = time.perf_counter()
        self.process = subprocess.Popen(
            [sys.executable, "-m", "jobq", "serve", str(directory), "--port", "0"],
            stderr=subprocess.PIPE,
            text=True,
        )
        assert self.process.stderr is not None
        line = self.process.stderr.readline()
        self.ready_s = time.perf_counter() - started
        self.port = int(line.rsplit(":", 1)[1])

    def rss_mb(self) -> float:
        for line in Path(f"/proc/{self.process.pid}/status").read_text().splitlines():
            if line.startswith("VmRSS:"):
                return int(line.split()[1]) / 1024
        return 0.0

    def stop(self) -> None:
        self.process.terminate()
        self.process.wait(TIMEOUT_S)
        if self.process.stderr is not None:
            self.process.stderr.close()


class Connection:
    """One keep-alive connection for one token."""

    def __init__(self, port: int, token: str) -> None:
        self._http = http.client.HTTPConnection(HOST, port, timeout=TIMEOUT_S)
        self._token = token

    def send(
        self, method: str, path: str, body: dict[str, object] | None = None
    ) -> tuple[int, dict[str, object]]:
        data = None if body is None else json.dumps(body).encode()
        self._http.request(method, path, data, {"authorization": f"Bearer {self._token}"})
        response = self._http.getresponse()
        raw = response.read()
        parsed = json.loads(raw) if raw else {}
        assert isinstance(parsed, dict)
        return response.status, parsed


def _ms(iso: object) -> float:
    assert isinstance(iso, str)
    return datetime.fromisoformat(iso).timestamp() * 1000


def _work(port: int, token: str, seconds: float) -> int:
    connection = Connection(port, token)
    pairs = 0
    end = time.perf_counter() + seconds
    while time.perf_counter() < end:
        status, job = connection.send("POST", "/queues/bench/lease", {"lease_ms": 60_000})
        if status != 200:
            break
        if connection.send("POST", f"/jobs/{job['id']}/ack")[0] == 200:
            pairs += 1
    return pairs


def throughput() -> None:
    for workers in (1, 32):
        with tempfile.TemporaryDirectory() as tmp:
            write_log(Path(tmp), 40_000)
            served = Served(Path(tmp))
            try:
                with ProcessPoolExecutor(workers) as pool:
                    futures = [
                        pool.submit(_work, served.port, f"w{n}", THROUGHPUT_SECONDS)
                        for n in range(workers)
                    ]
                    pairs = sum(f.result(timeout=THROUGHPUT_SECONDS + TIMEOUT_S) for f in futures)
            finally:
                served.stop()
        rate = pairs / THROUGHPUT_SECONDS
        print(f"throughput, {workers} workers: {rate:.0f} lease+ack pairs/s ({2 * rate:.0f} req/s)")


def lag() -> None:
    lease_ms = 300
    with tempfile.TemporaryDirectory() as tmp:
        served = Served(Path(tmp))
        try:
            producer, holder, stream = (Connection(served.port, t) for t in ("p", "a", "b"))
            lags, requests = [], 0
            for _ in range(20):
                body: dict[str, object] = {"queue": "lag", "payload": "x", "max_tries": 100}
                producer.send("POST", "/jobs", body)
                _, leased = holder.send("POST", "/queues/lag/lease", {"lease_ms": lease_ms})
                until = _ms(leased["lease_until"])
                while True:
                    requests += 1
                    status, got = stream.send("POST", "/queues/lag/lease", {"lease_ms": 60_000})
                    if status == 200:
                        lags.append(time.time() * 1000 - until)
                        break
                stream.send("POST", f"/jobs/{got['id']}/ack")
        finally:
            served.stop()
    rate = requests / (20 * lease_ms / 1000)
    print(
        f"lease lag under a steady stream (~{rate:.0f} lease requests/s): "
        f"median {statistics.median(lags):.1f} ms, max {max(lags):.1f} ms over 20 leases"
    )


def memory() -> None:
    for jobs in (0, 100_000):
        with tempfile.TemporaryDirectory() as tmp:
            size = write_log(Path(tmp), jobs)
            served = Served(Path(tmp))
            try:
                Connection(served.port, "m").send("GET", "/health")
                rss = served.rss_mb()
            finally:
                served.stop()
        print(f"resident memory, {jobs} jobs ({size / 1e6:.1f} MB log): {rss:.1f} MB")


def replay() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        size = write_log(Path(tmp), 250_000, history="full")
        started = time.perf_counter()
        store, replayed = Store.open(Path(tmp))
        Queue(store, SystemClock(), replayed)
        elapsed = time.perf_counter() - started
        store.close()
        served = Served(Path(tmp))
        served.stop()
    print(
        f"replay, 1,000,000 records ({size / 1e6:.0f} MB, 250k jobs): {elapsed:.1f} s in process, "
        f"{served.ready_s:.1f} s from process start to listening"
    )


def restart() -> None:
    now = SystemClock().now_ms()
    for label, until in (("still live", now + 3_600_000), ("run out while stopped", now - 1)):
        with tempfile.TemporaryDirectory() as tmp:
            write_log(Path(tmp), 10_000, history="leased", lease_until_ms=until)
            served = Served(Path(tmp))
            try:
                started = time.perf_counter()
                _, health = Connection(served.port, "r").send("GET", "/health")
                first = time.perf_counter() - started
            finally:
                served.stop()
        print(
            f"restart, 10,000 leased jobs, leases {label}: listening in {served.ready_s:.2f} s, "
            f"first request answered {first:.2f} s later, health {health}"
        )


MEASUREMENTS = {
    "throughput": throughput,
    "lag": lag,
    "memory": memory,
    "replay": replay,
    "restart": restart,
}

if __name__ == "__main__":
    for name in sys.argv[1:] or list(MEASUREMENTS):
        MEASUREMENTS[name]()
