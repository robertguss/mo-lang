---
title: "Outside review, 13 Sep 2026: what to keep, revise, drop"
created: 2026-09-13
updated: 2026-09-13
type: deep-dive
tags: [philosophy, laws, meta, agents, processes, verification]
sources: [spec/design-v0, decisions/decision-log.md, plans/control-run-2.md, examples/programs/kv, toolchain/src]
confidence: medium
contested: true
---

# Outside review, 13 Sep 2026: what to keep, revise, drop

Written by an outside agent (Amp) on day two, at Robert's request, with the oracle and librarian consulted. Goal assumed: real adoption (Robert uses Mo; others build production systems in it). Evidence for every claim is in [[outside-review-2026-09-13-evidence]]; nothing below rests on reading the docs alone.

## Verdict

Mo has a real thesis and three ideas worth a language: visible authority (capabilities, no ambient I/O), isolated process state with two failure kinds, and a toolchain that treats the agent as its user (diagnostics that teach, edit-by-ID, `--json`, `--sim`). Those are worth protecting.

The parts most likely to kill adoption are not the hard parts. They are the laws copied from Tiger Style and Power of 10 that were promoted from style to semantics without measurement, and a process that lets the implementation worker set semantics by default. After one day the toolchain already contains guarantees whose meaning is "whatever made the kv example pass." That is normal for a day-old compiler. Ratifying it is the risk.

## What I agree with, and why

- **Capabilities as the only effect mechanism**
([[d15-effects-via-capabilities]], [[d31-effects-never-hide-in-a-value]]). Cheaper than effect types, visible in signatures, and the right shape for a supply-chain story. Keep, with the two holes below fixed.
- **Immutable values, local `var`, `inout`** ([[d13-local-var-and-inout]]). The
best-designed corner of Mo. Nothing hides.
- **Two failure kinds** ([[d18-two-kinds-of-failure]]). Result for weather,
crash for bugs, no try/catch. Correct and rare.
- **Processes as the only identity, bounded mailboxes, mandatory supervisors**
([[d14-processes-are-the-only-identity]], [[d33-bounded-mailboxes]]). Right shape; the *promises* around it are overbroad (below).
- **Interpreter first, C via `zig cc`, differential testing**
([[d24-compile-to-c-via-zig]], [[d25-interpreter-for-the-edit-loop]]). Sound plan; the step-13/15 parity work is the most convincing engineering in the repo.
- **`verified:` line honesty rule and the null hypothesis**
([[case-against-new-languages]], [[d28-nothing-final-until-measured]]). Writing "no language's checks caught a bug" in [[control-run-2]] instead of spinning it is the single best sign for this project.
- **Ruby-like surface, one formatter, no classes**
([[d27-simple-and-elegant-like-ruby]], [[d06-never-oop]]). Familiar syntax is an adoption asset; `mo fmt` output is already clean.

## What I disagree with, ranked by damage to adoption

### 1. Spec altitude is being asked to replace review, not organize it

[[d02-spec-altitude]] and `spec/design-v0/01-premise.md` jump from "humans read contracts" to "body review is gone." Contracts state a requirement precisely; passing tests cannot show the requirement is complete. The kv store's durability `never` checks `Step` records the implementation builds itself, including a literal `logged: true`. That is instrumentation, not independent evidence. Keep the altitude as the *default view*; drop the claim that bodies may change freely. Persistence, auth, concurrency and crypto get body review, decided by a risk rule, not by shape change.

### 2. Shape numbers as laws with no override

70/500/6/3/12 (`spec/design-v0/02-laws.md`, [[d04-style-rules-become-laws]]) are preferences promoted to semantics with zero evidence. Observed effects on day one: the six-param cap collides with "no capability fields in structs" (there is nowhere to put the seventh capability); tests share the 500-line file budget with code; "median 3 lines per function" is reported as a win when short functions are compulsory. Make them project policy with a reviewed override (`mo.toml`), keep correctness diagnostics fatal, allow advisory ones.

### 3. No `while`/`loop`

The kv server serves a connection with `for _ in 0..10_000` nested twice ("at most 100 million lines") and accepts connections the same way. The bound is fictional; the law produced noise. Worse, `fn forever(n) forever(n) end` passes `mo check` and crashes `mo run` with a raw Zig trace (exit 134): the termination story does not cover recursion at all. Separate terminating computation from long-lived service loops. Allow `loop`, bound *resources* (work per turn, allocation, queue depth), and if a total subset is wanted, make it a checked subset for contracts.

### 4. `invariant` polarity

`invariant "count never exceeds 3"  state.count <= 3` trips on count=1. The body must be true *when broken*. The word invariant has meant "stays true" for fifty years; the design's own example (`state.done < old(state.done)`) shows the strain. Flip it today while there is no compat cost; keep `never` for the negative form.

### 5. Mandatory fault injection producing vacuous tests

Under `--sim`, the model wrote `assert first is Ok(Ok(108)) or first is Ok(Error(_)) or first is Error(_)` and `heard_so_far?` accepts any error and empty conversations. Not tautologies, but tests that pass without demonstrating what their titles claim. Split fault-free functional tests from fault campaigns; under faults assert safety throughout and progress *after faults stop*, never "any error is fine."

### 6. `update` as a transaction, and restart semantics

`spec/design-v0/03-semantics.md` promises rollback; the runtime discards state writes, sends and emits, but `ask` runs the other process before returning and fs writes land before a timeout is reported. Restart clears the mailbox and reruns init, so the kv store disables restart to avoid forgetting writes. Promise local rollback only, and specify: acks, poison messages, retry limits, escalation, cleanup on crash (the kv worker sends `Leave` only on its happy path), and persistent recovery. Supervisors contain failure; they are not a storage protocol.

