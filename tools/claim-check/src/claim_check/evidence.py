"""Check a claim's exact facts in code, and cut the log excerpt Jev will read.

Every count, comparison and lookup is here: whether a SHA is on the branch,
whether a summary line appears word for word, whether the recorded exit code
matches, whether a number appears in its raw output, and whether a summary's
own counts say zero tests or failures.
"""

from __future__ import annotations

import json
import re
import subprocess
from dataclasses import dataclass
from decimal import ROUND_HALF_EVEN, ROUND_HALF_UP, Decimal, InvalidOperation
from pathlib import Path

from .report import NUMBER, Claim

EXCERPT_BEFORE = 8
EXCERPT_AFTER = 6
EXCERPT_MAX_CHARS = 2000

# An exit code as the logs record it: "exit 0", "EXIT 0", "exit: 1",
# "full-exit 0", "(exit code 0)", "exit=124", or a JSON "exit_code": 0.
EXIT_RECORD = re.compile(
    r"(?:\bexit\"?(?: code)?|\bEXIT|\"exit_code\")\s*[:=]?\s*(?P<code>\d{1,3})\b", re.IGNORECASE
)


@dataclass(frozen=True)
class Log:
    path: str  # repository-relative
    text: str

    @property
    def lines(self) -> list[str]:
        return self.text.splitlines()


@dataclass(frozen=True)
class Fact:
    """What code settled about one claim."""

    status: str  # "found", "not_found", "contradicted", "ambiguous", "empty", "listed"
    reason: str
    log_path: str = ""
    excerpt: str = ""
    exit_record: str = ""


def render(path: Path) -> str:
    """A log as text. JSON-lines step records are expanded so their output reads as lines."""
    raw = path.read_text(errors="replace")
    records = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            return raw
        if not isinstance(record, dict) or not ({"stdout", "stderr"} & record.keys()):
            return raw
        records.append(record)
    if not records:
        return raw
    out = []
    for r in records:
        out.append(f"## step {r.get('check', '')}: exit {r.get('exit_code', '')}")
        for key in ("stdout", "stderr"):
            if r.get(key):
                out.append(str(r[key]).rstrip("\n"))
    return "\n".join(out) + "\n"


def normalize(text: str) -> str:
    table = str.maketrans({"“": '"', "”": '"', "‘": "'", "’": "'", "`": ""})
    text = re.sub(r"(?<=\d),(?=\d{3}\b)", "", text.translate(table))  # 87,440 is 87440
    return re.sub(r"\s+", " ", text).strip()


def _line_pattern(value: str) -> re.Pattern[str]:
    """A quoted summary as a pattern: whitespace flexible, an ellipsis stands for any text."""
    parts = re.split(r"\s*(?:\.\.\.|…)\s*", normalize(value))
    body = r".{0,400}?".join(r"\s+".join(map(re.escape, p.split(" "))) for p in parts)
    return re.compile(body)


def _subjects(words: str) -> set[str]:
    """Names in the report's words that a log may print: backticked terms and file stems."""
    names = set()
    for quoted in re.findall(r"`([^`]+)`", words):
        for token in re.split(r"[\s/]+", quoted):
            stem = token.rsplit(".", 1)[0] if "." in token else token
            if len(stem) >= 4 and re.search(r"[A-Za-z]", stem) and not re.search(r"\d+/\d+", stem):
                names.add(stem)
    return names


def _find_line(logs: list[Log], value: str, words: str = "") -> tuple[Log, int] | None:
    """The line a quoted summary sits on. When it appears more than once, the match whose
    surroundings name more of the report's subjects wins; ties go to the first."""
    pattern = _line_pattern(value)
    subjects = _subjects(words)
    best: tuple[int, Log, int] | None = None
    for log in logs:
        lines = log.lines
        for i in range(len(lines)):
            # a quoted line may wrap in the log, so look at a short window from each line
            window = normalize(" ".join(lines[i : i + 3]))
            m = pattern.search(window)
            if not (m and m.start() < len(normalize(lines[i])) + 1):
                continue
            around = "\n".join(lines[max(0, i - EXCERPT_BEFORE) : i + EXCERPT_AFTER + 1])
            score = sum(name in around for name in subjects)
            if best is None or score > best[0]:
                best = (score, log, i)
    return None if best is None else (best[1], best[2])


