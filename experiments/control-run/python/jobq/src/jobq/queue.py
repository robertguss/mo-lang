"""The queue: the job state machine, and the one place a job changes.

Every change goes through `_commit`, which checks the nevers, makes the record durable,
and only then applies it. A lease and a `run_at` are deadlines, not timers: every
operation first looks at the clock, returns each lease that ran out, and queues each
scheduled job that is due (`_look`); then it archives each done or dead job whose
`updated_ms` is `retain_ms` or more before now (`archive_step`, then `_archive_due`).

A job carries an optional idempotency `key`; the key map names the job, live or archived,
that holds each (queue, key), until that job is deleted.
"""

import heapq
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from typing import Concatenate

from jobq.clock import Clock
from jobq.contract import (
    BoardFailure,
    ChaosFailure,
    ContractError,
    ensure,
    invariant,
    never,
    require,
)
from jobq.jobs import (
    DEFAULT_RETAIN_MS,
    FINISHED,
    LIST_LIMIT,
    MAX_BACKOFF_MS,
    MAX_DELAY_MS,
    MAX_LEASE_MS,
    MAX_REASON_BYTES,
    MAX_RETAIN_MS,
    MAX_TRIES,
    MIN_LEASE_MS,
    MIN_RETAIN_MS,
    MIN_TRIES,
    STATES,
    Job,
    JobState,
    key_problem,
    parse_job_id,
    payload_problem,
    queue_name_problem,
    text_problem,
    token_problem,
)
from jobq.store import (
    ArchivedRecord,
    DeleteRecord,
    PutRecord,
    Replayed,
    Store,
    StoreError,
    key_map,
)

type Edge = tuple[JobState | None, JobState | None]

_LEGAL: frozenset[Edge] = frozenset(
    {
        (None, "queued"),
        (None, "scheduled"),
        ("scheduled", "queued"),
        ("queued", "leased"),
        ("leased", "done"),
        ("leased", "queued"),
        ("leased", "scheduled"),
        ("leased", "dead"),
        ("dead", "queued"),
        ("queued", None),
        ("scheduled", None),
        ("done", None),
        ("dead", None),
    }
)
# A leased job back from a fail or a run-out lease.
_RETURNS: frozenset[Edge] = frozenset(
    {("leased", "queued"), ("leased", "scheduled"), ("leased", "dead")}
)
_RETRY: Edge = ("dead", "queued")


@dataclass(frozen=True)
class NotFound:
    pass


@dataclass(frozen=True)
class Conflict:
    reason: str


def operation[**P, R](
    method: Callable[Concatenate[Queue, P], R],
) -> Callable[Concatenate[Queue, P], R]:
    """Check the queue's invariants after the operation. A store that cannot be written is
    the request's failure and leaves the board as it was; a broken rule is raised as it is;
    anything else is a `BoardFailure`, since the board may be half changed."""

    def checked(queue: Queue, /, *args: P.args, **kwargs: P.kwargs) -> R:
        try:
            result = method(queue, *args, **kwargs)
            queue.check_invariants()
        except (StoreError, ContractError, BoardFailure):
            raise
        except Exception as unexpected:
            raise BoardFailure(f"{method.__name__}: {unexpected!r}") from unexpected
        return result

    return checked


class Chaos:
    """`--crash-every N`: the N-th, 2N-th, ... job change the board applies fails after its
    record is on disk. The count lives as long as the process, across restarts; 0 never fails."""

    def __init__(self, every: int = 0) -> None:
        require(every >= 0, "crash_every is 0 or more")
        self.every = every
        self.applied = 0

    def fails(self, changes: int) -> bool:
        """Count `changes` more applied changes; whether a multiple of `every` was among them."""
        before = self.applied
        self.applied += changes
        return self.every > 0 and self.applied // self.every > before // self.every


def archive_step(jobs: Iterable[Job], now: int, retain_ms: int) -> list[Job]:
    """The archive move over the board, apart from any file: each done or dead job whose
    `updated_ms` is at least `retain_ms` before `now`, as the archive holds it."""
    require(MIN_RETAIN_MS <= retain_ms <= MAX_RETAIN_MS, "retain_ms is 1,000 to 2,678,400,000")
    moved = [
        job.model_copy(update={"archived_ms": now})
        for job in jobs
        if job.state in FINISHED and now - job.updated_ms >= retain_ms
    ]
    ensure(all(job.archived_ms == now for job in moved), "every moved job is archived now")
    return moved


