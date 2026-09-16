"""The store: an append-only log of JSON lines in `<dir>/jobs.log` that replays.

One record per job change, under the job's number. A write is durable when `append`
returns; when it raises, the log is truncated back to what it held before.

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
from dataclasses import dataclass
from pathlib import Path
from typing import Annotated, Literal, Protocol

from pydantic import BaseModel, ConfigDict, Field, TypeAdapter, ValidationError, field_validator

from jobq.contract import ensure
from jobq.jobs import Job, job_problem

LOG_NAME = "jobs.log"
LOCK_NAME = "jobq.lock"
COMPACT_NAME = "jobs.log.compact"

# A job record's field names before the tries rename, and the names they have now.
LEGACY_NAMES = {"attempts": "tries", "max_attempts": "max_tries"}


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


class DeleteRecord(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid", frozen=True)

    kind: Literal["delete"] = "delete"
    number: int = Field(ge=1)


class CounterRecord(BaseModel):
    """Written first by compaction, so a job number never repeats after its record is gone."""

    model_config = ConfigDict(strict=True, extra="forbid", frozen=True)

    kind: Literal["counter"] = "counter"
    next_number: int = Field(ge=1)


type Record = Annotated[PutRecord | DeleteRecord | CounterRecord, Field(discriminator="kind")]
_RECORD: TypeAdapter[PutRecord | DeleteRecord | CounterRecord] = TypeAdapter(Record)


class StoreError(Exception):
    """A write did not become durable. The log holds what it held before."""


class StoreOpenError(Exception):
    """`<dir>` cannot be opened, is served by another process, or its log is corrupt."""


class IllFormed(StoreOpenError):
    """A record in the log breaks a rule a job record must meet. `<dir>` is never served."""

    def __init__(self, key: str, rule: str) -> None:
        super().__init__(f"record {key}: {rule}")
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
    """The state a log replays to: jobs in number order and the next number to hand out."""

    jobs: dict[int, Job]
    next_number: int
    records: int


def apply_record(state: Replayed, record: PutRecord | DeleteRecord | CounterRecord) -> None:
    match record:
        case PutRecord(job=job):
            state.jobs[job.number] = job
            state.next_number = max(state.next_number, job.number + 1)
        case DeleteRecord(number=number):
            state.jobs.pop(number, None)
            state.next_number = max(state.next_number, number + 1)
        case CounterRecord(next_number=next_number):
            state.next_number = max(state.next_number, next_number)
    state.records += 1


class Store:
    def __init__(self, dir_fd: int, lock_fd: int, fd: int, size: int, ops: FileOps) -> None:
        self._dir_fd = dir_fd
        self._lock_fd = lock_fd
        self._fd = fd
        self._size = size
        self._ops = ops
        self._dirty = False

    @classmethod
    def open(cls, directory: Path, ops: FileOps | None = None) -> tuple[Store, Replayed]:
        """Lock `<dir>`, replay its log, and cut a torn last line off."""
        dir_fd, lock_fd = _open_and_lock(directory)
        opened: list[int] = [lock_fd, dir_fd]
        try:
            flags = os.O_RDWR | os.O_CREAT | os.O_APPEND | os.O_CLOEXEC
            fd = os.open(LOG_NAME, flags, 0o600, dir_fd=dir_fd)
            opened.insert(0, fd)
            os.fsync(dir_fd)
            replayed, good_size = replay_fd(fd)
            if good_size != os.fstat(fd).st_size:
                os.ftruncate(fd, good_size)
                os.fsync(fd)
        except (OSError, StoreOpenError) as error:
            for each in opened:
                os.close(each)
            if isinstance(error, IllFormed):
                raise StoreOpenError(f"{directory}: {error}") from error
            if isinstance(error, StoreOpenError):
                raise
            raise StoreOpenError(f"{directory}/{LOG_NAME}: {error.strerror}") from error
        return cls(dir_fd, lock_fd, fd, good_size, ops or RealFileOps()), replayed

    def append(self, record: PutRecord | DeleteRecord) -> None:
        """Write one record and fsync it; on any failure, roll the log back and raise."""
        self.append_all([record])

    def append_all(self, records: Sequence[PutRecord | DeleteRecord]) -> None:
        """Write records with one fsync: all of them become durable, or none do.

        A store that cannot be written raises `StoreError` and nothing else: no failure is
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
        """Cut off what a roll-back could not: a write only ever goes on a log of `size`."""
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

    def close(self) -> None:
        for fd in (self._fd, self._lock_fd, self._dir_fd):
            os.close(fd)

    @property
    def size(self) -> int:
        return self._size

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


def replay_fd(fd: int) -> tuple[Replayed, int]:
    """The replayed state and the size of the log up to its last whole line.

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
            problem = job_problem(record.job)
            if problem is not None:
                raise IllFormed(record.job.id, problem)
        apply_record(state, record)
        good_size += len(line)
    state.jobs = dict(sorted(state.jobs.items()))
    return state, good_size


def replay(directory: Path) -> Replayed:
    """Replay a log without taking the lock, for checks while a queue holds it."""
    fd = os.open(directory / LOG_NAME, os.O_RDONLY | os.O_CLOEXEC)
    try:
        return replay_fd(fd)[0]
    finally:
        os.close(fd)


def compact(directory: Path) -> tuple[int, int]:
    """Rewrite the log to a counter line and one line per live job; (records before, after)."""
    store, state = Store.open(directory)
    try:
        flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_CLOEXEC
        fd = os.open(COMPACT_NAME, flags, 0o600, dir_fd=store.dir_fd)
        try:
            lines = [CounterRecord(next_number=state.next_number).model_dump_json()]
            lines += [PutRecord(job=job).model_dump_json() for job in state.jobs.values()]
            data = ("\n".join(lines) + "\n").encode()
            view = memoryview(data)
            while view:
                view = view[os.write(fd, view) :]
            os.fsync(fd)
        finally:
            os.close(fd)
        os.rename(COMPACT_NAME, LOG_NAME, src_dir_fd=store.dir_fd, dst_dir_fd=store.dir_fd)
        os.fsync(store.dir_fd)
    except OSError as error:
        raise StoreOpenError(f"compacting {directory}: {error.strerror}") from error
    finally:
        store.close()
    after = replay(directory)
    ensure(
        all(job_problem(job) is None for job in after.jobs.values()),
        "compaction writes only well-formed records",
    )
    ensure(after.jobs == state.jobs, "compaction keeps every live job as it was")
    ensure(after.next_number == state.next_number, "compaction keeps the counter")
    ensure(after.records == len(state.jobs) + 1, "one line per live job and the counter")
    return state.records, after.records
