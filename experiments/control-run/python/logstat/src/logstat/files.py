"""The `*.log` files directly inside one directory, read one at a time, never outside it."""

import os
import stat
from collections.abc import Iterator
from pathlib import Path

from logstat.contract import require


class DirectoryError(Exception):
    """The directory could not be listed."""


def log_names(directory: Path) -> list[str]:
    """Regular, non-symlink `*.log` files directly inside `directory`, in name order."""
    try:
        with os.scandir(directory) as entries:
            names = [
                entry.name
                for entry in entries
                if _is_log_name(entry.name)
                and not entry.is_symlink()
                and entry.is_file(follow_symlinks=False)
            ]
    except OSError as err:
        raise DirectoryError(f"cannot read directory {directory}: {err.strerror}") from err
    return sorted(names)


def read_lines(directory: Path, name: str) -> Iterator[str | None]:
    """Each line without its `\\n` or `\\r\\n`; None for a line that is not UTF-8."""
    require(os.sep not in name and name not in (".", ".."), "name is a plain file name")
    dir_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=dir_fd)
    finally:
        os.close(dir_fd)
    with os.fdopen(fd, "rb") as handle:
        if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
            raise OSError(0, "not a regular file")
        for raw in handle:
            yield decode_line(raw)


def decode_line(raw: bytes) -> str | None:
    line = raw.removesuffix(b"\n").removesuffix(b"\r")
    try:
        return line.decode("utf-8")
    except UnicodeDecodeError:
        return None


def _is_log_name(name: str) -> bool:
    return name.endswith(".log") and not name.startswith(".")
