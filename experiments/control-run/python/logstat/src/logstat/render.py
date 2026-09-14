"""The two outputs: the text report and one JSON object."""

from logstat.summary import Summary

_LABEL_WIDTH = 10


def render_text(summary: Summary) -> str:
    counts = [
        ("requests", f"{summary.requests:_}"),
        ("errors", f"{summary.errors:_}"),
        ("malformed", f"{summary.malformed:_}"),
        ("per minute", f"{summary.per_minute:_.1f}"),
    ]
    width = max(len(value) for _, value in counts)
    percent = 100 * summary.errors / summary.requests if summary.requests else 0.0
    lines = [f"{label:<{_LABEL_WIDTH}} {value:>{width}}" for label, value in counts]
    lines[1] += f"  ({percent:.1f}%)"
    lines += ["", "slowest", *_slowest_lines(summary), "", "busiest", *_busiest_lines(summary)]
    return "\n".join(lines) + "\n"


def _slowest_lines(summary: Summary) -> list[str]:
    rows = [(f"{s.ms:_}", f"{s.method} {s.path}", s.at) for s in summary.slowest]
    ms_width = max((len(ms) for ms, _, _ in rows), default=0)
    request_width = max((len(request) for _, request, _ in rows), default=0)
    return [
        f"  {ms:>{ms_width}} ms  {request:<{request_width}}   {at}" for ms, request, at in rows
    ]


def _busiest_lines(summary: Summary) -> list[str]:
    rows = [(f"{b.count:_}", f"{b.method} {b.path}") for b in summary.busiest]
    count_width = max((len(count) for count, _ in rows), default=0)
    return [f"  {count:>{count_width}}  {request}" for count, request in rows]


def render_json(summary: Summary) -> str:
    return summary.model_dump_json() + "\n"