### 7. Handles are not capabilities

`caps.zig` classifies `Clock`/`Fs`/`Net`/`Out` as capabilities but not `Handle(T)`, so `answer(store: Handle(Store))` performs an `ask` with no capability parameter. "No capability param ⇒ pure" is false today. Also a closure passed to `map` may capture and use a capability, so "captures are read-only" does not mean "captures are effect-free." Treat handles as authority; forbid authority capture in callbacks or show it in the type.

### 8. Deadlines as literals, not budgets ([[d17-mandatory-deadlines]])

`within: 60_000.ms`, `1.minute`, `5_000.ms` on nearly every call, arbitrary and non-compositional: ten calls with fresh five-second allowances are not a five-second request. Put an absolute deadline or budget at the operation boundary; nested calls inherit and may tighten. Say what timeout means (the caller stopped waiting; the action may have happened). Sender-crash on mailbox overflow should be an overload *result* or backpressure, not a crash, for shared queues.

### 9. Recipes as security ([[d34-packages-are-recipes]], `spec/design-v0/06-packages.md`)

Regeneration removes a registry edge; it does not remove dependence on the recipe's assumptions, the model, or future security fixes, and it destroys the shared identity that lets anyone patch a bug everywhere. Every project gets a different, differently-buggy CSV parser. Keep recipes as portable specs plus conformance suites and optional generators for small glue. Defer the WebAuthn/transparency-log registry until one outsider runs one real service.

### 10. Governance: worker defaults become semantics

[[decision-log]] has many rows "ratified from Opus's default": zero-value state (Go's design, which the premise rejects elsewhere), order-sensitive map/set equality (wrong; reverse it), write-after-timeout behavior. "Robert reviews the log, not the queue" (SCHEMA agreement 8) is fine for implementation detail and dangerous for observable semantics. Add a gate: behavior touching failure, authority, equality, persistence or scheduling needs a one-paragraph record with alternatives, a counterexample, and a named approver *before* acceptance. "Provisional" needs an expiry.

### 11. Smaller items

- No default params: not load-bearing; allow pure defaults visible in the
signature.
- No catch-all on closed enums: keep, but add grouped patterns
(`A | B | C: body`) so `applied` in `kv/log.mo` stops repeating six identical arms.
- `try` cross-error by name/fields: brittle structural rule in a nominal
language. Note the kv wrappers are partly *semantic* (`Missing` becomes `NoFolder` or `Unreadable` by operation); make the translation cheap, not implicit.
- No logs + trace all args/results: a data-exposure default. Allow typed
operational logs; make tracing obey a classification policy.
- Evidence cache key (decl hash + callee contract hashes) is wrong for tests: a
callee body change without a contract change invalidates a caller's test result.
- Roc's precedent for "platform provides all I/O": after years, two platforms
matter (`basic-cli`, `basic-webserver`), platform authoring is systems work with no official guide, and every unsupported native library becomes platform work. Plan to ship every adoption-critical platform first-party and give platforms a composition story.

## Keep / revise / drop

| Decision                                  | Call                                                  |
| ----------------------------------------- | ----------------------------------------------------- |
| Capabilities, no effect types             | Keep; classify handles as authority, fix capture      |
| Immutable values, `var`, `inout`          | Keep                                                  |
| Two failure kinds, no try/catch           | Keep                                                  |
| Processes, bounded mailboxes, supervisors | Keep; rewrite the failure model                       |
| `update` as transaction                   | Revise to local rollback only                         |
| Spec altitude                             | Keep as view; drop "no body review"                   |
| Shape laws 70/500/6/3/12                  | Revise to policy with override                        |
| No `while`/`loop`                         | Drop; bound resources instead                         |
| `invariant` polarity                      | Drop; flip to "stays true"                            |
| `never` blocks                            | Keep; define observation domain                       |
| Mandatory `within:`                       | Revise to budgets                                     |
| Mandatory `test rejects` per `requires`   | Revise; accept generated/proven evidence              |
| Fault injection on every process test     | Revise; split from functional tests                   |
| No default params                         | Drop                                                  |
| No logs, trace everything                 | Revise                                                |
| Recipes                                   | Revise to specs + conformance; drop as security claim |
| Registry (WebAuthn, log, age gates)       | Defer                                                 |
| Zero-value state                          | Revise to explicit init                               |
| Order-sensitive map/set equality          | Drop                                                  |
| Interpreter + C backend + parity          | Keep                                                  |
| Null hypothesis, honest `verified:`       | Protect                                               |

## If I ran it: next five moves

1. Semantic approval gate and the polarity flip, this week, before compat baggage.
2. Write the failure model (what survives a crash, what timeout means, when a reply means durable) and test it: crash before/after write, lost reply, poison message, saturation, restart with live clients.
3. Make the assurance core fail closed: handles as authority, cache key by transitive implementations, mutation-test the `never`/`ensures` machinery with mutants that omit witnesses or return errors always.
4. Run the cancel-the-project experiment: Mo vs Go/Python under a Quasar-style subset with Mo's checks, held-out tasks, maintenance changes, independent oracles, blinded spec-only vs body review. Define the pass threshold first.
5. Pick one niche, supervised backend services, and shrink everything else: registry, first-party crypto/TLS/DB stack, autonomous production repair all wait.

## Related

- [[outside-review-2026-09-13-evidence]]
- [[case-against-new-languages]]
- [[control-run-2]]
- [[decision-log]]
- [[two-altitudes]]
- [[tiger-style-and-power-of-ten]]
