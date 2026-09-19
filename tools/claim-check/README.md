# claim-check

The lead's triage of a worker report: each claim in the report's fixed parts is
compared with the raw output it rests on, and the lead gets an ordered list of
places to look. **It never accepts anything.** Its output is the lead's working
note: never raw evidence, never a path in a `ready` record, never a reading.
Plan: `mo-wiki/plans/report-claim-check.md`.

## Stages

1. `report.py` collects claims from the fixed parts only: test and fuzz summary
   lines with the exit code beside them, commit SHAs, the "Decisions the brief
   did not cover" list, and the rows of a `Numbers` table. A report missing a
   required part is `incomplete`.
2. `evidence.py` settles exact facts in code: the SHA on the branch, the summary
   line word for word in a raw log, the exit code the log records, each number
   present at the report's precision, and the counts (zero tests, failures with
   exit 0). Anything not found is never sent to Jev.
3. `judge.py` asks Jev (`jev-1.13.0`, pinned) the plan's four questions in one
   request per surviving claim: the claim, the report's words and a short log
   excerpt as named JSON fields. `RecordedJudge` replays recorded answers, so
   tests and calibration re-runs are offline.
4. `gate.py` orders the verdicts for the lead; `supported` is listed last.

`guard.py` refuses, by path and by pattern, anything under `audit/mo-audit-*`,
sealed or hidden suites, secrets, `~/.mo-lead`, and anything outside the
repository. Every request's state is written to `sent/` (git-ignored) before it
is sent.

## Use

```sh
uv run pytest && uv run ruff check && uv run mypy        # offline
uv run claim-check toolchain/STEP-43-REPORT.md \
  --log audit/evidence/2026-09-19/fable-lead-verification/step43/darwin-full-suite.log
uv run python -m claim_check.calibrate                   # replays calibration/answers.json
```

With `--live` (both commands) it asks Jev for states with no recorded answer;
`TYPESAFE_API_KEY` must be in the environment, for example through `fnox exec`.
Requests count against `calibration/budget.json` (2,000 for the calibration).
Calibration results: `calibration/RESULTS.md`.
