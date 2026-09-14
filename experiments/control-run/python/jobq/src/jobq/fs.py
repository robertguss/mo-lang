"""The filesystem the store writes through: the real one, and a simulated one that fails on purpose."""

import errno
import os
import random
from collections.abc import Iterable, Iterator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Protocol

_WRITE_CHUNK = 1 << 20


class LogFile(Protocol):
    def append(self, data: bytes) -> None: ...

    def sync(self) -> None: ...

    def truncate(self, size: int) -> None: ...

    def close(self) -> None: ...


class Fs(Protocol):
    def open_log(self, path: Path) -> LogFile: ...

    def read_lines(self, path: Path) -> Iterator[bytes]: ...

    def replace(self, path: Path, lines: Iterable[bytes]) -> None: ...


class OsLogFile:
    def __init__(self, fd: int) -> None:
        self._fd = fd

    def append(self, data: bytes) -> None:
        view = memoryview(data)
        while view:
            view = view[os.write(self._fd, view) :]

    def sync(self) -> None:
        os.fsync(self._fd)

    def truncate(self, size: int) -> None:
        os.ftruncate(self._fd, size)

    def close(self) -> None:
        os.close(self._fd)


class OsFs:
    def open_log(self, path: Path) -> LogFile:
        existed = path.exists()
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_CLOEXEC, 0o644)
        if not existed:
            _sync_directory(path.parent)
        return OsLogFile(fd)

    def read_lines(self, path: Path) -> Iterator[bytes]:
        try:
            handle = path.open("rb")
        except FileNotFoundError:
            return
        with handle:
            yield from handle

    def replace(self, path: Path, lines: Iterable[bytes]) -> None:
        temporary = path.with_name(path.name + ".compact")
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_CLOEXEC, 0o644)
        file = OsLogFile(fd)
        try:
            buffer = bytearray()
            for line in lines:
                buffer += line
                if len(buffer) >= _WRITE_CHUNK:
                    file.append(bytes(buffer))
                    buffer.clear()
            file.append(bytes(buffer))
            file.sync()
        finally:
            file.close()
        os.replace(temporary, path)
        _sync_directory(path.parent)


def _sync_directory(directory: Path) -> None:
    fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


@dataclass
class Faults:
    """Each write-side call fails with probability `rate`, drawn from a seeded generator."""

    rng: random.Random
    rate: float = 0.0
    injected: int = 0

    def hit(self) -> bool:
        if self.rate > 0.0 and self.rng.random() < self.rate:
            self.injected += 1
            return True
        return False


@dataclass
class MemoryFile:
    content: bytearray = field(default_factory=bytearray)
    durable: bytes = b""


class MemoryLogFile:
    def __init__(self, fs: MemoryFs, path: Path) -> None:
        self._fs = fs
        self._path = path

    def append(self, data: bytes) -> None:
        file = self._fs.files[self._path]
        if self._fs.faults.hit():
            file.content += data[: self._fs.faults.rng.randint(0, len(data))]
            raise OSError(errno.EIO, "injected write failure")
        file.content += data

    def sync(self) -> None:
        file = self._fs.files[self._path]
        if self._fs.faults.hit():
            if self._fs.faults.rng.random() < 0.5:
                file.durable = bytes(file.content)
            raise OSError(errno.EIO, "injected fsync failure")
        file.durable = bytes(file.content)

    def truncate(self, size: int) -> None:
        if self._fs.faults.hit():
            raise OSError(errno.EIO, "injected truncate failure")
        del self._fs.files[self._path].content[size:]

    def close(self) -> None:
        pass


class MemoryFs:
    """Files whose unsynced bytes a `crash` throws away. Reads never fail."""

    def __init__(self, faults: Faults | None = None) -> None:
        self.files: dict[Path, MemoryFile] = {}
        self.faults = faults or Faults(random.Random(0))

    def open_log(self, path: Path) -> LogFile:
        if self.faults.hit():
            raise OSError(errno.EIO, "injected open failure")
        self.files.setdefault(path, MemoryFile())
        return MemoryLogFile(self, path)

    def read_lines(self, path: Path) -> Iterator[bytes]:
        file = self.files.get(path)
        if file is None:
            return
        data = bytes(file.content)
        start = 0
        while start < len(data):
            end = data.find(b"\n", start)
            stop = len(data) if end < 0 else end + 1
            yield data[start:stop]
            start = stop

    def replace(self, path: Path, lines: Iterable[bytes]) -> None:
        data = b"".join(lines)
        if self.faults.hit():
            raise OSError(errno.EIO, "injected replace failure")
        self.files[path] = MemoryFile(bytearray(data), data)

    def crash(self) -> None:
        for file in self.files.values():
            file.content = bytearray(file.durable)
