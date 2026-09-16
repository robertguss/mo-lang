"""`--sim 100 --faults`: the queue under 100 seeds of injected file and socket failures.

After every request: the store holds exactly what the queue holds, a 503 changed nothing
but what a look moves (run-out leases and due scheduled jobs), no job was held by two
workers, tries stayed within bounds, no scheduled job moved before its run_at, a done job
never changed, a dead job changed only by its retry, and `/queues` lists exactly the queues
holding a job. Then the folder refuses every write for a while: each write is a 503, reads
still answer, nothing changes, and the first write after it goes through with no restart.
Once the faults stop and the workers keep working, every job ends done or dead.
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
from jobq.jobs import STATES, Job, JobOut
from jobq.queue import Queue
from jobq.server import open_queue
from jobq.store import DeleteRecord, PutRecord, replay

SEEDS = 100
FAULT_STEPS = 80
UNWRITABLE_STEPS = 5
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


def _moved_at_a_look(before: Job, after: Job) -> bool:
    """A run-out lease returned or a due scheduled job queued: the changes a look makes."""
    returned = (
        before.state == "leased"
        and after.state in {"queued", "scheduled", "dead"}
        and after.worker is None
    )
    due = before.state == "scheduled" and after.state == "queued"
    return after.tries == before.tries and (returned or due)


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
        self.listed = 0
        self.scheduled = 0
        self.retried = 0

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
        now = self.clock.now_ms()
        self.check(response.status != 500, "no request is an internal error")
        self.check(replay(self.dir).jobs == after, "the store holds exactly what the queue holds")
        if response.status == 503:
            self.unavailable += 1
            self.check(after.keys() == before.keys(), "a 503 adds or removes no job")
            for number, job in after.items():
                old = before[number]
                self.check(job == old or _moved_at_a_look(old, job), "a 503 changes only a look's")
        removed = before.keys() - after.keys()
        if removed:
            deleted = request.method == "DELETE" and response.status == 204
            self.check(deleted and len(removed) == 1, "a job is only ever lost to its delete")
        for number, job in after.items():
            self.check(job.tries <= job.max_tries, "tries never exceed max_tries")
            was = before.get(number)
            if was is not None and was.state == "scheduled" and job.state != "scheduled":
                due = was.run_at_ms is not None and was.run_at_ms <= now
                self.check(due, "a scheduled job never moves before its run_at")
            if job.state == "scheduled" and (was is None or was.state != "scheduled"):
                self.scheduled += 1
            if number in self.finished:
                if job != self.finished[number]:
                    self.check(
                        self._retried(request, response, self.finished[number], job),
                        "a done job never changes, and a dead one only by its retry",
                    )
                    self.retried += 1
                    del self.finished[number]
            elif job.state in {"done", "dead"}:
                self.finished[number] = job
        if request.path == "/queues" and response.status == 200:
            self.check_queues(response, after)
        if response.status in {200, 201} and response.body.startswith(b'{"id"'):
            number = int(json.loads(response.body)["id"][2:])
            shown = JobOut.of(after[number]).to_json() if number in after else b""
            self.check(shown == response.body, "a job response shows the durable job")

    def check_queues(self, response: Response, after: dict[int, Job]) -> None:
        """`/queues` shows every queue holding a job, and its counts are the jobs there."""
        held: dict[str, dict[str, int]] = {}
        for job in after.values():
            held.setdefault(job.queue, dict.fromkeys(STATES, 0))[job.state] += 1
        listed = {row["name"]: row for row in json.loads(response.body)["queues"]}
        self.check(set(listed) == set(held), "/queues lists exactly the queues holding a job")
        for name, counts in held.items():
            shown = [listed[name][state] for state in STATES]
            self.check(shown == [counts[state] for state in STATES], f"{name}'s counts are right")
        self.listed += 1

    @staticmethod
    def _retried(request: Request, response: Response, finished: Job, job: Job) -> bool:
        route = request.method == "POST" and request.path == f"/jobs/{job.id}/retry"
        reset = job.state == "queued" and job.tries == 0 and job.reason is None
        return route and response.status == 200 and finished.state == "dead" and reset

    # The clients.

    def create(self) -> None:
        body = {
            "queue": self.rng.choice(QUEUES),
            "payload": f"job {self.rng.randrange(10**6)}",
            "max_tries": self.rng.randrange(1, 4),
            "delay_ms": self.rng.choice([0, 0, 0, self.rng.randrange(1, 1000)]),
            "backoff_ms": self.rng.choice([0, 0, self.rng.randrange(1, 500)]),
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

    def retry(self, worker: str) -> None:
        """Retry a dead job most of the time, and any id otherwise."""
        dead = [job.id for job in self.queue.snapshot().values() if job.state == "dead"]
        job_id = self.rng.choice(dead) if dead and self.rng.random() < 0.8 else self.some_id()
        self.send(Request("POST", f"/jobs/{job_id}/retry", "", worker))

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
        elif roll < 0.75:
            self.send(Request("GET", f"/jobs/{self.some_id()}", "", worker))
        elif roll < 0.8:
            self.retry(worker)
        elif roll < 0.85:
            self.send(Request("DELETE", f"/jobs/{self.some_id()}", "", worker))
        elif roll < 0.9:
            queries = ["", "state=leased", "queue=mail&state=queued", "state=scheduled"]
            self.send(Request("GET", "/jobs", self.rng.choice(queries), worker))
        elif roll < 0.93:
            self.send(Request("GET", "/queues", "", "operator"))
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

    def unwritable(self) -> None:
        """The folder refuses every write for a while, as the round 8 incident had it: every
        write is a 503, the reads still answer, no job changes, and the first write after the
        folder can be written again goes through with no restart."""
        self.ops.rate = 0.0
        self.drop_rate = 0.0
        settled = self.send(Request("GET", "/health"))  # nothing is due, so no read writes
        self.check(settled is not None and settled.status == 200, "the look before is taken")
        before = self.queue.snapshot()
        self.ops.rate = 1.0
        body = json.dumps(
            {"queue": QUEUES[0], "payload": "while unwritable", "max_tries": 2}
        ).encode()
        for _ in range(UNWRITABLE_STEPS):
            refused = self.send(Request("POST", "/jobs", "", "producer", body))
            self.check(refused is not None and refused.status == 503, "a write is refused")
            leased = self.send(Request("POST", f"/queues/{QUEUES[0]}/lease", "", "w1"))
            self.check(leased is not None and leased.status in {204, 503}, "a lease is refused")
            for path in ("/health", "/queues", "/jobs"):
                read = self.send(Request("GET", path, "", "operator"))
                self.check(read is not None and read.status == 200, f"{path} still answers")
            self.check(self.queue.snapshot() == before, "the unwritable folder changes no job")
        self.ops.rate = 0.0
        resumed = self.send(Request("POST", "/jobs", "", "producer", body))
        self.check(resumed is not None and resumed.status == 201, "the write resumes on its own")

    def run(self) -> None:
        self.ops.rate = FILE_FAULT_RATE
        self.drop_rate = SOCKET_DROP_RATE
        for _ in range(FAULT_STEPS):
            self.step()
        self.unwritable()
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
        self.assertGreater(sum(sim.scheduled for sim in sims), SEEDS)
        self.assertGreater(sum(sim.retried for sim in sims), SEEDS // 10)
        self.assertGreater(sum(sim.listed for sim in sims), SEEDS)

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
