---
title: "Program menu: what we build to put Mo through its paces"
created: 2026-09-12
updated: 2026-09-17
type: plan
tags: [roadmap, performance, agents]
sources: [raw/notion/open-questions-2026-09-12.md]
status: done
---

# Program menu: what we build to put Mo through its paces

Robert (session 2, on [[q14-first-real-program|Q14]]): one program is not enough; build a variety of kinds to find Mo's strengths and weaknesses and collect real data to improve the language. This is the measurement engine behind [[d28-nothing-final-until-measured|direction 28]].

## The menu, in rough order

| # | Program | Stresses | Measures |
|---|---|---|---|
| 1 | Durable job queue + HTTP API | processes, supervision, deadlines, `never` | the founding premise: agent builds it, Robert reads at spec altitude |
| 2 | CLI tool (log analyzer) | pure code, stdlib, single binary | stdlib gaps; is Mo pleasant with no concurrency? |
| 3 | KV store with a wire protocol | bytes, sized ints, hot loops | runtime speed, overflow-check cost ([[q04-integer-types-and-overflow|Q4]]), C backend |
| 4 | Web backend ("with Postgres" as proposed; built as `notes` over `Fs`, no database brick yet, [[program-4]]) | package story, capability-scoped deps | [[q17-package-management-and-supply-chain|Q17]] in practice; stdlib misses |
| 5 | Agent harness (tools, budgets, retries) | capabilities as permissions, deadlines | is Mo good at the thing it is for? |
| 6 | Payments ledger with invariants | `never`, contracts, SMT tier, fault injection | proof rate, tier-3 timings ([[q08-verification-tiers|Q8]]) |
| 7 | The Mo toolchain itself (late; program 8 on the [[roadmap]], where program 7 is a Redis subset against Redis's own tests) | everything, at scale | compile speed on 100K lines ([[d23-compile-speed-first-class|direction 23]]) |

## Collected on every program

- build time per KLOC; incremental rebuild latency
- agent loops-to-green per task
- contract and proof density; `verified:` line over time
- lines-per-function distribution (tests the 70-line law, [[q12-law-numbers|Q12]])
- crash reports per KLOC and time-to-autonomous-fix ([[d21-autonomous-crash-fixing|direction 21]])

## Related
- [[roadmap]]
- [[q14-first-real-program]]
- [[d28-nothing-final-until-measured]]
