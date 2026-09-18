---
title: "Reliability and testing philosophies"
created: 2026-09-13
updated: 2026-09-18
type: concept
tags: [research, verification, tooling]
sources: [raw/research-runs/2026-09-13-manifestos-safety-reliability.pplx.md]
confidence: high
---

# Reliability and testing philosophies

The testing traditions that high-reliability teams actually run: deterministic simulation, reachability assertions, adversarial black-box checking, coverage regimes, let-it-crash, property-based testing, error budgets, mutation testing, and structured concurrency. Read alongside [[tiger-style-and-power-of-ten]] and the rulebook standards, which cover rules rather than harnesses.

## Deterministic simulation is a language property

FoundationDB got determinism by writing Flow, a C++ extension with a single-threaded deterministic actor model, then simulating a whole cluster in one process ([FDB SIGMOD 2021](https://www.foundationdb.org/files/fdb-paper.pdf)). Simulation runs about ten times faster than real time, with "roughly one trillion CPU-hours of simulation" accumulated ([FoundationDB testing](https://apple.github.io/foundationdb/testing.html)).

BUGGIFY marks code locations where the simulator may inject unusual-but-legal behaviour — delays, reorderings, errors, pathological parameters — biasing runs toward rare paths ([FDB SIGMOD 2021](https://www.foundationdb.org/files/fdb-paper.pdf)). Swarm testing varies configuration between runs, and `TEST()` macros record whether an interesting situation was ever reached ([FDB SIGMOD 2021](https://www.foundationdb.org/files/fdb-paper.pdf)).

The authors state the limits against their own technique: "Simulation is not able to reliably detect performance issues", and it is "unable to test third-party libraries or dependencies, or even first-party code not implemented in Flow" ([FDB SIGMOD 2021](https://www.foundationdb.org/files/fdb-paper.pdf)).

Judgment: Mo's mandatory deadlines are exactly the property `--sim` cannot validate.

## Sometimes assertions answer the vacuous-test problem

An assertion that a bad state never occurs passes trivially when nothing happens. Antithesis invert it: "code coverage only covers locations, while sometimes assertions cover situations" ([Antithesis](https://antithesis.com/docs/best_practices/sometimes_assertions/)). Their vocabulary is `always`, `alwaysOrUnreachable`, `reachable`, `unreachable` and `sometimes`, with properties keyed by message so a named property is tracked across runs ([Antithesis](https://antithesis.com/docs/properties_assertions/assertions/)).

Checkpointing amplifies rare conjunctions: two independent one-in-a-thousand situations are unreachable by waiting, but snapshot-and-replay drives them ([Antithesis](https://antithesis.com/docs/best_practices/sometimes_assertions/)). The fetched pages do not use the terms safety and liveness — n.a.

Judgment: the fix for Mo's vacuous-fault-injection dispute is not to make injection mandatory but to make reachability obligations mandatory for injected tests, and to fail the run when a declared obligation is never observed across N seeds.

## Adversarial checking finds history bugs, not state bugs

Jepsen's stated trade: "Bugs reproduced in Jepsen are observable in production, not theoretical. However, we sacrifice some of the strengths of formal methods: tests are nondeterministic, and we cannot prove correctness, only find errors" ([Jepsen analyses](https://jepsen.io/analyses)).

The framing worth stealing: "A consistency model is a safety property which declares what a system can do" ([Jepsen consistency](https://jepsen.io/consistency)).

Elle infers Adya-style dependency graphs from observed histories and detects G0, G1a, G1b, G1c, G-single, G2 and G2-item anomalies plus dirty updates and garbage reads; "Elle revealed anomalies in every system we tested", and "Almost all of these anomalies were previously unknown" ([Elle, VLDB](http://www.vldb.org/pvldb/vol14/p268-alvaro.pdf)).

## Coverage regimes fight contracts

SQLite reports 155.8 KSLOC of core against 92,053.1 KSLOC of test code, with four independent harnesses: TCL cases, TH3 at 100% branch and 100% MC/DC, SQL Logic Test differential queries, and dbsqlfuzz at roughly one billion mutations per day ([How SQLite Is Tested](https://www.sqlite.org/testing.html)).

The conflict they documented is the one Mo will hit: "MC/DC testing discourages defensive code with unreachable branches, but without defensive code, a fuzzer is more likely to find a path that causes problems" ([How SQLite Is Tested](https://www.sqlite.org/testing.html)).

Their resolution is a three-build macro. A condition wrapped in `ALWAYS()` or `NEVER()` is an assertion in debug builds, a constant in coverage builds so the unreachable branch is excluded, and the plain condition in release ([SQLite assert](https://sqlite.org/assert.html)). They also warn that "An assert(X) should not be seen as a safety-net", and disable assertions in release because leaving them on costs about a threefold slowdown ([SQLite assert](https://sqlite.org/assert.html)).

Judgment: JPL went the other way, leaving assertions enabled in flight and wiring them to fault protection ([Mars Code](https://cacm.acm.org/research/mars-code/)). Both are right for their failure model. Mo should follow JPL and record why.

DO-178's discipline is the complement: coverage is measured while running requirements-based tests, and unexercised code is then classified, with dead code removed and deactivated code shown disabled ([NASA MC/DC tutorial](https://ntrs.nasa.gov/api/citations/20010057789/downloads/20010057789.pdf)). MC/DC needs a minimum of n+1 tests for n conditions ([NASA MC/DC tutorial](https://ntrs.nasa.gov/api/citations/20010057789/downloads/20010057789.pdf)).

## Let it crash, with a budget

Armstrong's slogans: "Let some other process do the error recovery. If you can't do what you want to do, die. Let it crash. Do not program defensively." ([Armstrong thesis](https://www.cs.otago.ac.nz/cosc441/armstrong_thesis_2003.pdf)).

The operational half is restart intensity. With `{one_for_one,5,1000}`, "if the supervisor has to restart the processes which it is monitoring more than 5 times in 1000 seconds then it itself will fail" ([Armstrong thesis](https://www.cs.otago.ac.nz/cosc441/armstrong_thesis_2003.pdf)).

```ruby
# Restart intensity is an error budget:
#   quantity = restarts, window = 1000s, action on exhaustion = escalate
```

### The nine nines, corrected

Armstrong's own record of the AXD301 figure: "the only information on the long-term stability of the system came from a power-point presentation showing some figures claiming that a major customer had run an 11 node system with a 99.9999999% reliability, though how these figure had been obtained was not documented" ([Armstrong thesis](https://www.cs.otago.ac.nz/cosc441/armstrong_thesis_2003.pdf)).

Mats Cronqvist, who worked on the system, states: "The customer (British Telecom) claimed nine nines service availability integrated over about 5 node-years." He adds "As far as I know, no one in the AXD 301 project claimed that this was normal, or even possible", that "the claim is pretty bogus", and "For the record, Joe Armstrong was not part of the AXD 301 team" ([Cronqvist, Erlang Factory 2010](https://www.erlang-factory.com/upload/presentations/243/ErlangFactorySFBay2010-MatsCronqvist.pdf)). He still holds that "the system was very reliable" but notes "I have been unable to find any publicly available reference to this" ([Cronqvist](https://www.erlang-factory.com/upload/presentations/243/ErlangFactorySFBay2010-MatsCronqvist.pdf)).

Judgment: cite the practice, never the number. The defensible claim is the scale — 1,136,150 lines across 2,248 modules with 191 OTP behaviour instances, by 40-plus programmers over 4 years ([Armstrong thesis](https://www.cs.otago.ac.nz/cosc441/armstrong_thesis_2003.pdf)).

## Generate the tests, then shrink the failure

QuickCheck writes properties as ordinary functions with generation under the tester's control ([QuickCheck](https://www.cs.tufts.edu/~nr/cs257/archive/john-hughes/quick.pdf)). The industrial result: 20,000 lines of QuickCheck against "around 3,000 pages of PDFs" of AUTOSAR spec, testing "a million lines of C code ... from 6 different suppliers, finding more than 200 problems—of which well over 100 were ambiguities or inconsistencies in the standard itself!" — an order of magnitude smaller than the TTCN3 suite ([Experiences with QuickCheck](https://www.cs.tufts.edu/~nr/cs257/archive/john-hughes/quviq-testing.pdf)).

Shrinking is "extracting the signal from the noise" ([Experiences with QuickCheck](https://www.cs.tufts.edu/~nr/cs257/archive/john-hughes/quviq-testing.pdf)). Hypothesis makes it universal with an internal representation that allows reduction without user intervention ([Hypothesis, JOSS](https://joss.theoj.org/papers/10.21105/joss.01891.pdf)).

Judgment: a raw failing `--sim` seed is useless to an agent. Design the schedule-plus-fault-list as a canonical reducible artifact before the simulator exists.

## Budgets and perturbation

"An error budget is 1 minus the SLO" ([Error budget policy](https://sre.google/workbook/error-budget-policy/)), with changes causing roughly 70% of outages and a stated halt clause when the budget is exhausted over a four-week window ([Error budget policy](https://sre.google/workbook/error-budget-policy/)). The premise is that 100% is the wrong target: "a user on a 99% reliable smartphone cannot tell the difference between 99.99% and 99.999%" ([Embracing Risk](https://sre.google/sre-book/embracing-risk/)).

Chaos engineering's principles are to hypothesise about steady-state behaviour, vary real-world events, run in production, automate continuously, and minimize blast radius ([Principles of Chaos](https://principlesofchaos.org/)).

## Mutation testing is contested

Just et al. found a statistically significant correlation between mutant detection and real fault detection across 357 real faults, holding when coverage was controlled, while noting 27% of faults were not coupled to any mutant ([Just et al., FSE 2014](https://dada.cs.washington.edu/research/tr/2014/02/UW-CSE-14-02-02.PDF)).

Papadakis et al. found correlations of 0.35 to 0.75 collapsing to roughly 0.05 to 0.20 once suite size was controlled, concluding that mutants as substitutes for real faults "can be problematic" while still "helpful, to testers for improving test suites" ([Papadakis et al., ICSE 2018](https://orbilu.uni.lu/bitstream/10993/34950/1/ICSE-main18b%20(1).pdf)).

Judgment: good instrument for improving a suite, bad instrument for grading one. Scope it to mutating Mo's contract machinery.

## Structured concurrency and inherited budgets

"Go statements are a form of goto statement" and "Go statements break abstraction"; a nursery block "doesn't exit until all the tasks inside it have exited" ([Notes on structured concurrency](https://vorpus.org/blog/notes-on-structured-concurrency-or-go-statement-considered-harmful/)). Kotlin requires a `CoroutineScope`, parents wait for children, and a child failure cancels siblings ([Kotlin coroutines](https://kotlinlang.org/docs/coroutines-basics.html)).

Go's contexts form a tree in which cancellation propagates, with the convention to "pass a Context parameter as the first argument to every function on the call path" ([Go context](https://go.dev/blog/context)). gRPC says "TL;DR: Always set a deadline" and distinguishes a deadline as a point in time from a timeout as a duration ([gRPC and Deadlines](https://grpc.io/blog/deadlines/)); that page does not state cross-service propagation or budget subtraction — n.a.

Judgment: combined with Ravenscar's ban on relative delays, the evidence favours an absolute deadline established once and inherited, where a nested `within:` may tighten and never extend.

## What Mo could take

| idea | maps to | status |
|---|---|---|
| Determinism designed into the runtime, not the harness | [[q08-verification-tiers]] | already in Mo |
| BUGGIFY-style biased injection of legal-but-rare behaviour | [[q08-verification-tiers]] | new idea for Mo |
| Swarm testing across configurations | [[q08-verification-tiers]] | new idea for Mo |
| Reachability obligations required for fault-injection tests | [[d19-negative-space-is-the-contract]] | strengthens Mo |
| Never claim simulation validates latency | [[d17-mandatory-deadlines]] | strengthens Mo |
| History-level properties across processes | [[d14-processes-are-the-only-identity]] | new idea for Mo |
| Contract branches excluded from coverage denominators | [[d19-negative-space-is-the-contract]] | new idea for Mo |
| Harness diversity over one very large suite | [[q08-verification-tiers]] | strengthens Mo |
| Restart intensity as an escalating budget | [[d18-two-kinds-of-failure]] | strengthens Mo |
| Drop the nine-nines claim from Mo's materials | [[d08-beam-qualities-without-the-beam]] | contradicts Mo |
| Model-based state-machine properties at process level | [[d19-negative-space-is-the-contract]] | new idea for Mo |
| Shrinking as a first-class part of `--sim` | [[q09-compiler-diagnostics]] | new idea for Mo |
| Deadlines inherited and tightened, not restated per call | [[d17-mandatory-deadlines]] | contradicts Mo |
| Mutation testing scoped to contract machinery only | [[d28-nothing-final-until-measured]] | strengthens Mo |

17 Sep 2026: two rows are settled. The nine-nines row was ruled **agree** on 13 Sep (Mo's materials cite Erlang's scale, never the number), and the inherited-deadlines row is no longer a contradiction — the derived deadline shipped at step 22. See [[research-agenda-2026-09-response]].

17 Sep 2026: the only other change today was adding the Hermes link below.

## Related

- [[hermes-daily-2026-09-18]] — Hermes follow-up on TLS state-sequence coverage and oracle semantics.

- [[hermes-daily-2026-09-17]] — Hermes follow-up on storage crash consistency and capability API boundaries.

- [[tiger-style-and-power-of-ten]]
- [[q08-verification-tiers]]
- [[errors-and-failure]]
- [[d19-negative-space-is-the-contract]]
- [[d17-mandatory-deadlines]]
- [[prompts-research-agenda-2026-09]]
- [[author-joe-armstrong]]
- [[research-agenda-2026-09-response]]
