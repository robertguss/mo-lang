from __future__ import annotations

from claim_check.calibrate import CALIBRATION, check_labels, run_all
from claim_check.cases import load_all
from claim_check.gate import Thresholds
from claim_check.judge import RecordedJudge

CASES = load_all(CALIBRATION / "cases")


def test_the_set_is_what_the_results_say() -> None:
    kinds = [c.kind for c in CASES]
    assert (kinds.count("historical"), kinds.count("accurate"), kinds.count("planted")) == (6, 3, 5)


def test_every_label_names_a_collected_claim() -> None:
    scored = run_all(RecordedJudge({}), Thresholds(), CASES)
    assert [p for s in scored for p in check_labels(s)] == []


def test_the_planted_controls_code_settles_are_caught_without_the_model() -> None:
    by_id = {c.id: c for c in CASES}
    ids = ["p1-made-up-summary", "p2-exit-mismatch", "p3-zero-passed", "p5-sha-off-branch"]
    scored = run_all(RecordedJudge({}), Thresholds(), [by_id[i] for i in ids])
    for s in scored:
        false_rows = [r for r in s.result.rows if s.label_of(r) is False]
        assert false_rows and all(r.judgment is None and r.to_lead for r in false_rows), s.case.id


def test_step36_is_flagged_incomplete() -> None:
    step36 = next(c for c in CASES if c.id == "h1-step36")
    (scored,) = run_all(RecordedJudge({}), Thresholds(), [step36])
    assert "no test summary line" in scored.result.incomplete and scored.caught()


def test_the_threshold_is_chosen_from_the_rows_not_the_cookbook() -> None:
    from claim_check.calibrate import choose

    def row(c: float, n: float, false_to_lead: int, true_flagged: int) -> dict[str, float]:
        return {
            "confidence": c,
            "noul": n,
            "false_claims_to_lead": false_to_lead,
            "planted_caught": false_to_lead,
            "true_claims_flagged": true_flagged,
        }

    rows = [
        row(0.5, 0.3, 6, 12),
        row(0.5, 0.5, 6, 12),
        row(0.6, 0.3, 6, 12),
        row(0.6, 0.5, 6, 12),
        row(0.6, 0.7, 6, 12),
        row(0.6, 0.9, 5, 12),
        row(0.8, 0.5, 6, 14),
    ]
    chosen = choose(rows)
    assert (chosen["confidence"], chosen["noul"]) == (0.6, 0.5)
