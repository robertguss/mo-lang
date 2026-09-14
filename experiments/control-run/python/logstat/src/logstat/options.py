"""Command-line usage: `logstat <dir> [--top N] [--since <ISO-8601>] [--json]`."""

import re
from collections.abc import Sequence
from datetime import datetime

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, ValidationError

USAGE = "usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"

_DIGITS = re.compile(r"[0-9]+")


class UsageError(Exception):
    """A usage error: printed to stderr as one line, exit code 2."""

    def __init__(self, problem: str) -> None:
        super().__init__(f"logstat: {problem} ({USAGE})")


class Options(BaseModel):
    model_config = ConfigDict(frozen=True, strict=True, extra="forbid")

    directory: str = Field(min_length=1)
    top: int = Field(default=5, ge=1, le=100)
    since: AwareDatetime | None = None
    json_output: bool = False


def parse_args(argv: Sequence[str]) -> Options:
    """Options from the arguments after the program name, or a UsageError."""
    directories: list[str] = []
    top = 5
    since: datetime | None = None
    json_output = False
    seen: set[str] = set()
    args = iter(argv)
    for arg in args:
        if not arg.startswith("--"):
            directories.append(arg)
            continue
        if arg in seen:
            raise UsageError(f"{arg} given twice")
        seen.add(arg)
        if arg == "--json":
            json_output = True
        elif arg == "--top":
            top = parse_top(next(args, None))
        elif arg == "--since":
            since = parse_since(next(args, None))
        else:
            raise UsageError(f"unknown option {arg}")
    if len(directories) != 1:
        raise UsageError(f"expected one <dir>, found {len(directories)}")
    try:
        return Options(directory=directories[0], top=top, since=since, json_output=json_output)
    except ValidationError as error:
        raise UsageError(str(error.errors()[0]["msg"])) from error


def parse_top(text: str | None) -> int:
    """`--top N`: 1 to 100. Outside that range is a usage error, not a clamp."""
    if text is None or _DIGITS.fullmatch(text) is None:
        raise UsageError("--top needs a whole number from 1 to 100")
    top = int(text)
    if not 1 <= top <= 100:
        raise UsageError(f"--top must be 1 to 100, got {top}")
    return top


def parse_since(text: str | None) -> datetime:
    """`--since T`: an ISO-8601 timestamp with a UTC offset."""
    if text is None:
        raise UsageError("--since needs an ISO-8601 timestamp")
    try:
        since = datetime.fromisoformat(text)
    except ValueError as error:
        raise UsageError(f"--since {text!r} is not ISO-8601") from error
    if since.tzinfo is None or since.utcoffset() is None:
        raise UsageError("--since needs a UTC offset, such as Z or +02:00")
    return since
