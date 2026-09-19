# Claim check calibration: worker report

Worker: Claude Opus 5 (fresh session, Herdr pane, bypass permissions). Branch
`tools/claim-check`, base `96fc1458`. Brief: the section "Approved, and the
calibration brief" of `mo-wiki/plans/report-claim-check.md`. I wrote only under
`tools/claim-check/`. No subagents, no push. I did not read any
`audit/mo-audit-*` file or sealed suite.

## Commits

| commit     | what                                                                                                      |
| ---------- | --------------------------------------------------------------------------------------------------------- |
| `73d21bb7` | the tool: collect, check in code, judge behind a guard, gate; offline tests                               |
| `b13d57dd` | the labelled set, 14 cases                                                                                |
| `ce6eedcd` | fix found by live run 1: a number is shown to Jev on its own row, with code's match; run 1's results kept |
| `79ec0eaa` | the threshold rule (inside the gap, not on its edge), tested                                              |
| `f2733f8d` | live results: `calibration/RESULTS.md`, `results.json`, `answers.json`, `budget.json`                     |
| (this)     | this report                                                                                               |

## Done when

Final tree `f2733f8d`, in `tools/claim-check`:

- `uv run pytest`: **exit 0**, `55 passed in 1.58s`.
- `uv run ruff check`: **exit 0**, `All checks passed!` (`ruff format --check`
  clean too).
- `uv run mypy` (strict): **exit 0**,
  `Success: no issues found in 14 source files`.
- Live results: **recorded** in `calibration/RESULTS.md`.
  `uv run python -m claim_check.calibrate` replays them offline (exit 0,
  `results.json` unchanged).

## The key

At the start neither `TYPESAFE_API_KEY` nor `~/.mo-lead/typesafe.env` was
present, so I built parts 1 and 2 first. The lead then sent word that the key
exists behind `fnox`. The two live runs were
`fnox -c ~/Projects/startups/mo-lang/fnox.toml exec -- uv run python -m claim_check.calibrate --live`,
which puts the key only in the child's environment. The key was never printed,
logged or written. A check run inside `fnox exec`, which printed only counts,
found it in none of the 76 files it could have reached: `sent/*` (73 files),
`answers.json`, `results.json` and `results-run1.json`.

## Part 1: the Shape, as code

`src/claim_check/`: `report.py` (claims from the fixed parts only),
`evidence.py` (exact facts), `judge.py` (the four questions; `TypeSafeJudge` and
the `RecordedJudge` fake behind one `Judge` interface), `gate.py`, `guard.py`,
`cases.py`, `calibrate.py`. The CLI:
`uv run claim-check <report> --log <path>... [--live]`. Details are in
`README.md`.

- Code settles the SHA on the branch, the summary line word for word, the exit
  code, each number at the report's precision, and every count (zero tests,
  failures claimed with exit 0). Only claims code found go to Jev.
- The state has named fields `claim`, `report_words` and `log_excerpt`, plus
  `exit_record` and, for numbers, `number_match` (code's arithmetic, so Jev does
  none). Excerpts are about 15 lines, capped at 2,000 characters; a number gets
  its table header and its own line only.
