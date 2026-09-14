"""The queue. Every look and every change is one transaction, durable before it is applied."""

import heapq
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from enum import Enum, auto

from jobq.clock import Clock
from jobq.contract import ContractError, ensure, invariant, never, require
from jobq.model import (
    Job,
    JobState,
    is_lease_ms,
    is_max_attempts,
    is_queue_name,
    is_worker,
    job_id_of,
    job_number,
    payload_problem,
    reason_problem,
)
from jobq.store import CounterRecord, DeleteRecord, PutRecord, Record, Store, StoreCorrupt

LIST_LIMIT = 100
LEASE_RAN_OUT = "lease ran out"

_NEXT_STATES = {
    JobState.QUEUED: {JobState.LEASED},
    JobState.LEASED: {JobState.DONE, JobState.QUEUED, JobState.DEAD},
    JobState.DONE: set[JobState](),
    JobState.DEAD: set[JobState](),
}


class Refusal(Enum):
    NOT_FOUND = auto()
    CONFLICT = auto()


@dataclass(frozen=True)
class Health:
    queued: int
    leased: int
    done: int
    dead: int
    uptime_ms: int


def check_job(job: Job) -> None:
    """The invariants on one job; a replayed record can break every one of them."""
    never(job.attempts > job.max_attempts, f"{job.id} has more attempts than max_attempts")
    leased = job.state is JobState.LEASED
    invariant(
        leased == (job.worker is not None) == (job.lease_until is not None),
        f"{job.id} has a worker and lease_until exactly while leased",
    )
    invariant(
        job.state is not JobState.QUEUED or job.attempts < job.max_attempts,
        f"queued {job.id} has an attempt left",
    )
    invariant(
        job.state is not JobState.DEAD or job.attempts == job.max_attempts,
        f"dead {job.id} used every attempt",
    )
    invariant(
        job.state not in (JobState.LEASED, JobState.DONE) or job.attempts >= 1,
        f"{job.state} {job.id} was leased at least once",
    )
    invariant(job.updated_at >= job.created_at, f"{job.id} is not updated before it was created")


def check_change(old: Job, new: Job | None) -> None:
    """The nevers, asserted on every state change before it is written."""
    if new is None:
        never(old.state is JobState.LEASED, f"{old.id} is deleted while leased")
        return
    never(
        (new.id, new.queue, new.max_attempts, new.created_at)
        != (old.id, old.queue, old.max_attempts, old.created_at)
        or new.payload != old.payload,
        f"{old.id} changes what it was created with",
    )
    leased = new.state is JobState.LEASED
    never(old.state is JobState.DONE and leased, f"done {old.id} is leased again")
    never(old.state is JobState.DEAD and new.state is JobState.LEASED, f"dead {old.id} is leased")
    never(
        old.state is JobState.LEASED and new.state is JobState.LEASED,
        f"{old.id} is held by two workers at once",
    )
    never(new.state not in _NEXT_STATES[old.state], f"{old.id} goes {old.state} to {new.state}")
    step = 1 if new.state is JobState.LEASED else 0
    never(new.attempts != old.attempts + step, f"{old.id} changes attempts other than by a lease")
    check_job(new)


class _Txn:
    def __init__(self, jobs: dict[str, Job], next_id: int, now: int) -> None:
        self._jobs = jobs
        self.now = now
        self.next_id = next_id
        self.staged: dict[str, Job | None] = {}
        self.records: list[Record] = []
        self.popped_leases: list[tuple[int, int]] = []

    def job(self, job_id: str) -> Job | None:
        if job_id in self.staged:
            return self.staged[job_id]
        return self._jobs.get(job_id)

    def put(self, new: Job) -> None:
        old = self.job(new.id)
        if old is None:
            never(
                new.state is not JobState.QUEUED or new.attempts != 0,
                f"{new.id} starts anywhere but queued with no attempts",
            )
            check_job(new)
        else:
            check_change(old, new)
        self.staged[new.id] = new
        self.records.append(PutRecord(job=new))

    def delete(self, job_id: str) -> None:
        old = self.job(job_id)
        require(old is not None, f"{job_id} exists to be deleted")
        if old is not None:
            check_change(old, None)
        self.staged[job_id] = None
        self.records.append(DeleteRecord(id=job_id))


