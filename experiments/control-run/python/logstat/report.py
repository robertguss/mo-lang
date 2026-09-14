"""Render a Summary as the text report or as one JSON object."""

from __future__ import annotations

import json
import math
from fractions import Fraction

from logstat.contracts import require
from logstat.record import Record
from logstat.summary import PathCount, Summary, error_rate, per_minute


def group(value: int) -> str:
    """`1204` as `1_204`."""
    require(value >= 0, "grouped numbers must not be negative")
    return f"{value:_}"


def fixed(value: Fraction, places: int, grouped: bool = False) -> str:
    """`value` rounded half up to `places` decimals."""
    require(value >= 0, "fixed numbers must not be negative")
    require(places >= 1, "places must be at least 1")
    scale = 10**places
    whole, fraction = divmod(math.floor(value * scale + Fraction(1, 2)), scale)
    whole_text = group(whole) if grouped else str(whole)
    return f"{whole_text}.{fraction:0{places}d}"


def overview_lines(summary: Summary) -> list[str]:
    labels = ["requests", "errors", "malformed", "per minute"]
    values = [
        group(summary.requests),
        group(summary.errors),
        group(summary.malformed),
        fixed(per_minute(summary), 1, grouped=True),
    ]
    width = max(len(value) for value in values)
    lines = [f"{label:<11}{value:>{width}}" for label, value in zip(labels, values, strict=True)]
    lines[1] += f"  ({fixed(error_rate(summary) * 100, 1)}%)"
    return lines


def slowest_lines(records: tuple[Record, ...]) -> list[str]:
    if not records:
        return []
    durations = [group(record.duration_ms) for record in records]
    ms_width = max(len(text) for text in durations)
    method_width = max(len(record.method) for record in records)
    path_width = max(len(record.path) for record in records)
    return [
        f"  {ms:>{ms_width}} ms  {r.method:<{method_width}} {r.path:<{path_width}}   {r.at}"
        for ms, r in zip(durations, records, strict=True)
    ]


def busiest_lines(entries: tuple[PathCount, ...]) -> list[str]:
    if not entries:
        return []
    counts = [group(entry.count) for entry in entries]
    count_width = max(len(text) for text in counts)
    method_width = max(len(entry.method) for entry in entries)
    return [
        f"  {count:>{count_width}}  {e.method:<{method_width}} {e.path}"
        for count, e in zip(counts, entries, strict=True)
    ]


def render_text(summary: Summary) -> str:
    blocks = [
        overview_lines(summary),
        ["slowest", *slowest_lines(summary.slowest)],
        ["busiest", *busiest_lines(summary.busiest)],
    ]
    return "\n\n".join("\n".join(block) for block in blocks) + "\n"


def render_json(summary: Summary) -> str:
    document = {
        "requests": summary.requests,
        "errors": summary.errors,
        "error_rate": float(fixed(error_rate(summary), 3)),
        "malformed": summary.malformed,
        "per_minute": float(fixed(per_minute(summary), 1)),
        "slowest": [
            {"ms": r.duration_ms, "method": r.method, "path": r.path, "at": r.at}
            for r in summary.slowest
        ],
        "busiest": [
            {"count": e.count, "method": e.method, "path": e.path} for e in summary.busiest
        ],
    }
    return json.dumps(document, ensure_ascii=False) + "\n"
