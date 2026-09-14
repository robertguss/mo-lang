"""The queue: the job state machine, and the one place a job changes.

Every change goes through `_commit`, which checks the nevers, makes the record durable,
and only then applies it. A lease is a deadline, not a timer: every operation first looks
at the clock and returns each lease that ran out (`_look`).
"""

import heapq
from collections.abc import Callable
from dataclasses import dataclass
from typing import Concatenate

from jobq.clock import Clock
from jobq.contract import ensure, invariant, never, require
from jobq.jobs import (
    LIST_LIMIT,
    MAX_ATTEMPTS,
    MAX_LEASE_MS,
    MAX_REASON_BYTES,
    MIN_ATTEMPTS,
    MIN_LEASE_MS,
    STATES,
    Job,
    JobState,
    parse_job_id,
    payload_problem,
    queue_name_problem,
    text_problem,
    token_problem,
)
from jobq.store import DeleteRecord, PutRecord, Replayed, Store

_LEGAL: frozenset[tuple[JobState | None, JobState | None]] = frozenset(
    {
        (None, "queued"),
        ("queued", "leased"),
        ("leased", "done"),
        ("leased", "queued"),
        ("leased", "dead"),
        ("queued", None),
        ("done", None),
        ("dead", None),
    }
)


@dataclass(frozen=True)
class NotFound:
    pass


@dataclass(frozen=True)
class Conflict:
    reason: str


def operation[**P, R](
    method: Callable[Concatenate[Queue, P], R],
) -> Callable[Concatenate[Queue, P], R]:
    """Check the queue's invariants after the operation."""

    def checked(queue: Queue, *args: P.args, **kwargs: P.kwargs) -> R:
        result = method(queue, *args, **kwargs)
        queue.check_invariants()
        return result

    return checked


class Queue:
    def __init__(self, store: Store, clock: Clock, replayed: Replayed) -> None:
        self._store = store
        self._clock = clock
        self._jobs: dict[int, Job] = dict(replayed.jobs)
        self._next_number = replayed.next_number
        self._counts: dict[JobState, int] = dict.fromkeys(STATES, 0)
        self._queued: dict[str, list[int]] = {}
        self._leases: list[tuple[int, int]] = []
        self._touched: list[int] = []
        for job in self._jobs.values():
            self._counts[job.state] += 1
            self._index(job)
        self.check_all()

    # Reads. Each is a look, so each may return run-out leases first.

    @operation
    def get(self, job_id: str) -> Job | None:
        self._look()
        number = parse_job_id(job_id)
        return None if number is None else self._jobs.get(number)

    @operation
    def jobs(self, queue: str | None, state: JobState | None) -> list[Job]:
        """Jobs by id, at most 100, filtered by queue and state when given."""
        require(queue is None or queue_name_problem(queue) is None, "the queue name is valid")
        self._look()
        found = []
        for job in self._jobs.values():
            if (queue is None or job.queue == queue) and (state is None or job.state == state):
                found.append(job)
                if len(found) == LIST_LIMIT:
                    break
        return found

    @operation
    def counts(self) -> dict[JobState, int]:
        self._look()
        return dict(self._counts)

    # Changes.

    @operation
    def create(self, queue: str, payload: str, max_attempts: int) -> Job:
        require(queue_name_problem(queue) is None, "the queue name is valid")
        require(payload_problem(payload) is None, "the payload is valid")
        require(MIN_ATTEMPTS <= max_attempts <= MAX_ATTEMPTS, "max_attempts is 1 to 100")
        now = self._look()
        job = Job(
            number=self._next_number,
            queue=queue,
            state="queued",
            payload=payload,
            attempts=0,
            max_attempts=max_attempts,
            created_ms=now,
            updated_ms=now,
        )
        self._commit(None, job)
        ensure(self._jobs[job.number] is job and job.state == "queued", "the job is queued")
        return job

    @operation
    def lease(self, queue: str, worker: str, lease_ms: int) -> Job | None:
        """The oldest queued job of `queue`, leased to `worker`; None when nothing is queued."""
        require(queue_name_problem(queue) is None, "the queue name is valid")
        require(token_problem(worker) is None, "the worker is a token")
        require(MIN_LEASE_MS <= lease_ms <= MAX_LEASE_MS, "lease_ms is 100 to 3,600,000")
        now = self._look()
        waiting = self._queued.get(queue, [])
        while waiting:
            job = self._jobs.get(waiting[0])
            if job is None or job.state != "queued" or job.queue != queue:
                heapq.heappop(waiting)
                continue
            leased = job.model_copy(
                update={
                    "state": "leased",
                    "attempts": job.attempts + 1,
                    "worker": worker,
                    "lease_until_ms": now + lease_ms,
                    "updated_ms": now,
                }
            )
            self._commit(job, leased)
            heapq.heappop(waiting)
            ensure(leased.state == "leased" and leased.worker == worker, "leased to the caller")
            ensure(leased.attempts == job.attempts + 1, "attempts is one higher")
            return leased
        return None

    @operation
    def ack(self, job_id: str, worker: str) -> Job | NotFound | Conflict:
        now = self._look()
        job = self._find(job_id)
        if job is None:
            return NotFound()
        if not _holds_live_lease(job, worker, now):
            return Conflict("the caller does not hold a live lease on this job")
        done = job.model_copy(
            update={"state": "done", "worker": None, "lease_until_ms": None, "updated_ms": now}
        )
        self._commit(job, done)
        ensure(self._jobs[done.number].state == "done", "the job is done")
        return done

    @operation
    def fail(self, job_id: str, worker: str, reason: str) -> Job | NotFound | Conflict:
        require(text_problem("reason", reason, MAX_REASON_BYTES) is None, "the reason is valid")
        now = self._look()
        job = self._find(job_id)
        if job is None:
            return NotFound()
        if not _holds_live_lease(job, worker, now):
            return Conflict("the caller does not hold a live lease on this job")
        failed = _returned(job, now).model_copy(update={"reason": reason})
        self._commit(job, failed)
        return failed

    @operation
    def delete(self, job_id: str) -> Job | NotFound | Conflict:
        self._look()
        job = self._find(job_id)
        if job is None:
            return NotFound()
        if job.state == "leased":
            return Conflict("the job is leased")
        self._commit(job, None)
        return job

    @operation
    def expire_due(self) -> int:
        """The listener's idle look: return every lease that ran out. How many were."""
        return self._expire(self._clock.now_ms())

    # The one place a job changes.

    def _look(self) -> int:
        now = self._clock.now_ms()
        self._expire(now)
        return now

    def _expire(self, now: int) -> int:
        expired = 0
        while self._leases and self._leases[0][0] <= now:
            until, number = self._leases[0]
            job = self._jobs.get(number)
            if job is not None and job.state == "leased" and job.lease_until_ms == until:
                self._commit(job, _returned(job, now))
                expired += 1
            heapq.heappop(self._leases)
        return expired

    def _find(self, job_id: str) -> Job | None:
        number = parse_job_id(job_id)
        return None if number is None else self._jobs.get(number)

    def _commit(self, before: Job | None, after: Job | None) -> None:
        check_transition(before, after)
        if after is not None:
            self._store.append(PutRecord(job=after))
        elif before is not None:
            self._store.append(DeleteRecord(number=before.number))
        self._apply(before, after)

    def _apply(self, before: Job | None, after: Job | None) -> None:
        if before is not None:
            self._counts[before.state] -= 1
        if after is None:
            if before is not None:
                del self._jobs[before.number]
                self._touched.append(before.number)
            return
        self._jobs[after.number] = after
        self._counts[after.state] += 1
        self._next_number = max(self._next_number, after.number + 1)
        self._touched.append(after.number)
        self._index(after)

    def _index(self, job: Job) -> None:
        if job.state == "queued":
            heapq.heappush(self._queued.setdefault(job.queue, []), job.number)
        elif job.state == "leased" and job.lease_until_ms is not None:
            heapq.heappush(self._leases, (job.lease_until_ms, job.number))

    # Invariants: checked after every operation on the touched jobs, in O(1) otherwise.

    def check_invariants(self) -> None:
        invariant(sum(self._counts.values()) == len(self._jobs), "the counts add up to the jobs")
        invariant(all(count >= 0 for count in self._counts.values()), "no count is negative")
        for number in self._touched:
            job = self._jobs.get(number)
            invariant(number < self._next_number, "a job number is below the counter")
            if job is not None:
                check_job(number, job)
        self._touched.clear()

    def check_all(self) -> None:
        self._touched = list(self._jobs)
        self.check_invariants()
        for state in STATES:
            actual = sum(1 for job in self._jobs.values() if job.state == state)
            invariant(self._counts[state] == actual, f"the {state} count is right")

    @property
    def store(self) -> Store:
        return self._store

    def snapshot(self) -> dict[int, Job]:
        return dict(self._jobs)


