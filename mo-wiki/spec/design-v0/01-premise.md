# 1. Premise

## The world Mo is for

- Agents write nearly 100% of the code. Humans no longer write or closely review bodies.
- Humans still read. They read intent, contracts, effects, and what the toolchain has verified. That layer is the **spec altitude**. Bodies are the **implementation altitude**, collapsed by default.
- Since review is gone, trust comes from what the compiler and the runtime can check, not from what a person promised. The source carries its own evidence.
- Every third-party package is code nobody read. The supply chain is the largest attack surface a program has, and an agent that installs what it needs makes it larger.

## The thesis (session 6, 14 Sep 2026)

Mo exists so that software written by agents is reliable, and needs no third-party code. Three layers deliver that, in the order of how much they carry:

1. **The runtime and the process model.** Isolated processes, each an Elm-shaped state machine, supervised; a failure model that says what a crash discards, what a timeout leaves, what a restart loses, and when a reply is durable (chapter 3); a deadline on every wait, a bound on every mailbox, an overflow that is a bug; a ring of structured runtime events and a runtime surface an agent can query and, with the capability, act on (directions 37 and 40). This is where reliability comes from, and it is what no existing language can be retrofitted with.
2. **Capabilities, and recipes as the package shape.** Authority is a parameter: a function is pure unless it takes a capability, a process holds only what it was started with, and nothing enters a program that `main` did not hand it, so a package's authority is visible at install and provable at compile time (chapter 6). A recipe is a package at spec altitude, its bodies generated and checked against its tests; a brick is audited platform code. This is where zero dependencies comes from.
3. **The language.** Its job is to expose the first two at spec altitude so a human can read the contracts, the `never` clauses, the `invariant`s, and the `verified:` line without reading bodies, and so an agent gets a diagnostic instead of a bug. Functional and procedural, no classes; immutable values with `var` and `inout` and no aliasing; static types declared at every boundary and inferred inside; two kinds of failure that never cross, an expected failure as a value and a bug as a crash; one static binary; a formatter with one answer. The syntax is Elixir-shaped (`end`-closed blocks, `?` predicates, dot-call sugar) under Ruby's taste, and spends novelty only where the semantics need it.

The language is not the thesis; it is the surface of the thesis. The language makes the runtime's guarantees visible in the source; the runtime makes the language's guarantees observable at run time. Mo's bet is that agents write better systems when the machine and its source share one vocabulary. A law belongs in the language when it removes a class of bug (bounded loops and waits, sized integers, consumed results, no escape from an error into a handled outcome, capabilities that cannot be forged). A rule that counts lines is a project setting with a default, not a law (session 6, after round 6 and the outside review of 14 Sep).

## What is measured

Nothing here is final until measured (direction 28). The claim under test is a conjunction: reliability at zero dependencies. The baselines run with the strongest checks their ecosystems offer, bought with packages and tools; Mo must match them on defects while needing none of it, and a baseline that is as reliable at zero run-time dependencies refutes the reliability claim, not the dependency one (Robert, 15 Sep 2026; decision log). The control run (chapter 8) predicts, in this order: how many defects a hidden adversarial suite finds in the finished program; how fast the program runs and how much memory it holds, native, against Go and Python; how fast the loop is from an edit to a verdict; and how many third-party packages and tools the program needs. How long an agent takes to write Mo is recorded, not predicted: no model has seen Mo in training, and that cost is expected and not the point (Robert, 14 Sep 2026).

## The null hypothesis

The null hypothesis, on the thesis as restated: the BEAM with Elixir already gives most of Mo's runtime advantages (isolated processes, supervision, a mailbox per process, hot code loading, a live shell into a running system), and the delta Mo adds (static types at every boundary, capabilities that cannot be forged, a deadline on every wait, one static binary, no package ecosystem to trust, an agent-facing runtime surface) does not justify a new language. This is the objection an OTP reader raises first, and it is the one program 7 must answer: a long-running service with a capability-scoped supply chain, measured against an Erlang or Elixir counterpart on reliability under a hidden defect suite, speed and memory, the loop, and dependencies. If the delta does not show there, that result changes the project.

What "does not show" means is written down before program 7 exists. On 17 Sep 2026 Robert ratified three stopping rules, drafted by an independent auditor that reads the raw evidence and never the lead's reading ([`audit/README.md`](https://github.com/robertguss/mo-lang/blob/main/audit/README.md)): one for the runtime layer (five reliability rows and four cost rows against Elixir on program 7, with the retirements S-A, S-B, S-C named in advance), one for capabilities and recipes (zero dependencies, recipe drift, capability escapes, maintenance time, with T-A, T-B, T-C), and one for the language layer's catch claim below (read at erosion generation ten). The lead and the auditor each read the evidence alone, and Robert reads both.

## The language layer's own null hypothesis, and what six rounds said

Agents might do as well in an existing language with Mo's checks bolted on. Rounds 1 to 6 of the control run tested the language layer on that question, with agent time and loops as the measure, and round 6 (the same job queue in Go with vet, staticcheck, and contracts, and in Python with mypy, ruff, and pydantic) found that no check in any language caught a bug the tests missed, and the baselines cost less to write. On that measure the null hypothesis stands. What those rounds did not test is the runtime and the capability layers, because logstat and a job queue exercise neither; from round 7 the measure is the one above, and program 7 is chosen to depend on capabilities, recipes, and the runtime surface. If a program built on those layers is no more reliable, no faster, and no leaner in dependencies than its Go or Erlang counterpart, that result changes the project. Its stopping rule is the third audit file above: unless `never` and `invariant` have caught at least two Mo defects no test would have caught by generation ten, at a false-positive rate of at most 1.5 times the catches and at most 5 per 1,000 lines, they leave the claim and stay in the language as tools (R-B).

## Session 6 changes

- **The thesis restated** (Robert, 14 Sep 2026, on the outside review of the same day, and its reply that named the BEAM null hypothesis and the one-sentence thesis): the runtime, then capabilities and recipes, then the language as their surface; the counted shape laws become project settings; the control run's measure is reliability, speed, the loop, and dependencies. The earlier premise, "agents do better with the compiler as teacher", is kept as one hypothesis inside the third layer, with rounds 1 to 6 as its evidence so far.

## Session 10 changes

- **The stopping rules linked** (Fable, 17 Sep 2026, on Robert's installation of the auditor role the same day): the null hypothesis sections now point at the three ratified rules in `audit/`; the thesis itself is unchanged.
