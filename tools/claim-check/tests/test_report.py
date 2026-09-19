from __future__ import annotations

from claim_check.report import parse

REPORT = """# Step 99 report

## Commits

| commit | what |
|---|---|
| `4fe26b9f` | GREEN |

## Results

- `zig build test -Dtest-filter=number: --summary all`: **exit 0,
  `Build Summary: 5/5 steps succeeded; 15/15 tests passed`**.
- `python3 -m unittest test_fuzz`: exit 0, `Ran 5 tests ... OK`.
- `zig build test --summary all`: exit 1, `Build Summary: 3/5 steps succeeded (1 failed);
  242/243 tests passed (1 failed)`.

## Numbers

| row | before | after | load |
|---|---:|---:|---|
| `read` (2,000) | 28.7 µs | **20.3 µs** | 5.3 |

## Decisions the brief did not cover

1. **MO0217 for every range.**
2. A second one,
   continued on an indented line.
"""


def test_fixed_parts_are_collected() -> None:
    report = parse(REPORT)
    assert report.missing == []
    summaries = [c for c in report.claims if c.kind == "summary"]
    assert [s.value for s in summaries] == [
        "Build Summary: 5/5 steps succeeded; 15/15 tests passed",
        "Ran 5 tests ... OK",
        "Build Summary: 3/5 steps succeeded (1 failed); 242/243 tests passed (1 failed)",
    ]
    assert [s.exit_code for s in summaries] == [0, 0, 1]
    assert [s.filtered for s in summaries] == [True, False, False]
    assert summaries[2].counts == {"passed": 242, "total": 243, "failed": 1}
    assert [c.value for c in report.claims if c.kind == "commit"] == ["4fe26b9f"]
    decisions = [c for c in report.claims if c.kind == "decision"]
    assert len(decisions) == 2 and "indented line" in decisions[1].value


def test_numbers_table_rows_become_claims_without_the_load() -> None:
    numbers = [c for c in parse(REPORT).claims if c.kind == "number"]
    assert [(n.value, n.label) for n in numbers] == [
        ("28.7", "`read` (2,000) / before"),
        ("20.3", "`read` (2,000) / after"),
    ]


def test_missing_parts_make_the_report_incomplete() -> None:
    report = parse("# Report\n\nThe suite is green at every commit.\n")
    assert report.missing == [
        "no test summary line",
        "no commit SHA",
        "no 'Decisions the brief did not cover' section",
    ]
    assert report.claims == []  # free prose is never mined


def test_a_summary_with_no_exit_code_is_named() -> None:
    report = parse("- `6 passed, 0 failed, 0 skipped`\n\n`abc1234` x\n\n## Decisions\n\n- none\n")
    assert report.missing == ["no exit code beside any summary line"]


def test_plain_text_reports_capitals_headings_and_commit_lists() -> None:
    text = (
        "Three commits:\n  f8d8dfc  Step 37 part A\n\n"
        "Run 1:\n  Build Summary: 5/5 steps succeeded; 234/234 tests passed\n  exit=0\n\n"
        "  87,440 inputs in 2,186 batches, seed 3701: 0 crashes; 3,601 CPU s\n\n"
        "DECISIONS THE BRIEF DID NOT COVER\n\n1. One.\n2. Two.\n"
    )
    report = parse(text)
    assert report.missing == []
    kinds = [(c.kind, c.value) for c in report.claims]
    assert ("commit", "f8d8dfc") in kinds
    assert ("summary", "Build Summary: 5/5 steps succeeded; 234/234 tests passed") in kinds
    fuzz = next(c for c in report.claims if "inputs" in c.value)
    assert fuzz.counts == {"inputs": 87440, "batches": 2186, "crashes": 0}
    assert sum(c.kind == "decision" for c in report.claims) == 2
