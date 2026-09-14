"""`--sim 100 --faults`: the queue under 100 seeds of injected file and socket failures.

Every response is judged against a second, deliberately simple model of the rules; a 503 must
leave memory and the durable log unchanged; the durable log must replay to the live state; no
lease is ever handed out on a job another worker still holds; and once the faults stop, workers
that keep working bring every job to done or dead."""

import copy
import random
import unittest
from dataclasses import dataclass
from pathlib import Path

from jobq.api import Request, Response, respond
from jobq.fs import MemoryFile, MemoryFs
from jobq.model import Job
from jobq.queue import Queue
from jobq.store import Store
from tests.support import LOG, SIM_DIR, Rig, body_of

SEEDS = 100
STEPS = 150
FILE_FAULT_RATE = 0.12
SOCKET_FAULT_RATE = 0.08
CRASH_RATE = 0.03
QUEUES = ("a", "b")
WORKERS = ("w1", "w2", "w3")
DRAIN_ROUNDS = 3_000


@dataclass(frozen=True)
class Create:
    queue: str
    max_attempts: int


@dataclass(frozen=True)
class Lease:
    queue: str
    worker: str
    lease_ms: int


@dataclass(frozen=True)
class Ack:
    job_id: str
    worker: str


@dataclass(frozen=True)
class Fail:
    job_id: str
    worker: str


@dataclass(frozen=True)
class Delete:
    job_id: str


@dataclass(frozen=True)
class Get:
    job_id: str


@dataclass(frozen=True)
class Health:
    pass


type Op = Create | Lease | Ack | Fail | Delete | Get | Health


@dataclass
class ModelJob:
    queue: str
    state: str
    attempts: int
    max_attempts: int
    worker: str | None = None
    lease_until: int | None = None


class Model:
    def __init__(self) -> None:
        self.jobs: dict[str, ModelJob] = {}
        self.next_id = 1

    def apply(self, op: Op, now: int) -> tuple[int, str | None]:
        """The status the rules call for, and the job it names; the model moves on."""
        self._expire(now)
        match op:
            case Create(queue, max_attempts):
                job_id = f"j_{self.next_id}"
                self.next_id += 1
                self.jobs[job_id] = ModelJob(queue, "queued", 0, max_attempts)
                return 201, job_id
            case Lease(queue, worker, lease_ms):
                waiting = [
                    i for i, j in self.jobs.items() if j.queue == queue and j.state == "queued"
                ]
                if not waiting:
                    return 204, None
                job_id = min(waiting, key=lambda i: int(i[2:]))
                chosen = self.jobs[job_id]
                chosen.state, chosen.worker, chosen.lease_until = "leased", worker, now + lease_ms
                chosen.attempts += 1
                return 200, job_id
            case Ack(job_id, worker) | Fail(job_id, worker):
                job = self.jobs.get(job_id)
                if job is None:
                    return 404, None
                if job.state != "leased" or job.worker != worker:
                    return 409, None
                if isinstance(op, Ack):
                    job.state = "done"
                else:
                    job.state = "queued" if job.attempts < job.max_attempts else "dead"
                job.worker = job.lease_until = None
                return 200, job_id
            case Delete(job_id):
                target = self.jobs.get(job_id)
                if target is None:
                    return 404, None
                if target.state == "leased":
                    return 409, None
                del self.jobs[job_id]
                return 204, None
            case Get(job_id):
                return (200, job_id) if job_id in self.jobs else (404, None)
            case Health():
                return 200, None

    def _expire(self, now: int) -> None:
        for job in self.jobs.values():
            if job.state == "leased" and job.lease_until is not None and now >= job.lease_until:
                job.state = "queued" if job.attempts < job.max_attempts else "dead"
                job.worker = job.lease_until = None

    def settled(self) -> bool:
        return all(job.state in ("done", "dead") for job in self.jobs.values())


def to_request(op: Op, step: int) -> Request:
    match op:
        case Create(queue, max_attempts):
            body = f'{{"queue": "{queue}", "payload": "p{step}", "max_attempts": {max_attempts}}}'
            return request("POST", "/jobs", "producer", body)
        case Lease(queue, worker, lease_ms):
            return request("POST", f"/queues/{queue}/lease", worker, f'{{"lease_ms": {lease_ms}}}')
        case Ack(job_id, worker):
            return request("POST", f"/jobs/{job_id}/ack", worker)
        case Fail(job_id, worker):
            return request("POST", f"/jobs/{job_id}/fail", worker, '{"reason": "sim"}')
        case Delete(job_id):
            return request("DELETE", f"/jobs/{job_id}", "producer")
        case Get(job_id):
            return request("GET", f"/jobs/{job_id}", "producer")
        case Health():
            return request("GET", "/health", None)


def request(method: str, path: str, token: str | None, body: str = "") -> Request:
    headers = {} if token is None else {"authorization": f"Bearer {token}"}
    return Request(method, path, headers, body.encode())


def random_op(rng: random.Random, model: Model) -> Op:
    held = [(i, j.worker) for i, j in model.jobs.items() if j.state == "leased" and j.worker]
    job_id = rng.choice([*model.jobs, "j_999"])
    worker = rng.choice(WORKERS)
    if held and rng.random() < 0.6:
        job_id, holder = rng.choice(held)
        worker = holder or worker
    kind = rng.choices(range(7), weights=[4, 5, 3, 2, 1, 1, 1])[0]
    ops: list[Op] = [
        Create(rng.choice(QUEUES), rng.randint(1, 3)),
        Lease(rng.choice(QUEUES), worker, rng.randint(100, 3_000)),
        Ack(job_id, worker),
        Fail(job_id, worker),
        Delete(job_id),
        Get(job_id),
        Health(),
    ]
    return ops[kind]


