---
title: "Outside review, 13 Sep 2026: Fable's response and the baselines"
created: 2026-09-13
updated: 2026-09-13
type: deep-dive
tags: [meta, laws, processes, verification, roadmap]
sources: [deep-dives/outside-review-2026-09-13.md, deep-dives/outside-review-2026-09-13-evidence.md, decisions/decision-log.md, plans/control-run-3.md]
confidence: medium
contested: true
contradictions: [outside-review-2026-09-13]
---

# Outside review, 13 Sep 2026: Fable's response and the baselines

Fable read [[outside-review-2026-09-13]] and its evidence the afternoon it landed, re-ran three of its probes on the toolchain after step 17 (recursion still exits 134 with a Zig trace; a closure still writes through a captured `Out` and the dropped `map` value is not flagged; the grammar has no grouped patterns), and made the calls below. Robert's decision the same hour: the laws and the no-`while` rule stay as they are, "we need to test and see what happens and can reevaluate later", and every finding and decision is documented so the numbers serve as baselines.

## The calls

| review item | Fable's call | where |
|---|---|---|
| `invariant` polarity | agree; flip to "stays true" now, no compat cost | step 18 |
| handles are not capabilities; capture in closures | agree; `Handle(T)` is authority, capture refused | step 18 |
| recursion crashes with a Zig trace | agree; a depth limit and a Mo crash report | step 18 |
| grouped patterns | agree | step 18 |
| map and set equality by order | agree; by content | step 18 |
| the sidecar's cache key | agree; transitive bodies | step 18 |
| vacuous fault tests | agree; `--faults --until F`, then rewrite kv's | step 18, program 4 |
| self-reported `never` witnesses | agree; mutation-test the contract machinery | a later step |
| `update` as a transaction; the failure model | agree the promise overreaches; Fable writes the failure model | before program 4's `--sim` claims |
| deadlines as budgets | agree; program 4's experiment | program 4 |
| governance of worker defaults | agree in part: a `semantic` tag and an expiry, not an approver before acceptance | the log, from step 18 |
| shape laws as policy with an override | disagree; Robert: stay, measure | control runs |
| no `while` | disagree; rows that drive their own loops first; Robert: stay, measure. Program 4 made it three programs with a fictional bound; Robert (evening) chose the runtime owning the loop over a `loop` keyword | [[interpreter-step-20]] |
| default parameters | Robert rejected them on sight; stays | — |
| recipes as security | the review says what direction 34 says: unproven; program 4 tests it | program 4 |
| spec altitude replacing review | agree on a risk rule for persistence, auth, concurrency; the altitude stays the default view | the failure model |
| Roc's platform precedent | agree; Mo.Server ships first-party and so will the rest | roadmap |

## The baselines on the day of the review

These are the numbers a later re-evaluation compares against.

| measure | value |
|---|---|
| control run round 3, loops to green | Mo 9 (6 syntax diagnostics, 1 real bug, 2 test mistakes), Go 2, Python 1 |
| control run round 2, wall-clock | Mo 11.8 min, Go 8.2, Python 7.9 (round 3's timing void, the machine slept) |
| checks that caught a real bug, all rounds | Mo 2 (round 3: a test, a `never`), Go 0, Python 0 |
| lines per function, round 3 | Mo median 6 (bodies 4), Go 9.5, Python 5 |
| program and test lines, round 3 | Mo 851, Go 1,387, Python 1,064 |
| corpus | 66 modules and programs, 142 files under test, suite 22 s |
| native against interpreted | logstat 5×, kv GETs 1.4×, echo 1.5×, http 1.7× |
| kv after 50k SETs | 19.2 MiB native, 37.4 interpreted |
| decision-log rows | 218, of which 4 overturned |

## What changes because of the review

Step 18 ([[interpreter-step-18]]) makes the no-compat fixes. The decision log gains the `semantic` tag. Fable writes the failure model before program 4's simulation claims are read. Program 4 tests budgets and recipes. The laws are re-evaluated after round 4 of the control run, against this page.

## Related
- [[outside-review-2026-09-13]]
- [[outside-review-2026-09-13-evidence]]
- [[interpreter-step-18]]
- [[control-run-3]]
- [[decision-log]]
- [[roadmap]]
