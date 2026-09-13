# 8. The interpreter milestone, and every open bet

## The milestone

Lex, parse, typecheck, and run `Payments.Refund` from chapter 4 with its tests. Contracts run at tier 2. `rejects` tests trip their `requires`. The `verified:` line is computed. No solver, no C backend, no real platform beyond `Mo.Sim`. Processes and supervisors can come in a second step, but the syntax must parse from day one.

This is where every syntax pick meets reality. What breaks gets fixed on the pick's page as a Session note, never by rewriting history.

## Session 5: the milestone is met

12 Sep 2026, four worker steps, about two hours of Opus time. `mo test examples/payments/refund.mo` lexes, parses, checks, runs six tests (three `rejects` tripping their `requires`), a property under 200 seeds, and the refund queue as a process under `Mo.Sim`, then prints the `verified:` line. All 52 corpus files behave as declared. What broke and got fixed on the way is in chapter 4's Session 5 notes and `decisions/decision-log.md`. No solver, no C backend, `sim (not run)` until fault injection exists.

## First tested by

Every provisional decision from session 3, and what tests it.

| Bet | First tested by |
|---|---|
| Anonymous functions are call-arguments only (d31) | the example corpus: how often an agent wants a stored closure |
| Loops without invariant syntax | tier 3 small-model checking on the corpus |
| Unbounded integers in contracts, sized in bodies | the tier-2 contract runtime, then the tier-3 proof rate |
| Tier 3 v0 is testing, proving is `mo prove` (d32) | how far property tests and simulation get before anyone misses a prover |
| Bounded mailboxes, sender crashes (d33) | `Mo.Sim` with a slow consumer |
| Zig, and its incremental build claim | the toolchain's own rebuild time |
| Packages as recipes (d34) | three recipes (rate limiter, JWT, CSV) implemented by agents: token cost, defects against the recipe's tests, attempts to exceed `needs` |
| The stdlib ceiling | stdlib misses on programs 2 and 4 of the menu |
| Law numbers (70, 500, 6, 3, 12) | lines-per-function distribution on the corpus |
| 50 ms and 100 ms targets | the benchmark suite, from day one |
| Spec altitude is readable | a timed reading study on program 1 |

## The control run

On the program menu, agents writing Mo against agents writing Go or TypeScript with the same checks bolted on (contracts via a verifier, tests, linters). Measured: time to green, defects found later, human review minutes, total token cost including spec and diagnostics. And a Quasar-style control: Mo's checks over a Go or Python subset. If the subset wins, that changes the project.

## Open questions, not yet asked

Held for after the milestone, one at a time: supervisor strategies and escalation; flow narrowing into refinement types; a linear resource kind; copyable capabilities; a spec-only contract kind for `never` clauses too costly to run; restart from `init` or from the last committed state; hot reload in development; a compatibility promise at v1; two versions of one recipe in a program; `forbid reaches(A, B)` as the general form of `flows`.