def shape(jobs: dict[str, Job]) -> dict[str, tuple[object, ...]]:
    return {
        i: (j.queue, j.state.value, j.attempts, j.max_attempts, j.worker, j.lease_until)
        for i, j in jobs.items()
    }


def model_shape(model: Model) -> dict[str, tuple[object, ...]]:
    return {
        i: (j.queue, j.state, j.attempts, j.max_attempts, j.worker, j.lease_until)
        for i, j in model.jobs.items()
    }


def replay_durable(rig: Rig) -> dict[str, Job]:
    durable = rig.durable_log()
    fs = MemoryFs()
    fs.files[LOG] = MemoryFile(bytearray(durable), durable)
    return Queue.open(Store(fs, SIM_DIR), rig.clock).snapshot()


class Sim:
    def __init__(self, test: unittest.TestCase, seed: int) -> None:
        self.test = test
        self.seed = seed
        self.rng = random.Random(seed)
        self.rig = Rig(seed)
        self.model = Model()
        self.holders: dict[str, tuple[str, int]] = {}
        self.step = 0

    def run(self) -> None:
        self.rig.faults.rate = FILE_FAULT_RATE
        for _ in range(STEPS):
            if self.rng.random() < 0.3:
                self.rig.clock.advance(self.rng.randint(0, 1_500))
            if self.rng.random() < SOCKET_FAULT_RATE:
                continue
            self.play(random_op(self.rng, self.model))
            if self.rng.random() < CRASH_RATE and self.rig.store.clean:
                self.crash()
        self.rig.faults.rate = 0.0
        self.drain()
        self.test.assertTrue(self.model.settled(), f"seed {self.seed}: not every job settled")
        self.test.assertEqual(shape(self.rig.restart().snapshot()), model_shape(self.model))

    def play(self, op: Op) -> Response:
        self.step += 1
        before = (self.rig.queue.snapshot(),)
        response = respond(self.rig.queue, to_request(op, self.step))
        where = f"seed {self.seed} step {self.step} {op}"
        if response.status == 503:
            self.test.assertEqual(self.rig.queue.snapshot(), before[0], where)
            if self.rig.store.clean:
                self.test.assertEqual(replay_durable(self.rig), before[0], where)
            return response
        now = self.rig.clock.now_ms()
        expected, job_id = self.model.apply(op, now)
        self.test.assertEqual(response.status, expected, f"{where}: {response.body!r}")
        if job_id is not None and response.status in (200, 201):
            self.test.assertEqual(body_of(response)["id"], job_id, where)
        self.check_holders(op, response, job_id, now, where)
        self.test.assertEqual(shape(self.rig.queue.snapshot()), model_shape(self.model), where)
        if self.rig.store.clean:
            self.test.assertEqual(replay_durable(self.rig), self.rig.queue.snapshot(), where)
        return response

    def check_holders(
        self, op: Op, response: Response, job_id: str | None, now: int, where: str
    ) -> None:
        if job_id is None or response.status != 200:
            return
        if isinstance(op, Lease):
            holder = self.holders.get(job_id)
            self.test.assertFalse(holder is not None and holder[1] > now, f"{where}: held twice")
            self.holders[job_id] = (op.worker, now + op.lease_ms)
        elif isinstance(op, Ack | Fail):
            self.holders.pop(job_id, None)

    def crash(self) -> None:
        rate, self.rig.faults.rate = self.rig.faults.rate, 0.0
        self.rig.restart()
        self.rig.faults.rate = rate
        where = f"seed {self.seed} after a crash at step {self.step}"
        self.test.assertEqual(shape(self.rig.queue.snapshot()), model_shape(self.model), where)

    def drain(self) -> None:
        for _ in range(DRAIN_ROUNDS):
            if self.model.settled():
                return
            self.rig.clock.advance(self.rng.randint(0, 1_000))
            worker = self.rng.choice(WORKERS)
            response = self.play(Lease(self.rng.choice(QUEUES), worker, 500))
            if response.status == 200:
                job_id = body_of(response)["id"]
                done = self.rng.random() < 0.7
                self.play(Ack(job_id, worker) if done else Fail(job_id, worker))


class SimTest(unittest.TestCase):
    def test_100_seeds_with_file_and_socket_faults(self) -> None:
        injected = 0
        for seed in range(SEEDS):
            sim = Sim(self, seed)
            sim.run()
            injected += sim.rig.faults.injected
        self.assertGreater(injected, SEEDS)

    def test_the_model_itself_rejects_a_wrong_answer(self) -> None:
        model = Model()
        model.apply(Create("a", 1), 0)
        self.assertEqual(model.apply(Lease("a", "w1", 100), 0), (200, "j_1"))
        self.assertEqual(model.apply(Lease("a", "w2", 100), 50), (204, None))
        self.assertEqual(model.apply(Ack("j_1", "w1"), 100), (409, None))
        self.assertEqual(copy.deepcopy(model).jobs["j_1"].state, "dead")
        self.assertEqual(Path(LOG).name, "jobs.log")


if __name__ == "__main__":
    unittest.main()
