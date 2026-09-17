---
title: "Tiger Style + Power of 10, rethought AI-first"
created: 2026-09-12
updated: 2026-09-17
type: deep-dive
tags: [laws, philosophy]
sources: [raw/notion/design-journal-2026-09-12.md]
---

# Tiger Style + Power of 10, rethought AI-first

**Key move:** both documents are style guides enforced socially by review. Review is gone. So *every style rule becomes a language rule enforced by the compiler.*
**Become laws of Mo (compiler-enforced):**
- No unbounded loops. No `while true`. Loops iterate finite collections or carry an explicit bound in the signature.
- No general recursion. Only structural recursion the compiler proves terminates. Totality by default.

  17 Sep 2026: not what Mo did — chapter 2 bounds recursion at depth 10,000 and then crashes; termination is `mo prove`'s job, not the compiler's.
- Hard function length limit: 70 lines, a `mo.toml` setting since 14 Sep. Also a context-window-sized unit of agent work.
- Minimum contract density: a function with no `requires`/`ensures` does not compile.
- No compound asserts. A failure always names one property.
- Exhaustive error handling. Every result consumed. No exceptions.
- No default parameters. All options explicit at call site.
- No warnings, only errors.
- Explicitly sized types only.
- Positive and negative space tests are part of the unit; compiler checks both exist per precondition.
**Die (served human eyes):** column limits, indent width, symmetric name lengths, file order, brace style. Canonical formatter, no choices.
**Promoted into bigger features:**
- "Motivate decisions" → structured provenance field linking to requirement and conversation.
- "Performance sketching" → declared resource budgets in the signature (latency, memory, allocations), checked by compiler/simulator.
- "Paired assertions" → type invariants auto-checked at every boundary (create, serialize, deserialize).
- Deterministic simulation testing → default runtime model. Every program deterministic under a seed. Failing assertion + seed = complete, reproducible bug report for an agent.
- Static allocation after startup → powerful but domain-constraining; parked until first-program decision.
Sources: [Tiger Style](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md), [The Power of Ten](https://spinroot.com/gerard/pdf/P10.pdf)

## Related
- [[d04-style-rules-become-laws]]
- [[d05-old-ideas-rethought-ai-first]]
- [[q12-law-numbers]]
- [[p11-loops-and-anonymous-functions]]
- [[p12-tests]]
