"""The gate, and the pipeline that runs a report through every stage.

Code's verdicts (incomplete, contradicted, not found, ambiguous, empty) go to
the lead. So do Jev's contradicted and unsupported, a Noul at or above its
threshold on a claim that depends on it, and anything supported below the
confidence threshold. Supported at or above the threshold is listed last.
Nothing here accepts anything.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from . import guard
from .evidence import Fact, Log, check
from .judge import Judge, Judgment
from .report import Claim, parse

RANK = {
    "not_sent": 0,
    "unjudged": 0,
    "contradicted": 1,
    "not_found": 2,
    "ambiguous": 2,
    "empty": 3,
    "suspect": 4,
    "unsupported": 5,
    "uncertain": 6,
    "supported": 7,
    "on_branch": 8,
    "listed": 9,
}
TO_LEAD = {
    "not_sent",
    "unjudged",
    "contradicted",
    "not_found",
    "ambiguous",
    "empty",
    "suspect",
    "unsupported",
    "uncertain",
}


@dataclass(frozen=True)
class Thresholds:
    confidence: float = 0.8  # the cookbook's; replaced by the calibrated value
    noul: float = 0.5


@dataclass(frozen=True)
class Row:
    claim: Claim
    fact: Fact
    judgment: Judgment | None
    verdict: str
    reason: str
    state: dict[str, str] | None = None

    @property
    def to_lead(self) -> bool:
        return self.verdict in TO_LEAD


@dataclass
class Result:
    incomplete: list[str]
    rows: list[Row] = field(default_factory=list)

    def ordered(self) -> list[Row]:
        return sorted(self.rows, key=lambda r: (RANK[r.verdict], r.claim.id))

    @property
    def sent_to_lead(self) -> int:
        return len(self.incomplete) + sum(r.to_lead for r in self.rows)


def applicable_nouls(claim: Claim) -> list[str]:
    """The Nouls a claim depends on. Code acts on no other."""
    if claim.kind != "summary":
        return []
    nouls = ["empty_selection"]
    claims_success = claim.exit_code == 0 or (
        claim.exit_code is None and claim.counts.get("failed", 0) == 0
    )
    if claims_success:
        nouls.append("masked_failure")
        if not claim.filtered:
            nouls.append("skipped")
    return nouls


def verdict(claim: Claim, fact: Fact, judgment: Judgment | None, t: Thresholds) -> tuple[str, str]:
    if fact.status in ("contradicted", "not_found", "ambiguous", "empty"):
        return fact.status, fact.reason
    if claim.kind == "commit":
        return "on_branch", fact.reason
    if claim.kind == "decision" or judgment is None:
        return "listed", fact.reason
    if judgment.relation == "contradicts":
        return "contradicted", f"Jev: contradicts ({judgment.confidence:.2f})"
    if judgment.relation == "says_nothing":
        return "unsupported", f"Jev: says nothing ({judgment.confidence:.2f})"
    raised = [
        f"{name} {getattr(judgment, name):.2f}"
        for name in applicable_nouls(claim)
        if getattr(judgment, name) >= t.noul
    ]
    if raised:
        return "suspect", "Jev: supports, but " + ", ".join(raised)
    if judgment.confidence < t.confidence:
        return "uncertain", f"Jev: supports below the threshold ({judgment.confidence:.2f})"
    return "supported", f"Jev: supports ({judgment.confidence:.2f}); not acceptance"


def claim_sentence(claim: Claim) -> str:
    if claim.kind == "number":
        return f"The measurement for {claim.label} is {claim.value}."
    exit_part = (
        f", and it exited with code {claim.exit_code}" if claim.exit_code is not None else ""
    )
    return f"The run printed the summary `{claim.value}`{exit_part}."


def state_for(claim: Claim, fact: Fact) -> dict[str, str]:
    state = {
        "claim": claim_sentence(claim),
        "report_words": claim.words[:1200],
        "log_excerpt": fact.excerpt,
    }
    if fact.exit_record:
        state["exit_record"] = fact.exit_record
    return state


def run(
    report_text: str,
    logs: list[Log],
    ref: str,
    repo: Path,
    judge: Judge,
    thresholds: Thresholds,
    report_path: str,
) -> Result:
    report = parse(report_text)
    result = Result(incomplete=list(report.missing))
    for claim in report.claims:
        fact = check(claim, logs, ref, repo)
        judgment = None
        state = None
        if fact.status == "found" and claim.kind in ("summary", "number"):
            state = state_for(claim, fact)
            try:
                judgment = judge.ask(state, [report_path, fact.log_path])
            except guard.Refused as refused:
                result.rows.append(Row(claim, fact, None, "not_sent", str(refused), state))
                continue
            except LookupError as missing:  # a recorded judge with no answer for this state
                result.rows.append(Row(claim, fact, None, "unjudged", str(missing), state))
                continue
        label, reason = verdict(claim, fact, judgment, thresholds)
        result.rows.append(Row(claim, fact, judgment, label, reason, state))
    return result


def render(result: Result) -> str:
    """The lead's working note: what to look at first."""
    lines = ["# Claim check (a working note; never acceptance, never evidence)", ""]
    for item in result.incomplete:
        lines.append(f"- **incomplete**: {item}")
    for row in result.ordered():
        flag = "**" if row.to_lead else ""
        lines.append(
            f"- {flag}{row.verdict}{flag} [{row.claim.kind}] `{row.claim.value[:90]}`: {row.reason}"
            + (f" ({row.fact.log_path})" if row.fact.log_path else "")
        )
    lines.append("")
    lines.append(f"{result.sent_to_lead} items for the lead.")
    return "\n".join(lines) + "\n"