class Queue:
    def __init__(
        self,
        store: Store,
        clock: Clock,
        replayed: Replayed,
        chaos: Chaos | None = None,
        retain_ms: int = DEFAULT_RETAIN_MS,
    ) -> None:
        require(MIN_RETAIN_MS <= retain_ms <= MAX_RETAIN_MS, "retain_ms is 1,000 to 2,678,400,000")
        self._store = store
        self._clock = clock
        self._chaos = chaos or Chaos()
        self._retain_ms = retain_ms
        self._jobs: dict[int, Job] = dict(replayed.jobs)
        self._archived: dict[int, Job] = dict(replayed.archived)
        self._keys: dict[tuple[str, str], int] = key_map(replayed)
        self._next_number = replayed.next_number
        self._counts: dict[JobState, int] = dict.fromkeys(STATES, 0)
        self._queued: dict[str, list[int]] = {}
        self._leases: list[tuple[int, int]] = []
        self._scheduled: list[tuple[int, int]] = []
        self._finished: list[tuple[int, int]] = []  # (updated_ms, number) of done and dead jobs
        self._unmarked: list[int] = []  # archived jobs the live log does not yet say left
        self._touched: list[int] = []
        for job in self._jobs.values():
            self._counts[job.state] += 1
            self._index(job)
        self.check_all()

    # Reads. Each is a look, so each may return run-out leases and queue due jobs first.

    @operation
    def get(self, job_id: str) -> Job | None:
        """The job, live or archived."""
        self._look()
        number = parse_job_id(job_id)
        if number is None:
            return None
        return self._jobs.get(number) or self._archived.get(number)

    @operation
    def keyed(self, queue: str, key: str) -> Job | None:
        """The job, live or archived, that holds `key` in `queue`."""
        require(queue_name_problem(queue) is None, "the queue name is valid")
        require(key_problem(key) is None, "the key is valid")
        self._look()
        return self._keyed(queue, key)

    def _keyed(self, queue: str, key: str) -> Job | None:
        number = self._keys.get((queue, key))
        if number is None:
            return None
        job = self._jobs.get(number) or self._archived.get(number)
        ensure(job is not None and job.key == key and job.queue == queue, "a key names its job")
        return job

    @operation
    def jobs(self, queue: str | None, state: JobState | None, key: str | None = None) -> list[Job]:
        """Live jobs by id, at most 100, filtered by queue and state when given. With a key,
        the one job that holds it in `queue`, live or archived, if its state matches."""
        require(queue is None or queue_name_problem(queue) is None, "the queue name is valid")
        require(key is None or (queue is not None and key_problem(key) is None), "a key's queue")
        self._look()
        if key is not None and queue is not None:
            job = self._keyed(queue, key)
            return [] if job is None or state not in {None, job.state} else [job]
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

    @property
    def archived_count(self) -> int:
        """How many jobs the archive holds; read after a look."""
        return len(self._archived)

    @operation
    def queue_counts(self) -> dict[str, dict[JobState, int]]:
        """Every queue that holds at least one job, by name, with its counts per state."""
        self._look()
        counts: dict[str, dict[JobState, int]] = {}
        for job in self._jobs.values():
            counts.setdefault(job.queue, dict.fromkeys(STATES, 0))[job.state] += 1
        return dict(sorted(counts.items()))

    # Changes.

    @operation
    def create(  # noqa: PLR0913 - the body's five fields and its optional key
        self,
        queue: str,
        payload: str,
        max_tries: int,
        delay_ms: int = 0,
        backoff_ms: int = 0,
        *,
        key: str | None = None,
    ) -> Job:
        """A new job: queued, or scheduled `delay_ms` from now when there is a delay. A `key`
        must not be in use in `queue` (`keyed` answers a create that reuses one)."""
        require(queue_name_problem(queue) is None, "the queue name is valid")
        require(payload_problem(payload) is None, "the payload is valid")
        require(MIN_TRIES <= max_tries <= MAX_TRIES, "max_tries is 1 to 100")
        require(0 <= delay_ms <= MAX_DELAY_MS, "delay_ms is 0 to 86,400,000")
        require(0 <= backoff_ms <= MAX_BACKOFF_MS, "backoff_ms is 0 to 3,600,000")
        require(key is None or key_problem(key) is None, "the key is valid")
        now = self._look()
        require(key is None or (queue, key) not in self._keys, "the key is not in use")
        job = Job(
            number=self._next_number,
            queue=queue,
            state="scheduled" if delay_ms > 0 else "queued",
            payload=payload,
            tries=0,
            max_tries=max_tries,
            backoff_ms=backoff_ms,
            created_ms=now,
            updated_ms=now,
            run_at_ms=now + delay_ms if delay_ms > 0 else None,
            key=key,
        )
        self._commit(None, job)
        ensure(self._jobs[job.number] is job, "the job is kept")
        ensure(key is None or self._keys[(queue, key)] == job.number, "the key names the job")
        if delay_ms > 0:
            ensure(job.state == "scheduled" and job.run_at_ms == now + delay_ms, "scheduled")
        else:
            ensure(job.state == "queued", "the job is queued")
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
                    "tries": job.tries + 1,
                    "worker": worker,
                    "lease_until_ms": now + lease_ms,
                    "updated_ms": now,
                }
            )
            self._commit(job, leased)
            heapq.heappop(waiting)
            ensure(leased.state == "leased" and leased.worker == worker, "leased to the caller")
            ensure(leased.tries == job.tries + 1, "tries is one higher")
            return leased
        return None

    @operation
    def ack(self, job_id: str, worker: str) -> Job | NotFound | Conflict:
        now = self._look()
        job = self._find(job_id)
        if job is None:
            return self._missing(job_id, _NOT_HELD)
        if not _holds_live_lease(job, worker, now):
            return Conflict(_NOT_HELD)
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
            return self._missing(job_id, _NOT_HELD)
        if not _holds_live_lease(job, worker, now):
            return Conflict(_NOT_HELD)
        failed = _returned(job, now).model_copy(update={"reason": reason})
        self._commit(job, failed)
        return failed

    @operation
    def retry(self, job_id: str) -> Job | NotFound | Conflict:
        """A dead job back in its queue with its tries at 0 and no reason."""
        now = self._look()
        job = self._find(job_id)
        if job is None:
            return self._missing(job_id, "archived")
        if job.state != "dead":
            return Conflict("the job is not dead")
        retried = job.model_copy(
            update={
                "state": "queued",
                "tries": 0,
                "reason": None,
                "worker": None,
                "lease_until_ms": None,
                "run_at_ms": None,
                "updated_ms": now,
            }
        )
        self._commit(job, retried)
        ensure(self._jobs[retried.number].state == "queued", "the job is queued")
        ensure(retried.tries == 0, "tries is 0")
        return retried

    @operation
    def delete(self, job_id: str) -> Job | NotFound | Conflict:
        """A live job is deleted by a live `delete`; an archived one by a live `delete` and
        then a tombstone in the archive, so no stale live record of it can come back."""
        self._look()
        job = self._find(job_id)
        if job is None:
            number = parse_job_id(job_id)
            archived = None if number is None else self._archived.get(number)
            if archived is None:
                return NotFound()
            self._store.append(DeleteRecord(number=archived.number))
            self._store.append_archive([DeleteRecord(number=archived.number)])
            self._unarchive(archived)
            ensure(archived.number not in self._archived, "the archived job is deleted")
            return archived
        if job.state == "leased":
            return Conflict("the job is leased")
        self._commit(job, None)
        return job

    @operation
    def expire_due(self) -> int:
        """The listener's idle look: return every lease that ran out and queue every scheduled
        job that is due. How many jobs moved."""
        return self._expire(self._clock.now_ms())

    # The one place a job changes.

    def _look(self) -> int:
        now = self._clock.now_ms()
        self._expire(now)
        return now

    def _missing(self, job_id: str, reason: str) -> NotFound | Conflict:
        """No live job: a Conflict naming `reason` when it is archived, NotFound otherwise."""
        number = parse_job_id(job_id)
        return NotFound() if number is None or number not in self._archived else Conflict(reason)

    def _expire(self, now: int) -> int:
        """Return every run-out lease and queue every due scheduled job in one durable write,
        so a look after a long stop is one fsync rather than one per job."""
        due: list[tuple[Job | None, Job | None]] = []
        popped_leases: list[tuple[int, int]] = []
        while self._leases and self._leases[0][0] <= now:
            until, number = heapq.heappop(self._leases)
            popped_leases.append((until, number))
            job = self._jobs.get(number)
            if job is not None and job.state == "leased" and job.lease_until_ms == until:
                due.append((job, _returned(job, now)))
        # A lease returned above is scheduled strictly after `now`, so no job moves twice.
        popped_runs: list[tuple[int, int]] = []
        while self._scheduled and self._scheduled[0][0] <= now:
            run_at, number = heapq.heappop(self._scheduled)
            popped_runs.append((run_at, number))
            job = self._jobs.get(number)
            if job is not None and job.state == "scheduled" and job.run_at_ms == run_at:
                due.append((job, _queued_when_due(job, now)))
        try:
            self._commit_all(due)
        except StoreError:
            for entry in popped_leases:
                heapq.heappush(self._leases, entry)
            for entry in popped_runs:
                heapq.heappush(self._scheduled, entry)
            raise
        return len(due) + self._archive_due(now)

    def _archive_due(self, now: int) -> int:
        """Move every done or dead job past `retain_ms` to the archive: the archive's write,
        then the live log's `archived` records, both durable before the look answers. The
        archive wins at open, so once its write is on disk the move is made; a live record
        that cannot be written is written at a later look. How many jobs moved."""
        popped: list[tuple[int, int]] = []
        candidates: list[Job] = []
        while self._finished and self._finished[0][0] <= now - self._retain_ms:
            updated, number = heapq.heappop(self._finished)
            popped.append((updated, number))
            job = self._jobs.get(number)
            if job is not None and job.state in FINISHED and job.updated_ms == updated:
                candidates.append(job)
        moved = archive_step(candidates, now, self._retain_ms)
        if moved:
            try:
                self._store.append_archive([PutRecord(job=job) for job in moved])
            except StoreError:
                for entry in popped:
                    heapq.heappush(self._finished, entry)
                raise
            if self._chaos.fails(len(moved)):
                raise ChaosFailure(
                    f"--crash-every {self._chaos.every} between the archive and the log"
                )
            for job in moved:
                self._archive(job)
        if self._unmarked:
            try:
                self._store.append_all([ArchivedRecord(number=n) for n in self._unmarked])
                self._unmarked.clear()
            except StoreError:
                pass  # the archive already holds the jobs; the next look writes the records
        return len(moved)

    def _archive(self, archived: Job) -> None:
        live = self._jobs.pop(archived.number)
        never(live.state in FINISHED, "only a done or dead job is archived")
        never(archived.model_copy(update={"archived_ms": None}) == live, "a job archives as is")
        self._counts[live.state] -= 1
        self._archived[archived.number] = archived
        self._unmarked.append(archived.number)
        self._touched.append(archived.number)

    def _unarchive(self, archived: Job) -> None:
        del self._archived[archived.number]
        if archived.key is not None:
            del self._keys[(archived.queue, archived.key)]
        self._touched.append(archived.number)

    def _find(self, job_id: str) -> Job | None:
        number = parse_job_id(job_id)
        return None if number is None else self._jobs.get(number)

    def _commit(self, before: Job | None, after: Job | None) -> None:
        self._commit_all([(before, after)])

    def _commit_all(self, changes: list[tuple[Job | None, Job | None]]) -> None:
        """Check every change's nevers, make all of them durable, and only then apply them."""
        if not changes:
            return
        records: list[PutRecord | DeleteRecord] = []
        for before, after in changes:
            check_transition(before, after)
            never(after is None or after.archived_ms is None, "a live job is never archived")
            if after is not None:
                records.append(PutRecord(job=after))
            elif before is not None:
                records.append(DeleteRecord(number=before.number))
        self._store.append_all(records)
        if self._chaos.fails(len(changes)):
            raise ChaosFailure(f"--crash-every {self._chaos.every} at change {self._chaos.applied}")
        for before, after in changes:
            self._apply(before, after)

    def _apply(self, before: Job | None, after: Job | None) -> None:
        if before is not None:
            self._counts[before.state] -= 1
        if after is None:
            if before is not None:
                del self._jobs[before.number]
                if before.key is not None:
                    del self._keys[(before.queue, before.key)]
                self._touched.append(before.number)
            return
        if before is None and after.key is not None:
            never((after.queue, after.key) not in self._keys, "a key never names two jobs")
            self._keys[(after.queue, after.key)] = after.number
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
        elif job.state == "scheduled" and job.run_at_ms is not None:
            heapq.heappush(self._scheduled, (job.run_at_ms, job.number))
        elif job.state in FINISHED:
            heapq.heappush(self._finished, (job.updated_ms, job.number))

    # Invariants: checked after every operation on the touched jobs, in O(1) otherwise.

    def check_invariants(self) -> None:
        invariant(sum(self._counts.values()) == len(self._jobs), "the counts add up to the jobs")
        invariant(all(count >= 0 for count in self._counts.values()), "no count is negative")
        for number in self._touched:
            job = self._jobs.get(number)
            invariant(number < self._next_number, "a job number is below the counter")
            archived = self._archived.get(number)
            invariant(job is None or archived is None, "a job is live or archived, not both")
            for held in (job, archived):
                if held is not None:
                    check_job(number, held)
        self._touched.clear()

    def check_all(self) -> None:
        self._touched = list(self._jobs)
        self.check_invariants()
        for state in STATES:
            actual = sum(1 for job in self._jobs.values() if job.state == state)
            invariant(self._counts[state] == actual, f"the {state} count is right")
        invariant(self._keys == key_map(Replayed(self._jobs, 0, 0, self._archived)), "keys")

    @property
    def store(self) -> Store:
        return self._store

    def snapshot(self) -> dict[int, Job]:
        return dict(self._jobs)

    def archived_snapshot(self) -> dict[int, Job]:
        return dict(self._archived)


