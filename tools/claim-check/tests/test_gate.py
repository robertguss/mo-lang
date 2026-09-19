from __future__ import annotations

from pathlib import Path

from conftest import ScriptedJudge

from claim_check.evidence import Log
from claim_check.gate import Thresholds, run

REPORT = """# R

## Commits

- `4ad89c1a` merge

## Results

- `zig build test --summary all`: exit 0,
  `Build Summary: 5/5 steps succeeded; 9/9 tests passed`.
- `zig build test -Dtest-filter=x --summary all`: exit 0,
  `Build Summary: 5/5 steps succeeded; 3/3 tests passed`.
- `zig build test --summary all`: exit 0,
  `Build Summary: 5/5 steps succeeded; 7/7 tests passed`.

## Decisions the brief did not cover

- none
"""
LOG = Log(
    "suite.log",
    "Build Summary: 5/5 steps succeeded; 9/9 tests passed\nexit=0\n"
    "Build Summary: 5/5 steps succeeded; 3/3 tests passed\nexit=0\n",
)


DEFAULT = Thresholds()


def verdicts(judge: ScriptedJudge, repo: Path, t: Thresholds = DEFAULT) -> dict[str, str]:
    result = run(REPORT, [LOG], "HEAD", repo, judge, t, "toolchain/STEP-43-REPORT.md")
    return {r.claim.value: r.verdict for r in result.rows}


NINE = "Build Summary: 5/5 steps succeeded; 9/9 tests passed"
THREE = "Build Summary: 5/5 steps succeeded; 3/3 tests passed"
SEVEN = "Build Summary: 5/5 steps succeeded; 7/7 tests passed"


def test_only_the_residue_reaches_the_model(repo: Path) -> None:
    judge = ScriptedJudge()
    v = verdicts(judge, repo)
    assert v[SEVEN] == "not_found" and v["4ad89c1a"] == "on_branch"
    assert len(judge.asked) == 2
    assert set(judge.asked[0]) >= {"claim", "report_words", "log_excerpt", "exit_record"}
    assert v[NINE] == "supported"


def test_the_model_can_contradict_or_say_nothing(repo: Path) -> None:
    assert verdicts(ScriptedJudge(relation="contradicts"), repo)[NINE] == "contradicted"
    assert verdicts(ScriptedJudge(relation="says_nothing"), repo)[NINE] == "unsupported"


def test_low_confidence_goes_to_the_lead(repo: Path) -> None:
    v = verdicts(ScriptedJudge(confidence=0.6), repo)
    assert v[NINE] == "uncertain"
    assert verdicts(ScriptedJudge(confidence=0.6), repo, Thresholds(0.5, 0.5))[NINE] == "supported"


def test_a_noul_acts_only_where_the_claim_depends_on_it(repo: Path) -> None:
    v = verdicts(ScriptedJudge(skipped=0.9), repo)
    assert v[NINE] == "suspect"  # a whole-suite claim depends on nothing being skipped
    assert v[THREE] == "supported"  # a filtered run skips tests by design
    assert verdicts(ScriptedJudge(masked_failure=0.8), repo)[THREE] == "suspect"
    assert verdicts(ScriptedJudge(empty_selection=0.49), repo)[NINE] == "supported"