class Queue:
    def __init__(self, store: Store, clock: Clock) -> None:
        self._store = store
        self._clock = clock
        self._jobs: dict[str, Job] = {}
        self._next_id = 1
        self._queued: dict[str, list[int]] = {}
        self._leases: list[tuple[int, int]] = []
        self._counts = dict.fromkeys(JobState, 0)

    @classmethod
    def open(cls, store: Store, clock: Clock) -> Queue:
        """Replay the store. StoreCorrupt if a record breaks a never or an invariant."""
        queue = cls(store, clock)
        store.open(queue._replay)
        return queue

    @property
    def next_id(self) -> int:
        return self._next_id

    def snapshot(self) -> dict[str, Job]:
        return dict(self._jobs)

    def create(self, queue: str, payload: str, max_attempts: int) -> Job:
        require(is_queue_name(queue), "queue is 1 to 64 letters, digits, - or _")
        require(payload_problem(payload) is None, "payload is 60 KiB of UTF-8 at most, no controls")
        require(is_max_attempts(max_attempts), "1 <= max_attempts <= 100")

        def body(txn: _Txn) -> Job:
            job = Job(
                id=job_id_of(txn.next_id),
                queue=queue,
                state=JobState.QUEUED,
                payload=payload,
                attempts=0,
                max_attempts=max_attempts,
                created_at=txn.now,
                updated_at=txn.now,
            )
            txn.next_id += 1
            txn.put(job)
            return job

        return self._transact(body)

    def get(self, job_id: str) -> Job | None:
        return self._transact(lambda txn: txn.job(job_id))

    def list(self, queue: str | None = None, state: JobState | None = None) -> list[Job]:
        def body(txn: _Txn) -> list[Job]:
            found: list[Job] = []
            for job_id in self._jobs:
                job = txn.job(job_id)
                if job is None or queue not in (None, job.queue) or state not in (None, job.state):
                    continue
                found.append(job)
                if len(found) == LIST_LIMIT:
                    break
            return found

        return self._transact(body)

    def delete(self, job_id: str) -> Refusal | None:
        def body(txn: _Txn) -> Refusal | None:
            job = txn.job(job_id)
            if job is None:
                return Refusal.NOT_FOUND
            if job.state is JobState.LEASED:
                return Refusal.CONFLICT
            txn.delete(job_id)
            return None

        return self._transact(body)

    def lease(self, queue: str, worker: str, lease_ms: int) -> Job | None:
        require(is_queue_name(queue), "queue is 1 to 64 letters, digits, - or _")
        require(is_worker(worker), "worker is 1 to 256 visible ASCII characters")
        require(is_lease_ms(lease_ms), "100 <= lease_ms <= 3,600,000")

        def body(txn: _Txn) -> tuple[Job, Job] | None:
            job = self._oldest_queued(txn, queue)
            if job is None:
                return None
            leased = job.model_copy(
                update={
                    "state": JobState.LEASED,
                    "attempts": job.attempts + 1,
                    "worker": worker,
                    "lease_until": txn.now + lease_ms,
                    "updated_at": max(txn.now, job.updated_at),
                }
            )
            txn.put(leased)
            return job, leased

        change = self._transact(body)
        if change is None:
            return None
        before, after = change
        ensure(
            after.state is JobState.LEASED
            and after.worker == worker
            and after.attempts == before.attempts + 1,
            "the job returned is leased to the caller with attempts one higher",
        )
        return after

    def ack(self, job_id: str, worker: str) -> Job | Refusal:
        def body(txn: _Txn) -> Job | Refusal:
            job = self._held(txn, job_id, worker)
            if isinstance(job, Refusal):
                return job
            done = job.model_copy(
                update={
                    "state": JobState.DONE,
                    "worker": None,
                    "lease_until": None,
                    "updated_at": max(txn.now, job.updated_at),
                }
            )
            txn.put(done)
            return done

        result = self._transact(body)
        ensure(isinstance(result, Refusal) or result.state is JobState.DONE, "the job is done")
        return result

    def fail(self, job_id: str, worker: str, reason: str) -> Job | Refusal:
        require(reason_problem(reason) is None, "reason is 4 KiB of UTF-8 at most, no controls")

        def body(txn: _Txn) -> Job | Refusal:
            job = self._held(txn, job_id, worker)
            if isinstance(job, Refusal):
                return job
            released = _released(job, txn.now, reason)
            txn.put(released)
            return released

        return self._transact(body)

    def expire(self) -> None:
        """A look at every lease: the listener's Idle."""
        self._transact(lambda txn: None)

    def health(self) -> Health:
        self._transact(lambda txn: None)
        counts = self._counts
        return Health(
            queued=counts[JobState.QUEUED],
            leased=counts[JobState.LEASED],
            done=counts[JobState.DONE],
            dead=counts[JobState.DEAD],
            uptime_ms=self._clock.uptime_ms(),
        )

    def compact(self) -> int:
        """Rewrite the log to the counter and one line per live job; the store is closed."""
        self._store.compact(self._live_records())
        return len(self._jobs) + 1

    def _live_records(self) -> Iterator[Record]:
        yield CounterRecord(next_id=self._next_id)
        for job in self._jobs.values():
            yield PutRecord(job=job)

    def _transact[T](self, body: Callable[[_Txn], T]) -> T:
        txn = _Txn(self._jobs, self._next_id, self._clock.now_ms())
        try:
            self._stage_expiries(txn)
            result = body(txn)
            if txn.records:
                self._store.append(txn.records)
        except BaseException:
            for entry in txn.popped_leases:
                heapq.heappush(self._leases, entry)
            raise
        ensure(self._store.synced == self._store.written, "every record is durable before applied")
        for job_id, job in txn.staged.items():
            self._apply(job_id, job)
        self._next_id = txn.next_id
        for job_id in txn.staged:
            if (job := self._jobs.get(job_id)) is not None:
                check_job(job)
        return result

    def _stage_expiries(self, txn: _Txn) -> None:
        while self._leases and self._leases[0][0] <= txn.now:
            entry = heapq.heappop(self._leases)
            until, number = entry
            job = txn.job(job_id_of(number))
            if job is None or job.state is not JobState.LEASED or job.lease_until != until:
                continue
            txn.popped_leases.append(entry)
            released = _released(job, txn.now, LEASE_RAN_OUT)
            txn.put(released)
            if released.state is JobState.QUEUED:
                heapq.heappush(self._queued.setdefault(job.queue, []), number)

    def _oldest_queued(self, txn: _Txn, queue: str) -> Job | None:
        heap = self._queued.get(queue)
        while heap:
            job = txn.job(job_id_of(heap[0]))
            if job is not None and job.state is JobState.QUEUED:
                return job
            heapq.heappop(heap)
        return None

    def _held(self, txn: _Txn, job_id: str, worker: str) -> Job | Refusal:
        job = txn.job(job_id)
        if job is None:
            return Refusal.NOT_FOUND
        if job.state is not JobState.LEASED or job.worker != worker:
            return Refusal.CONFLICT
        return job

    def _apply(self, job_id: str, new: Job | None) -> None:
        old = self._jobs.get(job_id)
        if old is not None:
            self._counts[old.state] -= 1
        if new is None:
            self._jobs.pop(job_id, None)
            return
        self._jobs[job_id] = new
        self._counts[new.state] += 1
        if new.state is JobState.QUEUED:
            heapq.heappush(self._queued.setdefault(new.queue, []), job_number(job_id))
        elif new.state is JobState.LEASED and new.lease_until is not None:
            heapq.heappush(self._leases, (new.lease_until, job_number(job_id)))

    def _replay(self, record: Record) -> None:
        try:
            match record:
                case PutRecord(job=job):
                    old = self._jobs.get(job.id)
                    if old is None:
                        check_job(job)
                    else:
                        check_change(old, job)
                    self._apply(job.id, job)
                    self._next_id = max(self._next_id, job_number(job.id) + 1)
                case DeleteRecord(id=job_id):
                    old = self._jobs.get(job_id)
                    invariant(old is not None, f"deleted {job_id} exists")
                    if old is not None:
                        check_change(old, None)
                    self._apply(job_id, None)
                case CounterRecord(next_id=next_id):
                    self._next_id = max(self._next_id, next_id)
        except ContractError as err:
            raise StoreCorrupt(str(err)) from err


def _released(job: Job, now: int, reason: str) -> Job:
    """A lease ends without an ack: queued with attempts left, dead without."""
    state = JobState.QUEUED if job.attempts < job.max_attempts else JobState.DEAD
    return job.model_copy(
        update={
            "state": state,
            "worker": None,
            "lease_until": None,
            "reason": reason,
            "updated_at": max(now, job.updated_at),
        }
    )
