"""Rendering a Summary as the text report or one JSON object."""

import json

from summary import Summary

LABEL_WIDTH = 11
MIN_VALUE_WIDTH = 5


def group(number: int) -> str:
    return f"{number:_}"


def render_counts(summary: Summary) -> list[str]:
    values = [
        ("requests", group(summary.requests)),
        ("errors", group(summary.errors)),
        ("malformed", group(summary.malformed)),
        ("per minute", f"{summary.per_minute:_.1f}"),
    ]
    width = max(MIN_VALUE_WIDTH, *(len(value) for _, value in values))
    lines = [f"{label:<{LABEL_WIDTH}}{value:>{width}}" for label, value in values]
    lines[1] += f"  ({summary.error_rate * 100:.1f}%)"
    return lines


def render_slowest(summary: Summary) -> list[str]:
    rows = [(group(r.duration_ms), f"{r.method} {r.path}", r.at_text) for r in summary.slowest]
    ms_width = max((len(ms) for ms, _, _ in rows), default=0)
    request_width = max((len(request) for _, request, _ in rows), default=0)
    lines = [f"  {ms:>{ms_width}} ms  {request:<{request_width}}   {at}" for ms, request, at in rows]
    return ["slowest", *lines]


def render_busiest(summary: Summary) -> list[str]:
    rows = [(group(entry.count), f"{entry.method} {entry.path}") for entry in summary.busiest]
    count_width = max((len(count) for count, _ in rows), default=0)
    return ["busiest", *(f"  {count:>{count_width}}  {request}" for count, request in rows)]


def render_text(summary: Summary) -> str:
    sections = [render_counts(summary), render_slowest(summary), render_busiest(summary)]
    return "\n\n".join("\n".join(section) for section in sections) + "\n"


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
