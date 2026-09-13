"""Finding `*.log` files directly inside a directory and reading them line by line, never outside it."""

import os
import stat
from collections.abc import Iterator
from pathlib import Path


class OutsideDirectory(ValueError):
    """A path that is not a regular file directly inside the root directory."""


def resolve_directory(directory: str) -> Path:
    """Resolve the directory once; raise NotADirectoryError or OSError if it is not one."""
    root = Path(directory).resolve(strict=True)
    if not root.is_dir():
        raise NotADirectoryError(f"{directory} is not a directory")
    return root


def list_log_files(root: Path) -> list[Path]:
    """Every regular, non-symlink `*.log` file directly inside root, in name order."""
    with os.scandir(root) as entries:
        names = [e.name for e in entries if e.name.endswith(".log") and e.is_file(follow_symlinks=False)]
    return [root / name for name in sorted(names)]


def check_inside(root: Path, path: Path) -> None:
    if path.parent != root or path.name in ("", ".", "..") or os.sep in path.name:
        raise OutsideDirectory(f"{path} is not directly inside {root}")
    if path.resolve(strict=True).parent != root:
        raise OutsideDirectory(f"{path} resolves outside {root}")


def read_lines(root: Path, path: Path) -> Iterator[bytes]:
    """Yield raw lines of one file, streamed; refuses symlinks, non-regular files and anything outside root."""
    check_inside(root, path)
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with open(descriptor, "rb") as handle:
        if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
            raise OutsideDirectory(f"{path} is not a regular file")
        yield from handle
