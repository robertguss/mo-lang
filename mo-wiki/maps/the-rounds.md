---
title: "The rounds and the measurements"
created: 2026-09-16
updated: 2026-09-17
type: map
tags: [research, agents]
sources: [index.md, plans/roadmap.md, decisions/decision-log.md]
status: living
---

# The rounds and the measurements

Every experiment the project has run, in one table, with its verdict and the page that holds it. The measure changed on 14 Sep: rounds 1 to 6 timed agents; from round 7 the reading is reliability, speed and memory, the loop, and dependencies. See [[state-of-the-project]] for what it adds up to.

| round | date | task | languages | what it read | verdict | page |
|---|---|---|---|---|---|---|
| 1 | 12 Sep | logstat from its spec | Mo, Go, Python | agent time | Mo 25.5 min, Go 12.9, Python 8 | [[control-run]] |
| 2 | 13 Sep | the same, on the day's toolchain | Mo, Go, Python | agent time | Mo 11.8 min, zero failed runs | [[control-run-2]] |
| 3 | 13 Sep | the same, after steps 14 to 16 | Mo, Go, Python | loops by cause | Mo 9 loops (one real bug caught by a test and a `never`), Go 2, Python 1 | [[control-run-3]] |
| 4 | 13 Sep | the same, after steps 17 to 20 | Mo, Go, Python | agent time, loops | Mo 16.1 min, Go 9.3, Python 9.0; the laws kept | [[control-run-4]] |
| 5 | 13 Sep | the same, pre-registered | Mo, Go, Python | three predictions | two held, one missed by a loop; Mo 1.28 times Go's time | [[control-run-5]] |
| 6 | 14 Sep | logstat and jobq, with every check bolted on | Mo, Go, Python | four predictions | failed on all four; no check caught a bug in any language; three laws removed by step 27 | [[control-run-6]] |
| 7 | 14 Sep | the job queue, on Robert's measure | Mo, Go, Python | reliability, speed, loop, dependencies | held on all four: 0 defects each, Mo 981 pairs a second to 478 and 467, loop 0.38 s to 18.7 and 8.7 | [[control-run-7]] |
| 8 | 15 Sep | change 1 to round 7's queues by fresh maintainers | Mo, Go, Python | five predictions, two hidden suites | held on all five; the fourth oracle found Mo's outage; no check caught a change-induced bug | [[control-run-8]] |
| 10 | 15 Sep | round 7's queue and change 1 in Elixir | Elixir | the BEAM null hypothesis | 2 defect causes, twice Mo's speed, 0 run-time dependencies; P6 the BEAM's | [[control-run-10]] |
| 9 | 16 Sep | change 1 by smaller models in Pi | kimi-k3, deepseek-v4-flash, gpt-5.5, qwen 27B, Haiku 4.5 | reliability and loops per model | reliability moves with the model on the Mo side only; the diagnostics carry small models to green; the local 27B made no edit | [[control-run-9]] |
| measurement 1 | 15 to 16 Sep | every program regenerated from its stripped spec, twice | Mo | completeness | twelve of twelve at 1.0; with tests deleted too, 0.74 under the original tests | [[bodies-as-cache]] |
| measurement 2 | 15 Sep | the queue's board regenerated five times, compared | Mo | agreement over 132,000 operations | identical except one impossible record | [[sampling-as-verification]] |
| erosion, generation 2 | 16 Sep | change 2 to all four queues by fresh maintainers | Mo, Go, Python, Elixir | regressions, a third suite, a fourth oracle, P6 | nothing eroded in Mo, Go, Python; Elixir refuses a torn line and cannot restart after a full disk; the deferred reply used | [[erosion-round]] |
| erosion, generation 3 | 16 Sep | change 3, the store restarts itself | Mo, Go, Python, Elixir | a fourth suite, P6 | Mo 55, Go 55, Python 55, Elixir 53 of 55; the Mo queue killed under load back in 106 ms | [[erosion-round]] |
| erosion, generation 4 | 16 Sep | change 4, idempotent creates and the archive | Mo, Go, Python, Elixir | a fifth suite, the speed row | Mo 77, Python 77, Go 76, Elixir 76 of 77; the Mo queue nine times slower on the lease path | [[erosion-round]] |
| erosion, generation 5 | 16 Sep | change 5, a lease handed off and a rename in flight | Mo, Go, Python, Elixir | a sixth suite, speed per generation | Python 94, Elixir 94, Go 92, Mo 93 of 94: the first Mo-only defect; no `never` tripped | [[erosion-round]] |
| the scaling run | 15 Sep | step 30 at 1, 4, 10, 14 cores on the M3 Max | Mo | throughput per core count | nothing scales; every row fastest at 1 core | [[mac-scaling-run]] |
| the model bake-off | 12 Sep | the corpus brief by Opus, Grok, and Codex | Mo | the corpus each produced | on branches `corpus-grok` and `corpus-codex` | [[model-bakeoff]] |

## The instruments

The suites and probes live beside their plans and are never shown to a worker: `control-run-7-suite/` (the 121-check defect suite and the measure), `control-run-8-suite/` (regressions, change 1's defects, the fourth oracle), `control-run-10-suite/` (`p6.py`), `control-run-9-suite/` (the briefs, the paced Python runner), `sampling-as-verification-suite/`, `bodies-as-cache-suite/` (the stripper and the verifier), `erosion-round-suite/` (the third suite with its RAM disk, the fourth oracle), `interpreter-step-30-suite/` (the Mac run).

## The programs the rounds run on

[[program-1]] (the job queue) is the round 7 to 10 program; [[program-2]] (logstat) the round 1 to 6 program; the change specs are [[01b-job-queue-change]] and [[01c-job-queue-change-2]]. See [[the-programs]].
