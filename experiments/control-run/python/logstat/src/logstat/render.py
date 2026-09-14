"""The summary as the text report or as one JSON object. Neither shows a card number."""

import json

from logstat.contract import ensure
from logstat.record import CARD_NUMBER
from logstat.summary import Summary


def render_text(summary: Summary) -> str:
    lines = [
        *_totals(summary),
        "",
        "slowest",
        *_slowest_rows(summary),
        "",
        "busiest",
        *_busiest_rows(summary),
    ]
    return _no_card_numbers("\n".join(lines) + "\n")


def render_json(summary: Summary) -> str:
    return _no_card_numbers(json.dumps(summary.model_dump(), ensure_ascii=False) + "\n")


def _totals(summary: Summary) -> list[str]:
    requests, errors, malformed, rate = (
        f"{summary.requests:_}",
        f"{summary.errors:_}",
        f"{summary.malformed:_}",
        f"{summary.per_minute:_.1f}",
    )
    width = max(len(requests), len(errors), len(malformed), len(rate))
    percent = 100 * summary.errors / summary.requests if summary.requests else 0.0
    return [
        f"requests   {requests:>{width}}",
        f"errors     {errors:>{width}}  ({percent:.1f}%)",
        f"malformed  {malformed:>{width}}",
        f"per minute {rate:>{width}}",
    ]


def _slowest_rows(summary: Summary) -> list[str]:
    if not summary.slowest:
        return []
    durations = [f"{entry.ms:_}" for entry in summary.slowest]
    requests = [f"{entry.method} {entry.path}" for entry in summary.slowest]
    ms_width = max(map(len, durations))
    request_width = max(map(len, requests))
    return [
        f"  {ms:>{ms_width}} ms  {request:<{request_width}}   {entry.at}"
        for ms, request, entry in zip(durations, requests, summary.slowest, strict=True)
    ]


def _busiest_rows(summary: Summary) -> list[str]:
    if not summary.busiest:
        return []
    counts = [f"{entry.count:_}" for entry in summary.busiest]
    width = max(map(len, counts))
    return [
        f"  {count:>{width}}  {entry.method} {entry.path}"
        for count, entry in zip(counts, summary.busiest, strict=True)
    ]


def _no_card_numbers(output: str) -> str:
    ensure(CARD_NUMBER.search(output) is None, "no card number (16 digits) reaches stdout")
    return output