def excerpt(log: Log, index: int) -> str:
    lines = log.lines
    lo = max(0, index - EXCERPT_BEFORE)
    hi = min(len(lines), index + EXCERPT_AFTER + 1)
    text = "\n".join(lines[lo:hi])
    if len(text) > EXCERPT_MAX_CHARS:
        # keep the matched line in view: trim from the far end of the window
        keep = "\n".join(lines[max(lo, index - 3) : min(hi, index + 3)])
        text = keep[-EXCERPT_MAX_CHARS:]
    if lo > 0 and lines and "\t" in lines[0]:
        text = lines[0] + "\n" + text  # a table's header names its columns
    return text


def _is_record(line: str, m: re.Match[str]) -> bool:
    """An exit record is the line's own statement ("exit=0", "test exit 0", "---- mo run,
    exit 0", "exit=124 (TIMED OUT)"), not an exit mentioned in prose ("a planted panic:
    exit 134, counted as a crash")."""
    before = len(line[: m.start()].split())
    after = len(line[m.end() :].split())
    return before <= 3 or after <= 1


def exit_records(log: Log, after: int = 0) -> list[tuple[int, str]]:
    """Exit codes a log records, from line `after` on."""
    stripped = log.text.strip()
    if re.fullmatch(r"\d{1,3}", stripped):
        return [(int(stripped), stripped)]
    found = []
    for line in log.lines[after:]:
        for m in EXIT_RECORD.finditer(line):
            if _is_record(line.strip(), m):
                found.append((int(m.group("code")), line.strip()))
    return found


def _stem(path: str) -> str:
    return Path(path).name.split(".")[0]


def exit_sources(log: Log, index: int, logs: list[Log]) -> list[tuple[Log, int]]:
    """Where the exit code of the run printed at `log` line `index` may be recorded.

    The run's own log, after its summary line (a run prints its exit after its
    summary; exit records before it belong to other commands), then a file in the
    same folder that records exits and shares the log's name before its first
    dash or dot ("step40-darwin-full.exit" for "step40-darwin-full.tail.txt",
    "darwin-exits.txt" for "darwin-full-suite.log").
    """
    sources = [(log, index)]
    # a step record rendered from JSON lines carries its exit code in its header line
    for back in range(index, -1, -1):
        if log.lines[back].startswith("## step "):
            sources.insert(0, (Log(log.path, log.lines[back]), 0))
            break
    folder = Path(log.path).parent
    first = re.split(r"[-.]", _stem(log.path))[0]
    for other in logs:
        if other is log or Path(other.path).parent != folder:
            continue
        name = Path(other.path).name
        if ("exit" in name or "status" in name) and (
            name.startswith(_stem(log.path)) or name.startswith(first)
        ):
            sources.append((other, 0))
    return sources


def check_summary(claim: Claim, logs: list[Log]) -> Fact:
    counts = claim.counts
    failed = counts.get("failed", 0)
    total = counts.get("total", counts.get("passed", 0) + failed + counts.get("skipped", 0))
    # the counts are code's: zero tests, or failures claimed with exit 0
    if "inputs" in counts:
        if counts["inputs"] == 0:
            return Fact("empty", "the summary counts 0 inputs")
    elif total == 0:
        return Fact("empty", "the summary counts 0 tests")
    if claim.exit_code == 0 and (failed > 0 or counts.get("crashes", 0) > 0):
        return Fact("contradicted", "the summary itself counts failures, but exit 0 is claimed")

    hit = _find_line(logs, claim.value, claim.words)
    if hit is None:
        return Fact("not_found", "the summary line is not in any raw log given")
    log, index = hit
    text = excerpt(log, index)
    if claim.exit_code is None:
        return Fact("found", "found word for word; the report gives no exit code", log.path, text)

    for candidate, after in exit_sources(log, index, logs):
        records = exit_records(candidate, after)
        if not records:
            continue
        codes = {code for code, _ in records}
        record = "\n".join(f"{candidate.path}: {ln}" for _, ln in records[:6])
        if len(codes) > 1:
            return Fact(
                "ambiguous",
                f"the exit records disagree ({sorted(codes)}); which is this run's is not "
                "code's to say",
                log.path,
                text,
                record,
            )
        if claim.exit_code in codes:
            return Fact("found", "found word for word, exit code recorded", log.path, text, record)
        return Fact(
            "contradicted",
            f"the log records exit {sorted(codes)}, the report exit {claim.exit_code}",
            log.path,
            text,
            record,
        )
    return Fact(
        "not_found", "the summary line is found but no exit code is recorded", log.path, text
    )


