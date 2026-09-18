"""The store: an append-only log of JSON lines in `<dir>/jobs.log` that replays, and beside
it the archive `<dir>/jobq.archive`, append-only between compactions.

One record per job change, under the job's number. A done or dead job that is archived is
appended to the archive first (with `archived_ms`), and then the live log records that it
left the board (an `archived` record). At open the archive wins: a job in both files is
archived, whichever write a kill fell between. A delete of an archived job writes a live
`delete` first and then a `delete` tombstone in the archive; compaction drops both. A write
is durable when `append` returns; when it raises, the file is truncated back to what it held
before.

A rename is one live record naming the queue, its new name, and `next_id`, the number the
next created job would take, never one per job. It replays in order with the job records, so
it moves the jobs that are in the queue at its place in the log; a job numbered at or above
`next_id` was created after it and is never moved by it. The archive is not rewritten by a
rename: each archive `put` carries `renames`, how many renames the live log held when it was
written, and at open the renames after that count whose `next_id` is above the job's number
are applied to it. A rename the change-5 program wrote has no `next_id` and is bounded by the
count alone, which is how that program read it. A compaction folds every rename into the job
records it rewrites and carries the count on in its `counter` record, so the archive's counts
still line up with the log's.

A prune is one live record naming a cutoff and a count, never one per job: every archived
job whose `archived_ms` is at or before the cutoff, and whose archive `put` was written
before the prune, is gone from it on. Each archive `put` carries `prunes`, how many prunes
the live log held when it was written, the same way it carries `renames`, so a job archived
after a prune is never taken by it whatever the clock said. A compaction drops the pruned
jobs from the archive and carries the prunes count on as it carries the renames count.

Every record is checked against the job's rules as it replays (`jobs.job_problem`): a record
in a state the API can never produce refuses the folder rather than being served.

A log the previous version wrote replays too: its job records say `attempts` and
`max_attempts` and have no `backoff_ms`, and they are read in the current shape
(`upgrade_job_fields`). Every write, compaction included, uses only the current names.
"""

import errno
import fcntl
import json
import os
from collections.abc import Iterator, Sequence
from dataclasses import dataclass, field
from pathlib import Path
from typing import Annotated, Literal, Protocol

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    SerializerFunctionWrapHandler,
    TypeAdapter,
    ValidationError,
    field_validator,
    model_serializer,
)

from jobq.contract import ensure
from jobq.jobs import Job, QueueName, job_problem

LOG_NAME = "jobs.log"
LOCK_NAME = "jobq.lock"
COMPACT_NAME = "jobs.log.compact"
ARCHIVE_NAME = "jobq.archive"
ARCHIVE_COMPACT_NAME = "jobq.archive.compact"

# A job record's field names before the tries rename, and the names they have now.
LEGACY_NAMES = {"attempts": "tries", "max_attempts": "max_tries"}


class RenamesCounted(BaseModel):
    """A record carrying a `renames` and a `prunes` count, written last and each left out
    while it is 0, so a folder that was never renamed or pruned is written as before."""

    renames: int = Field(default=0, ge=0)
    prunes: int = Field(default=0, ge=0)

    @model_serializer(mode="wrap")
    def _without_zero_counts(self, handler: SerializerFunctionWrapHandler) -> object:
        fields = handler(self)
        if isinstance(fields, dict):
            for name in ("renames", "prunes"):
                count = fields.pop(name, 0)
                if count:
                    fields[name] = count  # last on the line
        return fields


def upgrade_job_fields(value: object) -> object:
    """A job record as any version wrote it, in the current shape: `attempts` and
    `max_attempts` read as `tries` and `max_tries`, and a missing `backoff_ms` as 0. A record
    holding an old name beside its new one keeps both, so validation refuses it."""
    if not isinstance(value, dict):
        return value
    fields = dict(value)
    for old, new in LEGACY_NAMES.items():
        if old in fields and new not in fields:
            fields[new] = fields.pop(old)
    fields.setdefault("backoff_ms", 0)
    return fields


