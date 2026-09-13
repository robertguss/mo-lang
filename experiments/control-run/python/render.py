"""The summary as a text report or one JSON object."""

from __future__ import annotations

import json

from records import Record, has_card, require
from tally import PathCount, Summary

_LABEL = 10


def render_text(summary: Summary) -> str:
    sections = [header(summary), slowest_section(summary.slowest), busiest_section(summary.busiest)]
    return "\n\n".join("\n".join(lines) for lines in sections) + "\n"


def header(summary: Summary) -> list[str]:
    return [
        f"{'requests':<{_LABEL}}{summary.requests:>6_}",
        f"{'errors':<{_LABEL}}{summary.errors:>6_}  ({summary.error_rate * 100:.1f}%)",
        f"{'malformed':<{_LABEL}}{summary.malformed:>6_}",
        f"{'per minute':<{_LABEL}}{summary.per_minute:>7_.1f}",
    ]


def slowest_section(records: tuple[Record, ...]) -> list[str]:
    durations = [f"{r.duration_ms:_}" for r in records]
    requests = [f"{r.method} {r.path}" for r in records]
    ms_width = max(map(len, durations), default=0)
    request_width = max(map(len, requests), default=0)
    rows = [
        f"  {ms:>{ms_width}} ms  {request:<{request_width}}   {r.at_text}"
        for ms, request, r in zip(durations, requests, records)
    ]
    return ["slowest", *rows]


def busiest_section(entries: tuple[PathCount, ...]) -> list[str]:
    counts = [f"{e.count:_}" for e in entries]
    width = max(map(len, counts), default=0)
    rows = [f"  {count:>{width}}  {e.method} {e.path}" for count, e in zip(counts, entries)]
    return ["busiest", *rows]


def render_json(summary: Summary) -> str:
    document = {
        "requests": summary.requests,
        "errors": summary.errors,
        "error_rate": round(summary.error_rate, 3),
        "malformed": summary.malformed,
        "per_minute": round(summary.per_minute, 1),
        "slowest": [
            {"ms": r.duration_ms, "method": r.method, "path": r.path, "at": r.at_text} for r in summary.slowest
        ],
        "busiest": [{"count": e.count, "method": e.method, "path": e.path} for e in summary.busiest],
    }
    return json.dumps(document, ensure_ascii=False) + "\n"


def ensure_no_card(output: str) -> str:
    """The last check before stdout: no 16-digit run leaves the program."""
    require(not has_card(output), "output holds no card number")
    return output