def is_ancestor(sha: str, ref: str, repo: Path) -> bool:
    exists = subprocess.run(
        ["git", "cat-file", "-e", f"{sha}^{{commit}}"], cwd=repo, capture_output=True
    )
    if exists.returncode != 0:
        return False
    ancestor = subprocess.run(
        ["git", "merge-base", "--is-ancestor", sha, ref], cwd=repo, capture_output=True
    )
    return ancestor.returncode == 0


def check_commit(claim: Claim, ref: str, repo: Path) -> Fact:
    if is_ancestor(claim.value, ref, repo):
        return Fact("found", f"on {ref}")
    return Fact("not_found", f"not a commit on {ref}")


def _decimal(text: str) -> Decimal | None:
    try:
        return Decimal(text.replace(",", ""))
    except InvalidOperation:
        return None


def _scale(claimed: str, raw: Decimal) -> Decimal | None:
    """The factor that turns a raw number into the claimed one at the claim's precision,
    or None. A report rounds (28.7 for 28.71) and may change the unit by a factor of a
    thousand (4.75 ms for 4750 µs); either rounding direction is accepted."""
    value = _decimal(claimed)
    if value is None:
        return None
    exponent = value.as_tuple().exponent
    places = -exponent if isinstance(exponent, int) and exponent < 0 else 0
    quantum = Decimal(1).scaleb(-places)
    for scale in (Decimal(1), Decimal(1000), Decimal("0.001")):
        for rounding in (ROUND_HALF_UP, ROUND_HALF_EVEN):
            try:
                if (raw / scale).quantize(quantum, rounding=rounding) == value:
                    return scale
            except InvalidOperation:
                continue
    return None


def _matches(claimed: str, raw: Decimal) -> bool:
    return _scale(claimed, raw) is not None


def _label_words(label: str) -> set[str]:
    """Words of a number's row and column ("`read` small file (2,000) / `mo run` before")."""
    return {w for w in re.findall(r"[a-z_]{3,}", label.lower())}


def check_number(claim: Claim, logs: list[Log]) -> Fact:
    """A number is found when a raw number rounds to it. Of several such lines, the one
    that names more of the claim's row and column wins; ties go to the first. Jev is
    shown only that line and the table's header, and code says which number matched."""
    words = _label_words(claim.label)
    best: tuple[int, Log, int, str, Decimal] | None = None
    for log in logs:
        for i, line in enumerate(log.lines):
            for m in NUMBER.finditer(line):
                raw = _decimal(m.group(0))
                scale = _scale(claim.value, raw) if raw is not None else None
                if scale is not None:
                    score = sum(w in line.lower() for w in words)
                    if best is None or score > best[0]:
                        best = (score, log, i, m.group(0), scale)
                    break
    if best is None:
        return Fact("not_found", "no number in the raw output rounds to it")
    _, log, i, raw_text, scale = best
    lines = log.lines
    header = lines[0] if i > 0 and "\t" in lines[0] else ""
    shown = "\n".join(x for x in (header, lines[i]) if x)
    if scale == 1:
        how = f"{raw_text} in this line rounds to the claimed {claim.value}"
    else:
        per = "thousandths" if scale == 1000 else "thousands"
        how = f"{raw_text} in this line, counted in {per}, rounds to the claimed {claim.value}"
    return Fact("found", how, log.path, shown)


def check(claim: Claim, logs: list[Log], ref: str, repo: Path) -> Fact:
    if claim.kind == "summary":
        return check_summary(claim, logs)
    if claim.kind == "commit":
        return check_commit(claim, ref, repo)
    if claim.kind == "number":
        return check_number(claim, logs)
    return Fact("listed", "a decision is for the lead to read; nothing to check it against")
