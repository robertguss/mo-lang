"""Finding the .log files directly inside a directory and reading them without leaving it."""

from __future__ import annotations

import os
import stat
from collections.abc import Iterator
from pathlib import Path

from records import ContractError


def list_logs(directory: Path) -> list[Path]:
    """Every regular, non-hidden *.log file directly inside directory, in name order."""
    with os.scandir(directory) as entries:
        names = sorted(entry.name for entry in entries if is_log(entry))
    return [require_inside(directory, directory / name) for name in names]


def is_log(entry: os.DirEntry[str]) -> bool:
    name = entry.name
    return name.endswith(".log") and not name.startswith(".") and entry.is_file(follow_symlinks=False)


def require_inside(directory: Path, path: Path) -> Path:
    if path.is_symlink() or path.resolve().parent != directory.resolve():
        raise ContractError(f"{path} is not directly inside {directory}")
    return path


def read_lines(directory: Path, path: Path) -> Iterator[bytes]:
    """Lines of one file, streamed; refuses a file swapped for a symlink or non-file."""
    require_inside(directory, path)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as handle:
        if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
            raise ContractError(f"{path} is not a regular file")
        yield from handle