def check_job(number: int, job: Job) -> None:
    invariant(job.number == number, "a job sits under its own number")
    archived = job.archived_ms is not None
    invariant(not archived or job.state in FINISHED, "only a done or dead job is archived")
    leased = job.state == "leased"
    invariant(leased == (job.worker is not None), "a job has a worker exactly while leased")
    invariant(leased == (job.lease_until_ms is not None), "lease_until exactly while leased")
    scheduled = job.state == "scheduled"
    invariant(scheduled == (job.run_at_ms is not None), "run_at exactly while scheduled")
    waiting = job.state in {"queued", "scheduled"}
    invariant(not waiting or job.tries < job.max_tries, "a queued or scheduled job has tries left")


def check_transition(before: Job | None, after: Job | None) -> None:
    """The nevers, checked on every state change before it is written."""
    edge: Edge = (before.state if before else None, after.state if after else None)
    if edge == ("leased", "leased"):
        never(False, "a job is never held by two workers at once")
    never(edge in _LEGAL, f"a job never goes {edge[0]} -> {edge[1]}")
    if before is None or after is None:
        return
    never(before.number == after.number, "a change never moves a job to another number")
    fixed = ("queue", "payload", "max_tries", "backoff_ms", "created_ms", "key")
    never(all(getattr(before, f) == getattr(after, f) for f in fixed), "a job's fields are fixed")
    never(after.tries <= after.max_tries, "tries never exceed max_tries")
    if after.state == "leased":
        never(before.state == "queued", "a job is never held by two workers at once")
        never(after.tries == before.tries + 1, "a lease counts one try")
    elif edge == _RETRY:
        never(after.tries == 0, "a retry sets tries to 0")
    else:
        never(after.tries == before.tries, "only a lease counts a try and only a retry resets")
    if edge in _RETURNS:
        dead = after.tries == after.max_tries
        never((after.state == "dead") == dead, "dead exactly when tries reach max_tries")
        backoff = not dead and after.backoff_ms > 0
        never((after.state == "scheduled") == backoff, "scheduled exactly when it has a backoff")
    if edge == ("scheduled", "queued"):
        due = before.run_at_ms is not None and after.updated_ms >= before.run_at_ms
        never(due, "a scheduled job is never queued before its run_at")


_NOT_HELD = "the caller does not hold a live lease on this job"


def _holds_live_lease(job: Job, worker: str, now: int) -> bool:
    return (
        job.state == "leased"
        and job.worker == worker
        and job.lease_until_ms is not None
        and now < job.lease_until_ms
    )


def _returned(job: Job, now: int) -> Job:
    """A leased job back from a fail or a run-out lease: dead on its last try, scheduled
    `backoff_ms` from now when it has a backoff, and queued otherwise."""
    state: JobState = "queued"
    run_at_ms = None
    if job.tries >= job.max_tries:
        state = "dead"
    elif job.backoff_ms > 0:
        state, run_at_ms = "scheduled", now + job.backoff_ms
    return job.model_copy(
        update={
            "state": state,
            "run_at_ms": run_at_ms,
            "worker": None,
            "lease_until_ms": None,
            "updated_ms": now,
        }
    )


def _queued_when_due(job: Job, now: int) -> Job:
    """A scheduled job whose `run_at` has passed, queued at this look."""
    return job.model_copy(update={"state": "queued", "run_at_ms": None, "updated_ms": now})
