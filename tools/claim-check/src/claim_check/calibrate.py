"""Run the labelled set, measure, choose thresholds, and write the results.

Offline (the default) it replays the recorded answers in
`calibration/answers.json`; a claim with no recorded answer is `unjudged`.
With `--live` it asks Jev for the missing ones, within the request budget,
and records every answer so the next run replays it.
"""

from __future__ import annotations

import argparse
import json
import statistics
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from . import guard
from .cases import Case, load_all
from .gate import TO_LEAD, Result, Row, Thresholds, applicable_nouls, run
from .judge import (
    DOLLARS_PER_INPUT_TOKEN,
    MODEL,
    QUESTIONS,
    Judge,
    RecordedJudge,
    TypeSafeJudge,
)

TOOL = Path(__file__).resolve().parents[2]
REPO = TOOL.parents[1]
CALIBRATION = TOOL / "calibration"
ANSWERS = CALIBRATION / "answers.json"
BUDGET_FILE = CALIBRATION / "budget.json"
SENT = TOOL / "sent"
BUDGET = 2000

CONFIDENCES = (0.5, 0.6, 0.7, 0.8, 0.9, 0.95)
NOULS = (0.3, 0.5, 0.7, 0.9)


@dataclass
class Scored:
    case: Case
    result: Result

    def label_of(self, row: Row) -> bool | None:
        """The truth of a claim: its label, or true for any claim of an accurate report."""
        for label in self.case.labels:
            if label.matches(row.claim):
                return label.truth
        if self.case.kind == "accurate" and row.claim.kind != "decision":
            return True
        return None

    def caught(self) -> bool:
        if self.case.caught_by_incomplete and self.result.incomplete:
            return True
        return any(r.to_lead for r in self.result.rows if self.label_of(r) is False)


def check_labels(scored: Scored) -> list[str]:
    """Every label must name a claim the parser collected; otherwise the case is broken."""
    problems = []
    for label in scored.case.labels:
        if not any(label.matches(r.claim) for r in scored.result.rows):
            problems.append(f"{scored.case.id}: no {label.kind} claim contains {label.contains!r}")
    return problems


def run_all(judge: Judge, thresholds: Thresholds, cases: list[Case]) -> list[Scored]:
    out = []
    for case in cases:
        guard.check_path(case.report, REPO)
        result = run(
            case.report_text(REPO),
            case.load_logs(REPO),
            case.ref,
            REPO,
            judge,
            thresholds,
            case.report,
        )
        out.append(Scored(case, result))
    return out


def rejudge(scored: list[Scored], thresholds: Thresholds) -> list[Scored]:
    """Apply other thresholds to the same answers: no inference is rerun."""
    from .gate import verdict

    out = []
    for s in scored:
        rows = []
        for r in s.result.rows:
            if r.judgment is None:
                rows.append(r)
                continue
            label, reason = verdict(r.claim, r.fact, r.judgment, thresholds)
            rows.append(Row(r.claim, r.fact, r.judgment, label, reason, r.state))
        out.append(Scored(s.case, Result(s.result.incomplete, rows)))
    return out


def measure(scored: list[Scored]) -> dict[str, Any]:
    planted = [s for s in scored if s.case.kind == "planted"]
    historical = [s for s in scored if s.case.kind == "historical" and s.case.defective]
    accurate = [s for s in scored if s.case.kind == "accurate"]
    true_rows = [(s, r) for s in accurate for r in s.result.rows if s.label_of(r) is True]
    false_rows = [(s, r) for s in scored for r in s.result.rows if s.label_of(r) is False]
    judged = [r for s in scored for r in s.result.rows if r.judgment is not None]
    seconds = [r.judgment.seconds for r in judged if r.judgment]
    tokens = sum(r.judgment.input_tokens for r in judged if r.judgment)
    return {
        "cases": len(scored),
        "planted_caught": sum(s.caught() for s in planted),
        "planted": len(planted),
        "historical_caught": sum(s.caught() for s in historical),
        "historical": len(historical),
        "false_claims": len(false_rows),
        "false_claims_to_lead": sum(r.to_lead for _, r in false_rows),
        "true_claims": len(true_rows),
        "true_claims_flagged": sum(r.to_lead for _, r in true_rows),
        "true_flagged_by": dict(Counter(r.verdict for _, r in true_rows if r.to_lead)),
        "true_flagged_by_model": sum(r.to_lead and r.judgment is not None for _, r in true_rows),
        "true_judged": sum(r.judgment is not None for _, r in true_rows),
        "to_lead_per_case": {s.case.id: s.result.sent_to_lead for s in scored},
        "claims_per_case": {s.case.id: len(s.result.rows) for s in scored},
        "judged_claims": len(judged),
        "latency_median_s": round(statistics.median(seconds), 3) if seconds else None,
        "latency_p95_s": (
            round(sorted(seconds)[max(0, int(len(seconds) * 0.95) - 1)], 3) if seconds else None
        ),
        "input_tokens": tokens,
        "cost_dollars": round(tokens * DOLLARS_PER_INPUT_TOKEN, 6),
    }


