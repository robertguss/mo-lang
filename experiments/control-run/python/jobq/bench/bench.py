"""The spec's measurements, for the report: not a test. Run `uv run python bench/bench.py`."""

import http.client
import json
import os
import socket
import statistics
import subprocess
import sys
import tempfile
import threading
import time
from collections.abc import Iterator
from datetime import datetime
from pathlib import Path

from jobq.clock import SystemClock
from jobq.fs import OsFs
from jobq.model import Job, JobState
from jobq.queue import Queue
from jobq.store import LOG_NAME, PutRecord, Store, encode

PAYLOAD = "x" * 64
BENCH_TIMEOUT_S = 60.0


def now_ms() -> int:
    return time.time_ns() // 1_000_000


def job(number: int, **changes: object) -> Job:
    base = Job(
        id=f"j_{number}",
        queue="bench",
        state=JobState.QUEUED,
        payload=PAYLOAD,
        attempts=0,
        max_attempts=100,
        created_at=now_ms(),
        updated_at=now_ms(),
    )
    return base.model_copy(update=changes) if changes else base


def write_log(directory: Path, records: Iterator[Job]) -> int:
    count = 0
    with (directory / LOG_NAME).open("wb") as handle:
        chunk: list[bytes] = []
        for record in records:
            chunk.append(encode(PutRecord(job=record)))
            count += 1
            if len(chunk) == 10_000:
                handle.write(b"".join(chunk))
                chunk.clear()
        handle.write(b"".join(chunk))
    return count


def queued_jobs(jobs: int) -> Iterator[Job]:
    for number in range(1, jobs + 1):
        yield job(number)


def free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port: int = probe.getsockname()[1]
        return port


class Served:
    """`jobq serve` in its own process, so the bench's client threads do not share its GIL."""

    def __init__(self, directory: Path) -> None:
        self.port = free_port()
        started = time.monotonic()
        self.process = subprocess.Popen(
            [
                sys.executable,
                "-c",
                "from jobq.cli import main; main()",
                "serve",
                str(directory),
                "--port",
                str(self.port),
            ],
            stdout=subprocess.PIPE,
            text=True,
        )
        assert self.process.stdout is not None
        self.process.stdout.readline()
        self.ready_s = time.monotonic() - started

    def rss_mib(self) -> float:
        status = Path(f"/proc/{self.process.pid}/status").read_text()
        line = next(line for line in status.splitlines() if line.startswith("VmRSS:"))
        return int(line.split()[1]) / 1024

    def stop(self) -> None:
        self.process.terminate()
        self.process.wait(timeout=BENCH_TIMEOUT_S)
        if self.process.stdout is not None:
            self.process.stdout.close()


class Connection:
    def __init__(self, port: int, token: str) -> None:
        self._connection = http.client.HTTPConnection("127.0.0.1", port, timeout=BENCH_TIMEOUT_S)
        self._headers = {"authorization": f"Bearer {token}"}

    def call(self, method: str, path: str, body: bytes | None = None) -> tuple[int, bytes]:
        self._connection.request(method, path, body=body, headers=self._headers)
        response = self._connection.getresponse()
        return response.status, response.read()

    def close(self) -> None:
        self._connection.close()


def throughput(workers: int, seconds: float) -> dict[str, object]:
    with tempfile.TemporaryDirectory() as tmp:
        write_log(Path(tmp), queued_jobs(60_000))
        served = Served(Path(tmp))
        pairs = [0] * workers
        stop_at = time.monotonic() + seconds

        def work(index: int) -> None:
            connection = Connection(served.port, f"w{index}")
            while time.monotonic() < stop_at:
                status, body = connection.call(
                    "POST", "/queues/bench/lease", b'{"lease_ms": 60000}'
                )
                if status != 200:
                    break
                status, _ = connection.call("POST", f"/jobs/{json.loads(body)['id']}/ack")
                if status != 200:
                    raise RuntimeError(f"ack answered {status}")
                pairs[index] += 1
            connection.close()

        started = time.monotonic()
        threads = [threading.Thread(target=work, args=(i,)) for i in range(workers)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=seconds + BENCH_TIMEOUT_S)
        elapsed = time.monotonic() - started
        served.stop()
    total = sum(pairs)
    return {
        "workers": workers,
        "lease_ack_pairs_per_s": round(total / elapsed),
        "requests_per_s": round(2 * total / elapsed),
    }


