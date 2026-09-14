"""`logstat <dir> [--top N] [--since <ISO-8601>] [--json]`."""

import sys
from collections.abc import Sequence
from pathlib import Path
from typing import Annotated, TextIO

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, ValidationError

from logstat.files import DirectoryError, log_names, read_lines
from logstat.record import LogRecord, parse_line, parse_timestamp
from logstat.render import render_json, render_text
from logstat.summary import MAX_TOP, MIN_TOP, Tally

USAGE = "usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"
EXIT_OK = 0
EXIT_NO_LOGS = 1
EXIT_USAGE = 2


class UsageError(Exception):
    pass


class Options(BaseModel):
    model_config = ConfigDict(frozen=True, strict=True)

    directory: Path
    top: Annotated[int, Field(ge=MIN_TOP, le=MAX_TOP)] = 5
    since: AwareDatetime | None = None
    as_json: bool = False


def parse_args(argv: Sequence[str]) -> Options:
    positional: list[str] = []
    values: dict[str, str] = {}
    as_json = False
    rest = list(argv)
    while rest:
        arg = rest.pop(0)
        if arg in ("--top", "--since"):
            if not rest:
                raise UsageError(f"{arg} needs a value")
            if arg in values:
                raise UsageError(f"{arg} given twice")
            values[arg] = rest.pop(0)
        elif arg == "--json":
            if as_json:
                raise UsageError("--json given twice")
            as_json = True
        elif arg.startswith("-"):
            raise UsageError(f"unknown option {arg}")
        else:
            positional.append(arg)
    if len(positional) != 1:
        raise UsageError(f"expected one <dir>, got {len(positional)}")
    return _options(positional[0], values.get("--top"), values.get("--since"), as_json)


def _options(directory: str, top: str | None, since: str | None, as_json: bool) -> Options:
    if top is not None and not (top.isascii() and top.isdigit() and len(top) <= 3):
        raise UsageError(f"--top must be a whole number {MIN_TOP} to {MAX_TOP}")
    since_at = None if since is None else parse_timestamp(since)
    if since is not None and since_at is None:
        raise UsageError("--since must be an ISO-8601 timestamp with a zone")
    try:
        return Options(
            directory=Path(directory),
            top=5 if top is None else int(top),
            since=since_at,
            as_json=as_json,
        )
    except ValidationError as err:
        raise UsageError(f"--top must be {MIN_TOP} to {MAX_TOP}, not {top}") from err


def run(argv: Sequence[str], out: TextIO, err: TextIO) -> int:
    try:
        options = parse_args(argv)
    except UsageError as problem:
        print(f"logstat: {problem}; {USAGE}", file=err)
        return EXIT_USAGE
    try:
        names = log_names(options.directory)
    except DirectoryError as problem:
        print(f"logstat: {problem}", file=err)
        return EXIT_NO_LOGS
    if not names:
        print(f"logstat: no .log file in {options.directory}", file=err)
        return EXIT_NO_LOGS
    tally = Tally(options.top, options.since)
    for name in names:
        _read_file(tally, options.directory, name, err)
    summary = tally.summary()
    out.write(render_json(summary) if options.as_json else render_text(summary))
    return EXIT_OK


def _read_file(tally: Tally, directory: Path, name: str, err: TextIO) -> None:
    try:
        for line in read_lines(directory, name):
            record = None if line is None else parse_line(line)
            if isinstance(record, LogRecord):
                tally.add(record)
            else:
                tally.add_malformed()
    except OSError as problem:
        print(f"logstat: cannot read {name}: {problem.strerror}", file=err)


def main() -> None:
    raise SystemExit(run(sys.argv[1:], sys.stdout, sys.stderr))
