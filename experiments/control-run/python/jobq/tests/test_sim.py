"""`--sim 100 --faults`: the queue under 100 seeds of injected file and socket failures.

After every request: the store holds exactly what the queue holds, a 503 changed nothing
but run-out leases, no job was held by two workers, tries stayed within bounds, and a
done or dead job never changed. Once the faults stop and the workers keep working, every
job ends done or dead.
"""

import errno
import json
import os
import random
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from jobq.api import Request, Response
from jobq.clock import FakeClock
from jobq.jobs import Job, JobOut
from jobq.queue import Queue
from jobq.server import open_queue
from jobq.store import DeleteRecord, PutRecord, replay

SEEDS = 100
FAULT_STEPS = 80
DRAIN_ROUNDS = 400
FILE_FAULT_RATE = 0.15
SOCKET_DROP_RATE = 0.1
QUEUES = ("mail", "report")
WORKERS = ("w1", "w2", "w3")


class FaultyOps:
    """Writes and fsyncs that fail at `rate`; half of the failing writes land half their bytes."""

    def __init__(self, rng: random.Random) -> None:
        self.rng = rng
        self.rate = 0.0
        self.injected = 0

    def write(self, fd: int, data: bytes) -> int:
        if self.rng.random() < self.rate:
            self.injected += 1
            if self.rng.random() < 0.5:
                os.write(fd, data[: len(data) // 2])
            raise OSError(errno.EIO, "injected write failure")
        return os.write(fd, data)

    def fsync(self, fd: int) -> None:
        # The simulation never loses power, so a real fsync would only cost time.
        if self.rng.random() < self.rate:
            self.injected += 1
            raise OSError(errno.EIO, "injected fsync failure")


class Violation(AssertionError):
    pass


def _expired(before: Job, after: Job) -> bool:
    return (
        before.state == "leased"
        and after.state in {"queued", "dead"}
        and after.tries == before.tries
        and after.worker is None
    )


class Sim:
    def __init__(self, seed: int, directory: Path) -> None:
        self.seed = seed
        self.dir = directory
        self.rng = random.Random(seed)
        self.clock = FakeClock()
        self.ops = FaultyOps(random.Random(seed + 1_000_003))
        self.drop_rate = 0.0
        self.queue, self.api = open_queue(directory, self.clock, self.ops)
        self.beliefs: dict[str, tuple[str, int]] = {}  # job id -> (worker, lease_until_ms)
        self.finished: dict[int, Job] = {}
        self.dropped = 0
        self.unavailable = 0

    def check(self, condition: bool, text: str) -> None:
        if not condition:
            raise Violation(f"seed {self.seed}: {text}")

    # The socket: a request can be lost before it arrives, or its response after.

    def send(self, request: Request) -> Response | None:
        if self.rng.random() < self.drop_rate:
            self.dropped += 1
            return None
        before = self.queue.snapshot()
        response = self.api.handle(request)
        self.verify(request, response, before)
        if self.rng.random() < self.drop_rate:
            self.dropped += 1
            return None
        return response

    def verify(self, request: Request, response: Response, before: dict[int, Job]) -> None:
        after = self.queue.snapshot()
        self.check(response.status != 500, "no request is an internal error")
        self.check(replay(self.dir).jobs == after, "the store holds exactly what the queue holds")
        if response.status == 503:
            self.unavailable += 1
            self.check(after.keys() == before.keys(), "a 503 adds or removes no job")
            for number, job in after.items():
                old = before[number]
                self.check(job == old or _expired(old, job), "a 503 changes only run-out leases")
        removed = before.keys() - after.keys()
        if removed:
            deleted = request.method == "DELETE" and response.status == 204
            self.check(deleted and len(removed) == 1, "a job is only ever lost to its delete")
        for number, job in after.items():
            self.check(job.tries <= job.max_tries, "tries never exceed max_tries")
            if number in self.finished:
                self.check(job == self.finished[number], "a done or dead job never changes")
            elif job.state in {"done", "dead"}:
                self.finished[number] = job
        if response.status in {200, 201} and response.body.startswith(b'{"id"'):
            number = int(json.loads(response.body)["id"][2:])
            shown = JobOut.of(after[number]).to_json() if number in after else b""
            self.check(shown == response.body, "a job response shows the durable job")

    # The clients.

    def create(self) -> None:
        body = {
            "queue": self.rng.choice(QUEUES),
            "payload": f"job {self.rng.randrange(10**6)}",
            "max_tries": self.rng.randrange(1, 4),
        }
        self.send(Request("POST", "/jobs", "", "producer", json.dumps(body).encode()))

    def lease(self, worker: str, queue: str) -> None:
        lease_ms = self.rng.randrange(100, 800)
        body = json.dumps({"lease_ms": lease_ms}).encode()
        response = self.send(Request("POST", f"/queues/{queue}/lease", "", worker, body))
        if response is None or response.status != 200:
            return
        job_id = str(json.loads(response.body)["id"])
        now = self.clock.now_ms()
        held = self.beliefs.get(job_id)
        self.check(held is None or held[1] <= now, "a job is never held by two workers at once")
        self.beliefs[job_id] = (worker, now + lease_ms)

    def finish(self, worker: str, ack_rate: float, walk_away_rate: float) -> None:
        """Ack or fail every job this worker believes it holds; a sent ack ends the belief."""
        for job_id in [j for j, (w, _) in self.beliefs.items() if w == worker]:
            if self.rng.random() < walk_away_rate:
                continue
            del self.beliefs[job_id]
            if self.rng.random() < ack_rate:
                self.send(Request("POST", f"/jobs/{job_id}/ack", "", worker))
            else:
                self.send(Request("POST", f"/jobs/{job_id}/fail", "", worker, b'{"reason": "sim"}'))

    def some_id(self) -> str:
        numbers = list(self.queue.snapshot()) or [1]
        return f"j_{self.rng.choice(numbers) + self.rng.choice([0, 0, 0, 1])}"

    def restart(self) -> None:
        before = self.queue.snapshot()
        self.queue.store.close()
        self.queue, self.api = open_queue(self.dir, self.clock, self.ops)
        self.check(self.queue.snapshot() == before, "no job is lost across a restart")

    def step(self) -> None:
        roll = self.rng.random()
        worker = self.rng.choice(WORKERS)
        if roll < 0.25:
            self.create()
        elif roll < 0.5:
            self.lease(worker, self.rng.choice(QUEUES))
        elif roll < 0.7:
            self.finish(worker, ack_rate=0.7, walk_away_rate=0.2)
        elif roll < 0.78:
            self.send(Request("GET", f"/jobs/{self.some_id()}", "", worker))
        elif roll < 0.84:
            self.send(Request("DELETE", f"/jobs/{self.some_id()}", "", worker))
        elif roll < 0.9:
            query = self.rng.choice(["", "state=leased", "queue=mail&state=queued"])
            self.send(Request("GET", "/jobs", query, worker))
        elif roll < 0.95:
            self.send(Request("GET", "/health"))
        elif roll < 0.98:
            self.clock.advance(self.rng.randrange(0, 1500))
        else:
            self.restart()
        self.clock.advance(self.rng.randrange(0, 60))

    def drain(self) -> None:
        self.ops.rate = 0.0
        self.drop_rate = 0.0
        for _ in range(DRAIN_ROUNDS):
            if all(job.state in {"done", "dead"} for job in self.queue.snapshot().values()):
                return
            for worker in WORKERS:
                for queue in QUEUES:
                    self.lease(worker, queue)
                self.finish(worker, ack_rate=0.8, walk_away_rate=0.1)
            self.clock.advance(self.rng.randrange(50, 400))
        self.check(False, "every job is done or dead once the faults stop")

    def run(self) -> None:
        self.ops.rate = FILE_FAULT_RATE
        self.drop_rate = SOCKET_DROP_RATE
        for _ in range(FAULT_STEPS):
            self.step()
        self.drain()
        self.check(replay(self.dir).jobs == self.queue.snapshot(), "the store matches at the end")


def run_seed(seed: int) -> Sim:
    with tempfile.TemporaryDirectory() as tmp:
        sim = Sim(seed, Path(tmp))
        try:
            sim.run()
        finally:
            sim.queue.store.close()
    return sim


class SimulationTest(unittest.TestCase):
    def test_100_seeds_of_file_and_socket_faults(self) -> None:
        sims = [run_seed(seed) for seed in range(SEEDS)]
        self.assertGreater(sum(sim.ops.injected for sim in sims), SEEDS)
        self.assertGreater(sum(sim.unavailable for sim in sims), SEEDS)
        self.assertGreater(sum(sim.dropped for sim in sims), SEEDS)
        self.assertGreater(sum(len(sim.finished) for sim in sims), SEEDS)

    def test_the_simulation_catches_a_change_applied_before_it_is_durable(self) -> None:
        def applied_first(queue: Queue, before: Job | None, after: Job | None) -> None:
            queue._apply(before, after)
            if after is not None:
                queue.store.append(PutRecord(job=after))
            elif before is not None:
                queue.store.append(DeleteRecord(number=before.number))

        with mock.patch.object(Queue, "_commit", applied_first), self.assertRaises(Violation):
            for seed in range(SEEDS):
                run_seed(seed)


if __name__ == "__main__":
    unittest.main()
