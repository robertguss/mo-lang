"""The entry point: exit 0 on success, 2 on a usage error, 1 if no `.log` file was found."""

import os
import sys
from collections.abc import Iterator, Sequence
from typing import TextIO

from logstat.contract import ensure
from logstat.files import LogReadError, list_log_names, open_directory, read_lines
from logstat.mask import find_card_number, mask_card_numbers
from logstat.options import UsageError, parse_args
from logstat.render import render_json, render_text
from logstat.summary import analyze

EXIT_OK = 0
EXIT_NO_LOGS = 1
EXIT_USAGE = 2


def run(argv: Sequence[str], stdout: TextIO, stderr: TextIO) -> int:
    try:
        options = parse_args(argv)
        dir_fd = open_directory(options.directory)
    except UsageError as error:
        print(mask_card_numbers(str(error)), file=stderr)
        return EXIT_USAGE
    try:
        names = list_log_names(dir_fd)
        if not names:
            print(f"logstat: no .log file in {options.directory!r}", file=stderr)
            return EXIT_NO_LOGS
        summary = analyze(_all_lines(dir_fd, names), options.top, options.since)
    except LogReadError as error:
        print(mask_card_numbers(f"logstat: {error}"), file=stderr)
        return EXIT_NO_LOGS
    finally:
        os.close(dir_fd)
    report = render_json(summary) if options.json_output else render_text(summary)
    ensure(find_card_number(report) is None, "no card number reaches stdout")
    stdout.write(report)
    return EXIT_OK


def _all_lines(dir_fd: int, names: list[str]) -> Iterator[bytes]:
    for name in names:
        yield from read_lines(dir_fd, name)


def main() -> None:
    sys.exit(run(sys.argv[1:], sys.stdout, sys.stderr))
