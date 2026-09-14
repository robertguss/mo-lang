"""Reading `<dir>`: every regular `*.log` file directly inside it, in name order, read-only.

The directory is opened once; every file is opened relative to that descriptor by a plain
name with O_NOFOLLOW, so no symlink, `..`, or rename of `<dir>` can lead outside it.
"""

import os
import stat
from collections.abc import Iterator

from logstat.contract import require
from logstat.options import UsageError


class LogReadError(Exception):
    """A `.log` file inside `<dir>` could not be read."""

    def __init__(self, name: str, reason: str) -> None:
        super().__init__(f"cannot read {name}: {reason}")


def open_directory(path: str) -> int:
    """A read-only descriptor for `<dir>`; not a directory is a usage error."""
    try:
        return os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    except OSError as error:
        raise UsageError(f"<dir> {path!r}: {error.strerror}") from error


def is_plain_name(name: str) -> bool:
    return name not in {"", ".", ".."} and "/" not in name and "\0" not in name


def list_log_names(dir_fd: int) -> list[str]:
    """Names of the regular, non-hidden `*.log` files directly inside the directory."""
    names = []
    for name in os.listdir(dir_fd):
        if name.startswith(".") or not name.endswith(".log"):
            continue
        try:
            info = os.stat(name, dir_fd=dir_fd, follow_symlinks=False)
        except FileNotFoundError:
            continue
        except OSError as error:
            raise LogReadError(name, error.strerror or "stat failed") from error
        if stat.S_ISREG(info.st_mode):
            names.append(name)
    return sorted(names)


def read_lines(dir_fd: int, name: str) -> Iterator[bytes]:
    """The raw lines of one file, streamed so only one file is open at a time."""
    require(is_plain_name(name), "the name is a plain name inside <dir>")
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC
    try:
        fd = os.open(name, flags, dir_fd=dir_fd)
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            os.close(fd)
            raise LogReadError(name, "not a regular file")
        with open(fd, "rb") as lines:
            yield from lines
    except OSError as error:
        raise LogReadError(name, error.strerror or "read failed") from error