class PutRecord(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid", frozen=True)

    kind: Literal["put"] = "put"
    job: Job

    @field_validator("job", mode="before")
    @classmethod
    def _upgrade(cls, value: object) -> object:
        return upgrade_job_fields(value)


class ArchivePutRecord(PutRecord, RenamesCounted):
    """An archive `put`: the job, and how many renames the live log held when it was written.
    An archive written before renames existed says none."""


class DeleteRecord(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid", frozen=True)

    kind: Literal["delete"] = "delete"
    number: int = Field(ge=1)


class CounterRecord(RenamesCounted):
    """Written first by compaction, so a job number never repeats after its record is gone,
    and the renames count carries on after the rename records are folded away."""

    model_config = ConfigDict(strict=True, extra="forbid", frozen=True)

    kind: Literal["counter"] = "counter"
    next_number: int = Field(ge=1)


class ArchivedRecord(BaseModel):
    """In the live log: the job left the board for the archive."""

    model_config = ConfigDict(strict=True, extra="forbid", frozen=True)

    kind: Literal["archived"] = "archived"
    number: int = Field(ge=1)


class RenameRecord(BaseModel):
    """In the live log: every job numbered below `next_id` that is in queue `name` here is in
    queue `to` from here on. A job created into `name` after it is in a fresh queue `name`.
    The change-5 program wrote no `next_id`; such a record is bounded by its place alone."""

    model_config = ConfigDict(strict=True, extra="forbid", frozen=True)

    kind: Literal["rename"] = "rename"
    name: QueueName
    to: QueueName
    next_id: int | None = Field(default=None, ge=1)

    @model_serializer(mode="wrap")
    def _without_missing_next_id(self, handler: SerializerFunctionWrapHandler) -> object:
        fields = handler(self)
        if isinstance(fields, dict) and fields.get("next_id") is None:
            fields.pop("next_id", None)
        return fields


class PruneRecord(BaseModel):
    """In the live log: every archived job whose `archived_ms` is at or before `cutoff_ms`,
    archived before this record, is gone; `count` of them were."""

    model_config = ConfigDict(strict=True, extra="forbid", frozen=True)

    kind: Literal["prune"] = "prune"
    cutoff_ms: int = Field(ge=0)
    count: int = Field(ge=1)


type LiveRecord = (
    PutRecord | DeleteRecord | CounterRecord | ArchivedRecord | RenameRecord | PruneRecord
)
type Appended = PutRecord | DeleteRecord | ArchivedRecord | RenameRecord | PruneRecord
type ArchiveRecord = ArchivePutRecord | DeleteRecord
type Record = Annotated[LiveRecord, Field(discriminator="kind")]
type ArchiveLine = Annotated[ArchiveRecord, Field(discriminator="kind")]
_RECORD: TypeAdapter[LiveRecord] = TypeAdapter(Record)
_ARCHIVE_RECORD: TypeAdapter[ArchiveRecord] = TypeAdapter(ArchiveLine)


class StoreError(Exception):
    """A write did not become durable. The log holds what it held before."""


class StoreOpenError(Exception):
    """`<dir>` cannot be opened, is served by another process, or its log is corrupt."""


class IllFormed(StoreOpenError):
    """A record in the log or the archive breaks a rule a job record must meet. `<dir>` is
    never served."""

    def __init__(self, key: str, rule: str, where: str = "record") -> None:
        super().__init__(f"{where} {key}: {rule}")
        self.key = key
        self.rule = rule


class FileOps(Protocol):
    """The two calls a write can fail in; the simulation injects failures here."""

    def write(self, fd: int, data: bytes) -> int: ...

    def fsync(self, fd: int) -> None: ...


class RealFileOps:
    def write(self, fd: int, data: bytes) -> int:
        return os.write(fd, data)

    def fsync(self, fd: int) -> None:
        os.fsync(fd)


@dataclass
class Replayed:
    """The state a log replays to: live jobs in number order, archived jobs in number order,
    and the next number to hand out. `records` counts the live log's lines and
    `archive_records` the archive's. `renames` counts every rename the log has held, and
    `renamed` holds the ones still in it, by their count, with their `next_id` (None for a
    change-5 record), for the archive to apply. `prunes` and `pruning` do the same for the
    prune records, each with its cutoff, its count, and its line; `pruned` holds how many
    archive `put`s each prune took at replay, and `gone` their numbers."""

    jobs: dict[int, Job]
    next_number: int
    records: int
    archived: dict[int, Job] = field(default_factory=dict)
    archive_records: int = 0
    renames: int = 0
    renamed: list[tuple[int, str, str, int | None]] = field(default_factory=list)
    prunes: int = 0
    pruning: list[tuple[int, int, int, int]] = field(default_factory=list)
    pruned: dict[int, int] = field(default_factory=dict)
    gone: set[int] = field(default_factory=set)


def rename_jobs(
    jobs: dict[int, Job], name: str, to: str, next_id: int | None = None
) -> dict[int, Job]:
    """`jobs` with every job in queue `name` numbered below `next_id` (every one, when it is
    None) moved to queue `to`, and nothing else changed."""
    return {
        number: job.model_copy(update={"queue": to})
        if job.queue == name and (next_id is None or number < next_id)
        else job
        for number, job in jobs.items()
    }


def renamed_queue(job: Job, since: int, renamed: Sequence[tuple[int, str, str, int | None]]) -> str:
    """The queue an archived `job`, written when the log held `since` renames, is in after
    the log's renames: each later rename whose `next_id` is above its number, in order."""
    queue = job.queue
    for count, name, to, next_id in renamed:
        if count > since and queue == name and (next_id is None or job.number < next_id):
            queue = to
    return queue


def apply_record(state: Replayed, record: LiveRecord) -> None:
    match record:
        case PutRecord(job=job):
            state.jobs[job.number] = job
            state.next_number = max(state.next_number, job.number + 1)
        case DeleteRecord(number=number) | ArchivedRecord(number=number):
            state.jobs.pop(number, None)
            state.next_number = max(state.next_number, number + 1)
        case CounterRecord(next_number=next_number, renames=renames, prunes=prunes):
            state.next_number = max(state.next_number, next_number)
            state.renames = max(state.renames, renames)
            state.prunes = max(state.prunes, prunes)
        case RenameRecord(name=name, to=to, next_id=next_id):
            state.jobs = rename_jobs(state.jobs, name, to, next_id)
            state.renames += 1
            state.renamed.append((state.renames, name, to, next_id))
        case PruneRecord(cutoff_ms=cutoff, count=count):
            state.prunes += 1
            state.pruning.append((state.prunes, cutoff, count, state.records + 1))
    state.records += 1


def pruned_by(job: Job, since: int, pruning: Sequence[tuple[int, int, int, int]]) -> int | None:
    """The count of the first prune after `since` whose cutoff takes the archived `job`, or
    None when no prune in the log takes it."""
    for count, cutoff, _, _ in pruning:
        if count > since and job.archived_ms is not None and job.archived_ms <= cutoff:
            return count
    return None


def apply_archive_record(state: Replayed, record: ArchiveRecord) -> None:
    """Apply one archive record, with every rename the log wrote after it to its job, and
    every prune the log wrote after it that takes the job."""
    match record:
        case ArchivePutRecord(job=job, renames=renames, prunes=prunes):
            queue = renamed_queue(job, renames, state.renamed)
            if queue != job.queue:
                job = job.model_copy(update={"queue": queue})
            state.next_number = max(state.next_number, job.number + 1)
            prune = pruned_by(job, prunes, state.pruning)
            if prune is None:
                state.archived[job.number] = job
            else:
                state.archived.pop(job.number, None)
                state.gone.add(job.number)
                state.pruned[prune] = state.pruned.get(prune, 0) + 1
        case DeleteRecord(number=number):
            state.archived.pop(number, None)
            state.next_number = max(state.next_number, number + 1)
    state.archive_records += 1


def resolve(state: Replayed) -> None:
    """The archive wins: a job in both files is archived and its live record is stale, and
    so is the live record of a job pruned from the archive. No prune took more jobs than its
    count says (a compaction cut short may leave it fewer). Then no key names two jobs in one
    queue, live or archived; IllFormed when one does."""
    for number in [*state.archived, *state.gone]:
        state.jobs.pop(number, None)
    for count, cutoff, said, line in state.pruning:
        took = state.pruned.get(count, 0)
        if took > said:
            rule = f"a prune at cutoff {cutoff} takes {took} archived jobs, above its count {said}"
            raise IllFormed(f"line {line}", rule)
    state.jobs = dict(sorted(state.jobs.items()))
    state.archived = dict(sorted(state.archived.items()))
    seen: dict[tuple[str, str], int] = {}
    for job in [*state.jobs.values(), *state.archived.values()]:
        if job.key is None:
            continue
        other = seen.setdefault((job.queue, job.key), job.number)
        if other != job.number:
            raise IllFormed(job.id, f"key {job.key!r} also names j_{other} in {job.queue}")


def key_map(state: Replayed) -> dict[tuple[str, str], int]:
    """Every used key, by (queue, key), from the live and the archived jobs."""
    return {
        (job.queue, job.key): job.number
        for job in [*state.jobs.values(), *state.archived.values()]
        if job.key is not None
    }


class LogFile:
    """One append-only file of JSON lines. A write is durable when `append_all` returns; when
    it raises, the file is truncated back to what it held before."""

    def __init__(self, fd: int, size: int, ops: FileOps) -> None:
        self._fd = fd
        self._size = size
        self._ops = ops
        self._dirty = False

    def append_all(self, records: Sequence[BaseModel]) -> None:
        """Write records with one fsync: all of them become durable, or none do.

        A file that cannot be written raises `StoreError` and nothing else: no failure is
        latched, so the first write after the file can be written again goes through.
        """
        data = b"".join(record.model_dump_json().encode() + b"\n" for record in records)
        start = self._size
        try:
            self._clean(start)
            self._write_all(data)
            self._ops.fsync(self._fd)
        except OSError as error:
            self._roll_back(start)
            raise StoreError(f"write failed: {error.strerror or error}") from error
        self._size = start + len(data)

    def _clean(self, size: int) -> None:
        """Cut off what a roll-back could not: a write only ever goes on a file of `size`."""
        if not self._dirty:
            return
        os.ftruncate(self._fd, size)
        os.fsync(self._fd)
        self._dirty = False

    def _write_all(self, data: bytes) -> None:
        written = 0
        while written < len(data):
            count = self._ops.write(self._fd, data[written:])
            if count <= 0:
                raise OSError(errno.EIO, "short write")
            written += count

    def _roll_back(self, size: int) -> None:
        """Back to `size`; a roll-back that fails is tried again before the next write."""
        try:
            os.ftruncate(self._fd, size)
            os.fsync(self._fd)
            self._dirty = False
        except OSError:
            self._dirty = True

    @property
    def size(self) -> int:
        return self._size


class Store:
    def __init__(
        self,
        dir_fd: int,
        lock_fd: int,
        log: tuple[int, int],
        archive: tuple[int, int],
        ops: FileOps,
    ) -> None:
        self._dir_fd = dir_fd
        self._lock_fd = lock_fd
        self._fds = (log[0], archive[0])
        self._log = LogFile(log[0], log[1], ops)
        self._archive = LogFile(archive[0], archive[1], ops)
        self._closed = False

    @classmethod
    def open(cls, directory: Path, ops: FileOps | None = None) -> tuple[Store, Replayed]:
        """Lock `<dir>`, replay its log and its archive, and cut a torn last line off each."""
        dir_fd, lock_fd = _open_and_lock(directory)
        opened: list[int] = [lock_fd, dir_fd]
        name = LOG_NAME
        try:
            flags = os.O_RDWR | os.O_CREAT | os.O_APPEND | os.O_CLOEXEC
            fd = os.open(LOG_NAME, flags, 0o600, dir_fd=dir_fd)
            opened.insert(0, fd)
            os.fsync(dir_fd)
            replayed, good_size = replay_fd(fd)
            name = ARCHIVE_NAME
            archive_fd = os.open(ARCHIVE_NAME, flags, 0o600, dir_fd=dir_fd)
            opened.insert(0, archive_fd)
            os.fsync(dir_fd)
            archive_size = replay_archive_fd(archive_fd, replayed)
            resolve(replayed)
            for each, size in ((fd, good_size), (archive_fd, archive_size)):
                if size != os.fstat(each).st_size:
                    os.ftruncate(each, size)
                    os.fsync(each)
        except (OSError, StoreOpenError) as error:
            for each in opened:
                os.close(each)
            if isinstance(error, IllFormed):
                raise StoreOpenError(f"{directory}: {error}") from error
            if isinstance(error, StoreOpenError):
                raise
            raise StoreOpenError(f"{directory}/{name}: {error.strerror}") from error
        store = cls(
            dir_fd, lock_fd, (fd, good_size), (archive_fd, archive_size), ops or RealFileOps()
        )
        return store, replayed

    def append(self, record: Appended) -> None:
        """Write one record and fsync it; on any failure, roll the log back and raise."""
        self.append_all([record])

    def append_all(self, records: Sequence[Appended]) -> None:
        """Write live records with one fsync: all of them become durable, or none do."""
        self._log.append_all(records)

    def append_archive(self, records: Sequence[ArchivePutRecord | DeleteRecord]) -> None:
        """Write archive records with one fsync: all of them become durable, or none do."""
        for record in records:
            if isinstance(record, ArchivePutRecord):
                ensure(archive_problem(record.job) is None, "only an archivable job is archived")
        self._archive.append_all(records)

    def close(self) -> None:
        """Close both files and give up the lock; a second close does nothing."""
        if self._closed:
            return
        self._closed = True
        for fd in (*self._fds, self._lock_fd, self._dir_fd):
            os.close(fd)

    @property
    def size(self) -> int:
        return self._log.size

    @property
    def archive_size(self) -> int:
        return self._archive.size

    @property
    def dir_fd(self) -> int:
        return self._dir_fd


def _open_and_lock(directory: Path) -> tuple[int, int]:
    try:
        dir_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    except OSError as error:
        raise StoreOpenError(f"{directory}: {error.strerror}") from error
    try:
        lock_fd = os.open(LOCK_NAME, os.O_RDWR | os.O_CREAT | os.O_CLOEXEC, 0o600, dir_fd=dir_fd)
    except OSError as error:
        os.close(dir_fd)
        raise StoreOpenError(f"{directory}/{LOCK_NAME}: {error.strerror}") from error
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError as error:
        os.close(lock_fd)
        os.close(dir_fd)
        raise StoreOpenError(f"{directory} is in use by another jobq") from error
    return dir_fd, lock_fd


def _lines(fd: int) -> Iterator[bytes]:
    with os.fdopen(os.dup(fd), "rb") as log:
        log.seek(0)
        yield from log


def record_key(line: bytes, line_number: int) -> str:
    """The key a record sits under: the job id its number names, or its line when it has none."""
    try:
        fields = json.loads(line)
    except ValueError:
        return f"line {line_number}"
    if isinstance(fields, dict):
        job = fields.get("job")
        number = job.get("number") if isinstance(job, dict) else fields.get("number")
        if isinstance(number, int) and not isinstance(number, bool) and number >= 1:
            return f"j_{number}"
    return f"line {line_number}"


def _first_problem(invalid: ValidationError) -> str:
    first = invalid.errors()[0]
    where = ".".join(str(part) for part in first["loc"] if part != "put")
    return f"{where} {first['msg'].lower()}" if where else str(first["msg"]).lower()


def live_problem(job: Job) -> str | None:
    """The rule a job in the live log breaks, or None."""
    problem = job_problem(job)
    if problem is None and job.archived_ms is not None:
        return "a live job has no archived_at"
    return problem


def archive_problem(job: Job) -> str | None:
    """The rule a job in the archive breaks, or None: only done and dead jobs, each with an
    `archived_at`."""
    problem = job_problem(job)
    if problem is None and job.state not in {"done", "dead"}:
        return f"an archived job is done or dead, not {job.state}"
    if problem is None and job.archived_ms is None:
        return "an archived job has an archived_at"
    return problem


def replay_fd(fd: int) -> tuple[Replayed, int]:
    """The live log's replayed state (before the archive is applied) and the size of the log
    up to its last whole line.

    IllFormed for the first record that breaks a rule: the folder is refused, not served.
    """
    state = Replayed(jobs={}, next_number=1, records=0)
    good_size = 0
    for line_number, line in enumerate(_lines(fd), start=1):
        if not line.endswith(b"\n"):
            break  # a torn last write: never answered, so never acknowledged
        try:
            record = _RECORD.validate_json(line)
        except ValidationError as error:
            raise IllFormed(record_key(line, line_number), _first_problem(error)) from error
        if isinstance(record, PutRecord):
            problem = live_problem(record.job)
            if problem is not None:
                raise IllFormed(record.job.id, problem)
        if isinstance(record, RenameRecord) and record.name == record.to:
            raise IllFormed(f"line {line_number}", f"a rename of {record.name} to itself")
        if isinstance(record, RenameRecord) and (record.next_id or 0) > state.next_number:
            rule = f"a rename's next_id {record.next_id} is past the counter {state.next_number}"
            raise IllFormed(f"line {line_number}", rule)
        apply_record(state, record)
        good_size += len(line)
    state.jobs = dict(sorted(state.jobs.items()))
    return state, good_size


def replay_archive_fd(fd: int, state: Replayed) -> int:
    """Apply the archive to `state`; the size of the archive up to its last whole line."""
    good_size = 0
    for line_number, line in enumerate(_lines(fd), start=1):
        if not line.endswith(b"\n"):
            break  # a torn last write, cut like the log's
        try:
            record = _ARCHIVE_RECORD.validate_json(line)
        except ValidationError as error:
            key = record_key(line, line_number)
            raise IllFormed(key, _first_problem(error), "archive record") from error
        if isinstance(record, ArchivePutRecord):
            problem = archive_problem(record.job)
            if problem is None and record.renames > state.renames:
                problem = f"renames {record.renames} is past the log's {state.renames}"
            if problem is None and record.prunes > state.prunes:
                problem = f"prunes {record.prunes} is past the log's {state.prunes}"
            if problem is not None:
                raise IllFormed(record.job.id, problem, "archive record")
        apply_archive_record(state, record)
        good_size += len(line)
    return good_size


def replay(directory: Path) -> Replayed:
    """Replay the log and the archive without taking the lock, for checks while a queue
    holds it."""
    fd = os.open(directory / LOG_NAME, os.O_RDONLY | os.O_CLOEXEC)
    try:
        state = replay_fd(fd)[0]
    finally:
        os.close(fd)
    try:
        archive_fd = os.open(directory / ARCHIVE_NAME, os.O_RDONLY | os.O_CLOEXEC)
    except FileNotFoundError:
        archive_fd = -1
    if archive_fd >= 0:
        try:
            replay_archive_fd(archive_fd, state)
        finally:
            os.close(archive_fd)
    resolve(state)
    return state


def _write_file(dir_fd: int, name: str, final: str, lines: Sequence[BaseModel]) -> None:
    """`lines` into `name`, fsynced, then renamed over `final`."""
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_CLOEXEC
    fd = os.open(name, flags, 0o600, dir_fd=dir_fd)
    try:
        data = b"".join(line.model_dump_json().encode() + b"\n" for line in lines)
        view = memoryview(data)
        while view:
            view = view[os.write(fd, view) :]
        os.fsync(fd)
    finally:
        os.close(fd)
    os.rename(name, final, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
    os.fsync(dir_fd)


def compact(directory: Path) -> tuple[int, int]:
    """Rewrite the log to a counter line and one line per live job, and the archive to one
    line per archived job that is neither deleted nor pruned; (live records before, after).
    Every job is written under its current queue, so no rename or prune record is left; the
    counter line and each archive line carry the renames and prunes counts on.

    The archive is rewritten first: a kill between the two renames leaves a live log whose
    stale lines the archive still overrides, and deletes the live log still records."""
    store, state = Store.open(directory)
    try:
        archived = [
            ArchivePutRecord(job=job, renames=state.renames, prunes=state.prunes)
            for job in state.archived.values()
        ]
        _write_file(store.dir_fd, ARCHIVE_COMPACT_NAME, ARCHIVE_NAME, archived)
        live: list[BaseModel] = [
            CounterRecord(next_number=state.next_number, renames=state.renames, prunes=state.prunes)
        ]
        live += [PutRecord(job=job) for job in state.jobs.values()]
        _write_file(store.dir_fd, COMPACT_NAME, LOG_NAME, live)
    except OSError as error:
        raise StoreOpenError(f"compacting {directory}: {error.strerror}") from error
    finally:
        store.close()
    after = replay(directory)
    ensure(
        all(live_problem(job) is None for job in after.jobs.values()),
        "compaction writes only well-formed records",
    )
    ensure(
        all(archive_problem(job) is None for job in after.archived.values()),
        "compaction writes only well-formed archive records",
    )
    ensure(after.jobs == state.jobs, "compaction keeps every live job as it was")
    ensure(after.archived == state.archived, "compaction keeps every archived job as it was")
    ensure(after.next_number == state.next_number, "compaction keeps the counter")
    ensure(after.renames == state.renames and not after.renamed, "compaction folds renames")
    ensure(after.prunes == state.prunes and not after.pruning, "compaction folds prunes")
    ensure(not after.gone, "compaction drops the pruned jobs")
    ensure(after.records == len(state.jobs) + 1, "one line per live job and the counter")
    ensure(after.archive_records == len(state.archived), "one line per archived job")
    return state.records, after.records