def check_job(number: int, job: Job) -> None:
    invariant(job.number == number, "a job sits under its own number")
    leased = job.state == "leased"
    invariant(leased == (job.worker is not None), "a job has a worker exactly while leased")
    invariant(leased == (job.lease_until_ms is not None), "lease_until exactly while leased")
    invariant(job.state != "queued" or job.attempts < job.max_attempts, "queued has attempts left")


def check_transition(before: Job | None, after: Job | None) -> None:
    """The nevers, checked on every state change before it is written."""
    edge = (before.state if before else None, after.state if after else None)
    never(edge in _LEGAL, f"a job never goes {edge[0]} -> {edge[1]}")
    if before is None or after is None:
        return
    never(before.number == after.number, "a change never moves a job to another number")
    fixed = ("queue", "payload", "max_attempts", "created_ms")
    never(all(getattr(before, f) == getattr(after, f) for f in fixed), "a job's fields are fixed")
    never(after.attempts <= after.max_attempts, "attempts never exceed max_attempts")
    if after.state == "leased":
        never(before.state == "queued", "a job is never held by two workers at once")
        never(after.attempts == before.attempts + 1, "a lease counts one attempt")
    else:
        never(after.attempts == before.attempts, "only a lease counts an attempt")
    if edge in {("leased", "queued"), ("leased", "dead")}:
        dead = after.attempts == after.max_attempts
        never((after.state == "dead") == dead, "dead exactly when attempts reach max_attempts")


def _holds_live_lease(job: Job, worker: str, now: int) -> bool:
    return (
        job.state == "leased"
        and job.worker == worker
        and job.lease_until_ms is not None
        and now < job.lease_until_ms
    )


def _returned(job: Job, now: int) -> Job:
    """A leased job back from a fail or a run-out lease: queued, or dead on its last attempt."""
    state: JobState = "dead" if job.attempts >= job.max_attempts else "queued"
    return job.model_copy(
        update={"state": state, "worker": None, "lease_until_ms": None, "updated_ms": now}
    )
