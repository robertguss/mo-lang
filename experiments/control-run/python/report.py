"""Rendering a Summary as the text report or as one JSON object. Both pass the card check last."""

from __future__ import annotations

import json

from contracts import require
from parse import Record, contains_card
from stats import Busy, Summary

_LABEL_WIDTH = len("per minute")


def thousands(number: int) -> str:
    """`1204` to `1_204`."""
    return f"{number:_}"


def one_decimal(number: float) -> str:
    """`1234.56` to `1_234.6`."""
    return f"{number:_.1f}"


def checked_output(text: str) -> str:
    """Ensures no card number reaches stdout, whatever was rendered."""
    require(not contains_card(text), "no card number reaches stdout")
    return text


def render_text(summary: Summary) -> str:
    lines = [
        *counts_section(summary),
        "",
        "slowest",
        *slowest_section(summary.slowest),
        "",
        "busiest",
        *busiest_section(summary.busiest),
    ]
    return checked_output("\n".join(lines) + "\n")


def counts_section(summary: Summary) -> list[str]:
    """Labels padded to one column, values right-aligned to the widest value."""
    labels = ["requests", "errors", "malformed", "per minute"]
    values = [
        thousands(summary.requests),
        thousands(summary.errors),
        thousands(summary.malformed),
        one_decimal(summary.per_minute),
    ]
    width = max(len(value) for value in values)
    lines = [f"{label:<{_LABEL_WIDTH}} {value:>{width}}" for label, value in zip(labels, values, strict=True)]
    lines[1] += f"  ({one_decimal(summary.error_rate * 100)}%)"
    return lines


def slowest_section(records: tuple[Record, ...]) -> list[str]:
    if not records:
        return []
    durations = [thousands(record.duration_ms) for record in records]
    targets = [f"{record.method} {record.path}" for record in records]
    duration_width = max(len(duration) for duration in durations)
    target_width = max(len(target) for target in targets)
    return [
        f"  {duration:>{duration_width}} ms  {target:<{target_width}}   {record.at}"
        for duration, target, record in zip(durations, targets, records, strict=True)
    ]


def busiest_section(busiest: tuple[Busy, ...]) -> list[str]:
    if not busiest:
        return []
    counts = [thousands(busy.count) for busy in busiest]
    width = max(len(count) for count in counts)
    return [
        f"  {count:>{width}}  {busy.method} {busy.path}" for count, busy in zip(counts, busiest, strict=True)
    ]


def render_json(summary: Summary) -> str:
    payload: dict[str, object] = {
        "requests": summary.requests,
        "errors": summary.errors,
        "error_rate": round(summary.error_rate, 3),
        "malformed": summary.malformed,
        "per_minute": round(summary.per_minute, 1),
        "slowest": [
            {"ms": record.duration_ms, "method": record.method, "path": record.path, "at": record.at}
            for record in summary.slowest
        ],
        "busiest": [{"count": busy.count, "method": busy.method, "path": busy.path} for busy in summary.busiest],
    }
    return checked_output(json.dumps(payload, ensure_ascii=False) + "\n")