def lease_lag(samples: int) -> dict[str, object]:
    with tempfile.TemporaryDirectory() as tmp:
        served = Served(Path(tmp))
        holder = Connection(served.port, "holder")
        poller = Connection(served.port, "poller")
        body = json.dumps({"queue": "lag", "payload": "x", "max_attempts": 100}).encode()
        holder.call("POST", "/jobs", body)
        lags: list[float] = []
        polls = 0
        for _ in range(samples):
            status, reply = holder.call("POST", "/queues/lag/lease", b'{"lease_ms": 100}')
            assert status == 200, status
            until = datetime.fromisoformat(json.loads(reply)["lease_until"]).timestamp() * 1000
            while True:
                polls += 1
                status, reply = poller.call("POST", "/queues/lag/lease", b'{"lease_ms": 100}')
                if status == 200:
                    lags.append(time.time_ns() / 1_000_000 - until)
                    break
            poller.call("POST", f"/jobs/{json.loads(reply)['id']}/fail", b'{"reason": "lag"}')
        holder.close()
        poller.close()
        served.stop()
    return {
        "samples": samples,
        "lag_ms_median": round(statistics.median(lags), 2),
        "lag_ms_max": round(max(lags), 2),
        "lease_polls": polls,
    }


def memory(jobs: int) -> dict[str, object]:
    with tempfile.TemporaryDirectory() as tmp:
        write_log(Path(tmp), queued_jobs(jobs))
        served = Served(Path(tmp))
        connection = Connection(served.port, "w")
        status, reply = connection.call("GET", "/health")
        assert status == 200 and json.loads(reply)["queued"] == jobs
        rss = served.rss_mib()
        connection.close()
        served.stop()
    return {"jobs": jobs, "payload_bytes": len(PAYLOAD), "rss_mib": round(rss, 1)}


def replay(records: int) -> dict[str, object]:
    jobs = records // 3 + 1

    def history() -> Iterator[Job]:
        for number in range(1, jobs + 1):
            queued = job(number)
            leased = queued.model_copy(
                update={
                    "state": JobState.LEASED,
                    "attempts": 1,
                    "worker": "w1",
                    "lease_until": now_ms() + 60_000,
                }
            )
            yield queued
            yield leased
            yield leased.model_copy(
                update={"state": JobState.DONE, "worker": None, "lease_until": None}
            )

    with tempfile.TemporaryDirectory() as tmp:
        written = write_log(Path(tmp), history())
        size = os.path.getsize(Path(tmp, LOG_NAME))
        started = time.monotonic()
        store = Store(OsFs(), Path(tmp))
        queue = Queue.open(store, SystemClock())
        elapsed = time.monotonic() - started
        assert len(queue.snapshot()) == jobs
        store.close()
    return {"records": written, "log_mib": round(size / 2**20, 1), "replay_s": round(elapsed, 2)}


def restart_leased(jobs: int) -> dict[str, object]:
    past = now_ms() - 1_000

    def leased() -> Iterator[Job]:
        for number in range(1, jobs + 1):
            yield job(number, state=JobState.LEASED, attempts=1, worker="w1", lease_until=past)

    with tempfile.TemporaryDirectory() as tmp:
        write_log(Path(tmp), leased())
        served = Served(Path(tmp))
        connection = Connection(served.port, "w")
        started = time.monotonic()
        status, reply = connection.call("GET", "/health")
        first_look = time.monotonic() - started
        assert status == 200 and json.loads(reply)["queued"] == jobs, reply
        connection.close()
        served.stop()
    return {
        "leased_jobs": jobs,
        "start_to_serving_s": round(served.ready_s, 2),
        "first_look_expiring_all_s": round(first_look, 2),
    }


def main() -> None:
    results = [
        throughput(1, 5.0),
        throughput(32, 5.0),
        lease_lag(40),
        memory(0),
        memory(100_000),
        replay(1_000_000),
        restart_leased(10_000),
    ]
    for result in results:
        print(json.dumps(result), flush=True)


if __name__ == "__main__":
    main()
