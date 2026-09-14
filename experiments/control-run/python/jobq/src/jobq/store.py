"""The append-only log: one line per change, `<crc32 hex> <json>\\n`, replayed in order on start."""

import itertools
import zlib
from collections.abc import Callable, Iterable, Sequence
from contextlib import suppress
from pathlib import Path
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, TypeAdapter, ValidationError

from jobq.contract import ContractError
from jobq.fs import Fs, LogFile
from jobq.model import Job, JobId

LOG_NAME = "jobs.log"


class _Record(BaseModel):
    model_config = ConfigDict(frozen=True, strict=True, extra="forbid")


class PutRecord(_Record):
    kind: Literal["put"] = "put"
    job: Job


class DeleteRecord(_Record):
    kind: Literal["delete"] = "delete"
    id: JobId


class CounterRecord(_Record):
    kind: Literal["counter"] = "counter"
    next_id: Annotated[int, Field(ge=1)]


type Record = PutRecord | DeleteRecord | CounterRecord
_RECORD: TypeAdapter[Record] = TypeAdapter(
    Annotated[PutRecord | DeleteRecord | CounterRecord, Field(discriminator="kind")]
)


class StoreUnavailable(Exception):
    """A write could not be made durable. Nothing it carried was applied."""


class StoreCorrupt(Exception):
    """The log has a damaged line that is not the torn last one, or a record breaks the rules."""


def encode(record: Record) -> bytes:
    body = record.model_dump_json(exclude_none=True).encode()
    return b"%08x %s\n" % (zlib.crc32(body), body)


def decode(line: bytes) -> Record | None:
    """The record on a whole, undamaged line; None if the line is torn or damaged."""
    if len(line) < 11 or not line.endswith(b"\n") or line[8:9] != b" ":
        return None
    body = line[9:-1]
    try:
        checksum = int(line[:8], 16)
    except ValueError:
        return None
    if zlib.crc32(body) != checksum:
        return None
    try:
        return _RECORD.validate_json(body)
    except ValidationError as err:
        raise StoreCorrupt(f"a record fails its schema: {err.errors()[0]['msg']}") from err


class Store:
    def __init__(self, fs: Fs, directory: Path) -> None:
        self._fs = fs
        self.path = directory / LOG_NAME
        self._file: LogFile | None = None
        self._good_size = 0
        self._dirty = False
        self.written = 0
        self.synced = 0

    @property
    def clean(self) -> bool:
        """No bytes past the last durable record are in the file."""
        return not self._dirty

    def open(self, apply: Callable[[Record], None]) -> int:
        """Replay every record into `apply`, cut a torn last line, open for appends; the count."""
        if self._file is not None:
            raise ContractError("requires the store is not open yet")
        size = 0
        count = 0
        torn = False
        for line in self._fs.read_lines(self.path):
            if torn:
                raise StoreCorrupt(f"{self.path}: damaged line {count + 1} is not the last line")
            record = decode(line)
            if record is None:
                torn = True
                continue
            try:
                apply(record)
            except ContractError as err:
                raise StoreCorrupt(f"{self.path}: record {count + 1}: {err}") from err
            size += len(line)
            count += 1
        self._good_size = size
        self._file = self._fs.open_log(self.path)
        if torn:
            self._dirty = True
            self._repair()
        return count

    def append(self, records: Sequence[Record]) -> None:
        """All of `records` durable, or StoreUnavailable and the log as it was."""
        data = b"".join(map(encode, records))
        try:
            if self._dirty:
                self._repair()
            file = self._opened()
            self._dirty = True
            self.written += len(records)
            file.append(data)
            file.sync()
        except OSError as err:
            self.written = self.synced
            with suppress(OSError):
                self._repair()
            raise StoreUnavailable(f"{self.path}: {err.strerror or err}") from err
        self._dirty = False
        self._good_size += len(data)
        self.synced = self.written

    def compact(self, records: Iterable[Record]) -> None:
        """Replace the log with `records`, atomically. The store is closed afterwards."""
        self.close()
        self._fs.replace(self.path, map(encode, itertools.chain(records)))

    def close(self) -> None:
        if self._file is not None:
            self._file.close()
            self._file = None

    def _repair(self) -> None:
        file = self._opened()
        file.truncate(self._good_size)
        file.sync()
        self._dirty = False

    def _opened(self) -> LogFile:
        if self._file is None:
            raise ContractError("requires the store is open")
        return self._file