def sweep(scored: list[Scored]) -> list[dict[str, Any]]:
    rows = []
    for c in CONFIDENCES:
        for n in NOULS:
            m = measure(rejudge(scored, Thresholds(c, n)))
            rows.append(
                {
                    "confidence": c,
                    "noul": n,
                    **{
                        k: m[k]
                        for k in (
                            "planted_caught",
                            "historical_caught",
                            "false_claims_to_lead",
                            "true_claims_flagged",
                            "true_flagged_by_model",
                        )
                    },
                }
            )
    return rows


def choose(rows: list[dict[str, Any]]) -> dict[str, Any]:
    """The rows that send the most false claims to the lead and flag the fewest true
    ones; of those, the highest confidence (the more cautious gate), and the middle of
    the Noul thresholds tied there, so the Noul sits inside the gap the data shows and
    not on its edge."""

    def score(r: dict[str, Any]) -> tuple[int, int, int]:
        return (-r["false_claims_to_lead"], -r["planted_caught"], r["true_claims_flagged"])

    best = min(score(r) for r in rows)
    tied = [r for r in rows if score(r) == best]
    confidence = max(r["confidence"] for r in tied)
    at = sorted((r for r in tied if r["confidence"] == confidence), key=lambda r: r["noul"])
    return at[(len(at) - 1) // 2]


def wrong(scored: list[Scored]) -> list[dict[str, Any]]:
    """Every labelled claim the gate got wrong, with the exact state and answer."""
    out = []
    for s in scored:
        for r in s.result.rows:
            truth = s.label_of(r)
            if truth is None:
                continue
            if (truth is False and not r.to_lead) or (truth is True and r.to_lead):
                out.append(
                    {
                        "case": s.case.id,
                        "claim": r.claim.value,
                        "kind": r.claim.kind,
                        "truth": truth,
                        "verdict": r.verdict,
                        "reason": r.reason,
                        "nouls_applied": applicable_nouls(r.claim),
                        "state": r.state,
                        "judgment": asdict(r.judgment) if r.judgment else None,
                    }
                )
    return out


def row_json(row: Row) -> dict[str, Any]:
    return {
        "claim": asdict(row.claim),
        "fact": asdict(row.fact),
        "judgment": asdict(row.judgment) if row.judgment else None,
        "verdict": row.verdict,
        "reason": row.reason,
        "to_lead": row.verdict in TO_LEAD,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", action="store_true", help="ask Jev for unrecorded states")
    parser.add_argument("--out", type=Path, default=CALIBRATION / "results.json")
    args = parser.parse_args(argv)

    recorded: dict[str, dict[str, Any]] = (
        json.loads(ANSWERS.read_text()) if ANSWERS.exists() else {}
    )
    judge: Judge
    if args.live:
        judge = TypeSafeJudge(REPO, SENT, BUDGET_FILE, BUDGET, recorded)
    else:
        judge = RecordedJudge(recorded)

    cases = load_all(CALIBRATION / "cases")
    try:
        scored = run_all(judge, Thresholds(), cases)
    finally:
        if args.live:
            ANSWERS.write_text(json.dumps(recorded, indent=1, sort_keys=True) + "\n")

    problems = [p for s in scored for p in check_labels(s)]
    table = sweep(scored)
    chosen = choose(table)
    final = rejudge(scored, Thresholds(chosen["confidence"], chosen["noul"]))
    requests = json.loads(BUDGET_FILE.read_text())["requests"] if BUDGET_FILE.exists() else 0
    output = {
        "model": MODEL,
        "questions": QUESTIONS,
        "label_problems": problems,
        "requests_spent": requests,
        "budget": BUDGET,
        "at_cookbook_threshold": measure(scored),
        "sweep": table,
        "chosen": chosen,
        "at_chosen_threshold": measure(final),
        "wrong": wrong(final),
        "cases": {
            s.case.id: {
                "kind": s.case.kind,
                "defective": s.case.defective,
                "expected": s.case.expected,
                "caught": s.caught(),
                "incomplete": s.result.incomplete,
                "rows": [row_json(r) for r in s.result.ordered()],
            }
            for s in final
        },
    }
    args.out.write_text(json.dumps(output, indent=1, ensure_ascii=False) + "\n")
    summary = {k: output[k] for k in ("requests_spent", "chosen", "label_problems")}
    print(json.dumps(summary, indent=1))
    print(json.dumps(output["at_chosen_threshold"], indent=1))
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