- The sender refuses by path (`audit/mo-audit-*`, `sealed`, `hidden suite`,
  `.mo-lead`, `fnox.toml`, `*.env`, key files, private or capability files,
  anything outside the repository) and by pattern (private keys, token shapes,
  `TYPESAFE_API_KEY=`, the key's own value, an `audit/mo-audit-` path). 29 tests
  in `tests/test_guard.py` cover this, and a refused state is neither sent nor
  recorded. Every state is written to `sent/` (git-ignored) before it is sent.

## Parts 2 and 3: the set and the live run

The full results are in `calibration/RESULTS.md`. In short:

- **14 cases:** 6 historical, 3 accurate, 5 planted.
- **73 requests** of the 2,000 budget; 78,635 input tokens; **$0.0033** (tokens
  times the Models page price; the API reports no money); **median 0.175 s**,
  p95 0.32 s.
- **Planted caught: 5 of 5.** Four were caught by code. Jev caught the
  timeout-then-success with `masked_failure` at 0.86.
- **Historical defects caught: 2 of 6, both by code.** Step 36 was `incomplete`
  (it quoted no summary line). The fuzz count was `not found` (no exit code
  recorded). The four misses are tests that cannot fail (E3, M1, step 37's
  corpus test and fuzz hour, whose output supports the claim) and a live
  regression that was never a claim (harness step 2). Reading output cannot
  catch these.
- **True claims flagged: 12 of 62.** Ten have no raw log filed, one is a correct
  zero count, and one is a code error that Jev read correctly. **Jev flagged 1
  of 34 true claims** it judged.
- **Threshold: confidence 0.6, Noul 0.5.** These come from the sweep, and the
  sample is small (42 judged claims, one catch that depended on Jev).
- **Every wrong case** is in RESULTS.md, with its exact state, question and
  answer.

**Live run 1 found a defect in my code.** In run 1, Jev flagged 14 of step 40's
32 true numbers. I checked every one in code against `numbers.tsv`, and all 32
are right. Code had matched the first raw number that rounded to the claim,
anywhere in the file, and sent Jev fifteen rows of numbers. I fixed the excerpt,
not the questions, and re-asked only the 32 changed states. Run 1's results are
kept in `results-run1.json`.

## Decisions the brief did not cover

1. **Which parts are required.** A report must have a summary line with an exit
   code, a commit SHA and a "Decisions" section; otherwise it is `incomplete`. A
   numbers table is optional, because only benchmark steps have one. Under this
   rule the accepted raw-memory report is `incomplete` (no Decisions section).
2. **Historical reports in the fixed form.** Where the record has no report in
   the fixed form (step 36, the fuzz reproduction, E3, M1), I assembled one from
   the worker's own words or the acceptance row. Each file names its sources at
   the top. Step 37 and harness step 2 (at `29ec6a66`, as first committed) are
   the real report files.
3. **Which exit record belongs to a run.** A record counts when it is in the
   run's own log after its summary line, or in a file beside the log whose name
   shares the log's first word and records exits or status. A line counts only
   when the exit is its own statement, not a mention in prose. When the records
   there disagree, the verdict is `ambiguous`, which goes to the lead.
4. **Numbers:** a raw number matches at the claim's precision, rounded either
   way, at a factor of 1 or 1,000. The line that names more of the row and
   column wins. A lone `after` column takes the runtime of the column before it.
5. **Repeated summary lines:** the occurrence whose surrounding lines name more
   of the report's backticked subjects wins.
6. **Nouls act only where the claim depends on them.** `empty_selection` applies
   to every summary. `masked_failure` applies to a claimed success. `skipped`
   applies only to an unfiltered run, since a filtered run skips tests by
   design. None applies to a number.
7. **`ambiguous`, `unjudged` and `not_sent`** are extra lead-bound verdicts,
   beside the plan's.
8. **The request budget** counts `system_one` calls in
   `calibration/budget.json`. A state with a recorded answer is replayed, not
   re-sent. The CLI's `--live` draws on the same budget.
9. **SDK transport.** httpx2 cannot parse this host's `NO_PROXY` entry `[::1]`.
   The judge builds its own httpx2 client with `trust_env=False` and the
   environment's `HTTPS_PROXY` passed explicitly.
10. **Threshold rule:** of the rows that send every false claim to the lead and
    flag the fewest true ones, take the highest confidence, then the middle of
    the tied Noul values.

## Not done, and for the lead

- **Nothing in acceptance should depend on this yet.** The one Jev-only catch is
  a planted control, and no false claim in the set ever reached the relation
  question. The next measurement needs false claims that code cannot settle. One
  example: the fuzz reproduction with its exit code recorded, so Jev sees the
  batch that exited 134 before `0 crashes`.
- **Most flags would go away if briefs asked workers to tee every run they quote
  into a filed log**, beside a `.exit` file. Ten of the twelve true claims
  flagged are workers' runs with no raw output in the repository.
- Known code limits: an ambiguous number match can pick the wrong row (`47.2`),
  and identical summary lines from different runs pair with the first log that
  has one (step 37's four suites, where Jev's confidence fell to 0.55 and 0.43).
- Left out, and why: overnight P1 has no raw `test.mjs` output in the
  repository. The harness runners' false-success prints no summary in a fixed
  form.
