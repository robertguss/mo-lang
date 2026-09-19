"""Collect the claims from the fixed parts of a worker report.

Only the parts whose form a brief already fixes are read: test and fuzz
summary lines with the exit code written beside them, commit SHAs, the
"Decisions the brief did not cover" list, and the rows of a table under a
heading named "Numbers". Free prose is never mined for claims.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

# A summary line as the tools print it. Each pattern captures the whole line
# as the report quotes it; the named groups are what code checks.
SUMMARY_PATTERNS: tuple[re.Pattern[str], ...] = (
    # zig build test: "Build Summary: 5/5 steps succeeded; 121/121 tests passed"
    # or the short form a report quotes, "5/5 steps succeeded; 15/15 tests passed".
    re.compile(
        r"(?:Build Summary: )?\d+/\d+ steps succeeded(?: \(\d+ failed\))?; "
        r"(?P<passed>\d+)/(?P<total>\d+) tests passed(?: \((?P<failed>\d+) failed\))?"
    ),
    # unittest: "Ran 5 tests" (optionally "in 1.2s"), then OK or FAILED.
    re.compile(
        r"Ran (?P<total>\d+) tests?(?: in [\d.]+s)?"
        r"(?:(?: ?/ ?| \.\.\. | …)(?P<status>OK|FAILED(?: \([^)]*\))?))?"
    ),
    # mo test: "6 passed, 0 failed, 0 skipped"
    re.compile(r"(?P<passed>\d+) passed, (?P<failed>\d+) failed, (?P<skipped>\d+) skipped"),
    # the fuzz drivers: "87440 inputs in 2186 batches, seed 3701: 0 crashes"
    re.compile(
        r"(?P<inputs>\d[\d,]*) inputs in (?P<batches>\d[\d,]*) batches, seed \d+: "
        r"(?P<crashes>\d[\d,]*) crashes"
    ),
)

EXIT_NEAR = re.compile(r"exit(?: code)?[ :=*]*\**(?P<code>\d{1,3})\b", re.IGNORECASE)
SHA = re.compile(r"`(?P<sha>[0-9a-f]{7,40})`")
# a plain-text commit list: "  f8d8dfc  Step 37 part A"
SHA_LEAD = re.compile(r"(?m)^\s*(?P<sha>[0-9a-f]{7,40})\s{2,}\S")
DECISIONS_HEADING = re.compile(r"decisions", re.IGNORECASE)
NUMBERS_HEADING = re.compile(r"^numbers\b", re.IGNORECASE)
NUMBER = re.compile(r"(?<![\w.])-?\d[\d,]*(?:\.\d+)?(?![\w.])")
# a plain-text report's heading: a line of capitals, as "DECISIONS THE BRIEF DID NOT COVER"
CAPS_HEADING = re.compile(r"^([A-Z][A-Z0-9 ,'()/-]{7,})$")
FILTER = re.compile(r"-Dtest-filter|--only|-k |-p '")


@dataclass(frozen=True)
class Claim:
    """One checkable statement from a report, with the words it came from."""

    id: str
    kind: str  # "summary", "commit", "number" or "decision"
    value: str  # the summary line, the SHA, the number, or the decision text
    words: str  # the report's own words: the bullet, row or paragraph
    section: str
    exit_code: int | None = None
    filtered: bool = False  # the command named a filter, so not every test ran
    counts: dict[str, int] = field(default_factory=dict)
    label: str = ""  # for a number: its row and column


@dataclass(frozen=True)
class Report:
    claims: list[Claim]
    missing: list[str]  # required parts the report does not have


@dataclass
class _Unit:
    section: str
    text: str
    table_header: list[str] | None = None


def _units(text: str) -> list[_Unit]:
    """Split a report into bullets, table rows and paragraphs, each with its section."""
    units: list[_Unit] = []
    section = ""
    current: list[str] = []
    header: list[str] | None = None

    def flush() -> None:
        if current:
            units.append(_Unit(section, "\n".join(current).strip()))
            current.clear()

    for line in text.splitlines():
        stripped = line.strip()
        heading = re.match(r"^#{1,6}\s+(.*)$", stripped) or CAPS_HEADING.match(stripped)
        if heading:
            flush()
            section = heading.group(1).strip()
            header = None
            continue
        if re.fullmatch(r"[=_~-]{5,}", stripped):
            flush()
            continue
        if stripped.startswith("|"):
            flush()
            cells = [c.strip() for c in stripped.strip("|").split("|")]
            if all(re.fullmatch(r":?-{2,}:?", c) for c in cells if c):
                continue
            if header is None:
                header = cells
                continue
            units.append(_Unit(section, stripped, header))
            continue
        header = None
        if not stripped:
            flush()
            continue
        # A bullet or numbered item indented less than four starts a new unit;
        # its more deeply indented lines continue it.
        indent = len(line) - len(line.lstrip())
        if re.match(r"^(?:[-*+]|\d+[.)])\s", stripped) and indent < 4:
            flush()
        current.append(stripped)
    flush()
    return units


def _counts(match: re.Match[str]) -> dict[str, int]:
    counts = {}
    for k, v in match.groupdict().items():
        if v is not None and v.replace(",", "").isdigit():
            counts[k] = int(v.replace(",", ""))
    return counts


def _exit_for(unit_text: str, start: int, end: int) -> int | None:
    """The exit code written nearest to a summary line in the same unit."""
    best: tuple[int, int] | None = None
    for m in EXIT_NEAR.finditer(unit_text):
        if start <= m.start() < end:
            continue
        distance = start - m.end() if m.end() <= start else m.start() - end
        if best is None or distance < best[0]:
            best = (distance, int(m.group("code")))
    return None if best is None else best[1]


def _numbers(unit: _Unit, next_id: int) -> list[Claim]:
    header = unit.table_header or []
    cells = [c.strip() for c in unit.text.strip().strip("|").split("|")]
    if not cells:
        return []
    row = cells[0]
    claims: list[Claim] = []
    for col, cell in enumerate(cells[1:], start=1):
        column = header[col] if col < len(header) else f"column {col}"
        if re.search(r"load", column, re.IGNORECASE):
            continue  # the load average is context, not a result
        for m in NUMBER.finditer(cell.replace("*", "")):
            claims.append(
                Claim(
                    id=f"c{next_id + len(claims)}",
                    kind="number",
                    value=m.group(0),
                    words=unit.text,
                    section=unit.section,
                    label=f"{row} / {column}",
                )
            )
    return claims


def parse(text: str) -> Report:
    """Collect the claims of one report and name the required parts it lacks."""
    claims: list[Claim] = []
    seen_sha: set[str] = set()
    decisions_seen = False

    def nid() -> str:
        return f"c{len(claims) + 1}"

    for unit in _units(text):
        in_decisions = bool(DECISIONS_HEADING.search(unit.section))
        if in_decisions:
            decisions_seen = True
            if re.match(r"^(?:[-*+]|\d+[.)])\s", unit.text):
                claims.append(Claim(nid(), "decision", unit.text, unit.text, unit.section))
            continue

        if unit.table_header is not None and NUMBERS_HEADING.search(unit.section):
            claims.extend(_numbers(unit, len(claims) + 1))
            continue

        flat = re.sub(r"\s+", " ", unit.text)
        spans: list[tuple[int, int]] = []
        for pattern in SUMMARY_PATTERNS:
            for m in pattern.finditer(flat):
                if any(s <= m.start() < e for s, e in spans):
                    continue
                spans.append((m.start(), m.end()))
                claims.append(
                    Claim(
                        id=nid(),
                        kind="summary",
                        value=m.group(0),
                        words=unit.text,
                        section=unit.section,
                        exit_code=_exit_for(flat, m.start(), m.end()),
                        filtered=bool(FILTER.search(flat)),
                        counts=_counts(m),
                    )
                )

        for m in [*SHA.finditer(unit.text), *SHA_LEAD.finditer(unit.text)]:
            sha = m.group("sha")
            if sha in seen_sha or not re.search(r"[a-f]", sha) or not re.search(r"\d", sha):
                continue
            before = unit.text[max(0, m.start() - 8) : m.start()]
            if "sha256:" in before:
                continue
            seen_sha.add(sha)
            claims.append(Claim(nid(), "commit", sha, unit.text, unit.section))

    missing = []
    if not any(c.kind == "summary" for c in claims):
        missing.append("no test summary line")
    elif not any(c.kind == "summary" and c.exit_code is not None for c in claims):
        missing.append("no exit code beside any summary line")
    if not any(c.kind == "commit" for c in claims):
        missing.append("no commit SHA")
    if not decisions_seen:
        missing.append("no 'Decisions the brief did not cover' section")
    return Report(claims, missing)
