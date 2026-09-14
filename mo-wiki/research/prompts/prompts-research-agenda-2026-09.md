---
title: "Research agenda, Sep 2026: recent papers, language authors, and the manifestos beyond Tiger Style"
created: 2026-09-13
updated: 2026-09-13
type: concept
tags: [research, philosophy, roadmap]
sources: [deep-dives/research-summary-2026-09.md, deep-dives/steal-list.md, deep-dives/outside-review-2026-09-13-response.md]
status: open
---

# Research agenda, Sep 2026: recent papers, language authors, and the manifestos beyond Tiger Style

Written by Perplexity Computer at Robert's request on 13 Sep 2026, after reading the whole vault. Three themes Robert asked for: the latest academic research that bears on Mo, the ethos and decisions of the people who designed Mo's ancestor languages, and the coding standards and engineering philosophies that sit beside Tiger Style and the Power of Ten. Six independent runs; each is one prompt set below, each lands as one `raw/research-runs/` file and one or more `research/concepts/` pages, and any run can be fired alone.

## Why these gaps

The vault is deep on emerging languages (thirteen comparisons), on capability and effect papers, on LLM plus Dafny and SPARK, and on supply chain. It is thin on the people and the standards. Before this agenda, Thompson appeared in two pages, Armstrong in one, and Dijkstra, Wirth, Matz, Hickey, Meyer, Parnas, Lamport, Alloy, FoundationDB, Antithesis, JPL's full standard, MISRA, "Reflections on Trusting Trust", the Go proverbs, and the Zen of Zig in none. Those are the primary sources for the laws in chapter 2, so [[d05-old-ideas-rethought-ai-first|direction 5]] has been arguing from second-hand summaries.

## The six runs

| run | contents | what it feeds |
|---|---|---|
| R1 papers, LLM-facing | agents writing contracts and proofs, autoformalization, agent–compiler loops, constrained decoding, agent test generation, AST editing; token efficiency, cold start, strictness vs bugs, human review of agent code | [[q08-verification-tiers|Q8]], [[q09-compiler-diagnostics|Q9]], [[d29-edit-by-declaration-id|d29]], the null hypothesis, the control runs |
| R2 papers, semantics and runtime | capability and effect systems, second-class values, refinements with SMT, totality, session types, MVS; simulation and replay, Perceus and regions, per-process heaps, backpressure, incremental compilers | [[d13-local-var-and-inout|d13]]–[[d17-mandatory-deadlines|d17]], [[d22-rust-plus-refinements-types|d22]], [[d25-interpreter-for-the-edit-loop|d25]], [[d33-bounded-mailboxes|d33]], chapter 7 memory bets |
| R3 authors, the elders | Thompson, Ritchie, Kernighan, Pike, Hoare, Dijkstra, Wirth, Armstrong | [[d04-style-rules-become-laws|d4]], [[d08-beam-qualities-without-the-beam|d8]], [[d14-processes-are-the-only-identity|d14]], [[d18-two-kinds-of-failure|d18]], [[d30-supply-chain-security|d30]] |
| R4 authors, the moderns | Matz, Meyer, Czaplicki, Hickey, Kelley, Greef, Holzmann, Steele, Valim, Graydon Hoare, Kay, Liskov, Peyton Jones, Lattner, Miller, Lamport | [[d22-rust-plus-refinements-types|d22]], [[d26-developer-and-agent-happiness|d26]], [[d27-simple-and-elegant-like-ruby|d27]], [[d35-mo-is-an-ecosystem|d35]], the shape-law dispute |
| R5 manifestos, philosophy and specification | Unix philosophy, Worse is Better, Zen of Python, Go proverbs, Zen of Zig, Simple Made Easy, Grug, Handmade, data-oriented design, Ousterhout, Carmack, boring technology, suckless; TLA+, Alloy, Parnas, Brooks, Hillel Wayne | [[d04-style-rules-become-laws|d4]], [[d05-old-ideas-rethought-ai-first|d5]], [[d27-simple-and-elegant-like-ruby|d27]], [[d02-spec-altitude|d2]] |
| R6 manifestos, safety and reliability | JPL, MISRA C, CERT C, DO-178C, Ravenscar, seL4, Cleanroom, static allocation; FoundationDB and Antithesis, Jepsen, SQLite testing, let-it-crash in practice, QuickCheck, SRE and chaos, mutation testing, structured concurrency | [[q12-law-numbers|Q12]], tier 3 `--sim`, the failure model, the `while` and shape-law disputes |

Status on 13 Sep 2026: R1, R3, and R6 were run by Perplexity Computer the same day (see [[agents-and-verification-2026]], [[language-design-for-llms-evidence]], [[author-ken-thompson]], [[author-dennis-ritchie]], [[author-brian-kernighan]], [[author-rob-pike]], [[author-tony-hoare]], [[author-edsger-dijkstra]], [[author-niklaus-wirth]], [[author-joe-armstrong]], [[safety-critical-coding-standards]], [[reliability-and-testing-philosophies]]). R2, R4, and R5 are open; their prompts are below.

## Context to paste with every prompt

> Mo is a statically typed, Ruby-looking, Elixir-flavored functional language in which AI agents write nearly all the code and humans read only intent, contracts (`requires`/`ensures`), `never` clauses, and capability parameters. Processes are the only mutable state and each is an Elm-shaped state machine under a supervisor with a bounded mailbox. Effects are capability parameters, not an effect type system. Style rules from Tiger Style and NASA's Power of Ten are compiler laws with no override: functions at most 70 lines, no `while`, every wait has a deadline, no exceptions, no nil, no warnings. A crash is a bug that an agent fixes from the seed and message log. Compile speed is first-class. Supply-chain security is a design goal. Nothing is final until measured. Quote primary sources verbatim with URLs; mark your own judgment as judgment.

## R2 — papers, semantics and runtime (open)

### Prompt 2a — semantics Mo depends on
> Find academic papers from 2023 to 2026 (PLDI, POPL, OOPSLA, ICFP, ECOOP, arXiv) on: capability-based effect systems and second-class or non-escaping values (Effekt, Scala capture checking, Austral linear capabilities and their successors); refinement types with SMT in production-shaped languages (Liquid Haskell, Flux for Rust, F* successors) with numbers on solver time and annotation burden; termination and totality checking that admits ordinary programs (sized types, structural recursion checkers, Bosque-style bounded iteration) and what they reject; session types and typed message protocols for actor-style processes; mutable value semantics after Hylo; information-flow types for capability-passing languages. For each: claim, mechanism, evidence, and whether it fits a language whose functions are pure unless handed a capability and whose only identity is a supervised process.

### Prompt 2b — runtime, memory, and the edit loop
> Find papers and engineering reports from 2022 to 2026 on: deterministic simulation and record-replay for actor or message-passing runtimes; Perceus-style reference counting with reuse, region allocation, and per-process heaps in single-binary languages (Koka, Roc, Inko, Pony, Lean 4's runtime) with measured overheads; bounded queues and backpressure in actor systems; structured concurrency with inherited deadlines or budgets versus per-call timeouts; query-based incremental compilers (Salsa, rust-analyzer, Roslyn, Kotlin) and what sub-50-millisecond incremental checking has required in practice. Report numbers, not adjectives.

## R4 — authors, the moderns (open)

### Prompt 4a — designers of Mo's direct inspirations
> Write primary-source profiles of Yukihiro Matsumoto (Ruby), Bertrand Meyer (Eiffel, Design by Contract), Evan Czaplicki (Elm), Rich Hickey (Clojure), Andrew Kelley (Zig), Joran Dirk Greef (TigerBeetle, Tiger Style), Gerard Holzmann (Power of Ten, JPL standard, SPIN), and José Valim (Elixir). For each: their ethos in four to eight verbatim quotes from their own talks, papers, or posts with URLs; three to six defining decisions with the reasoning they gave at the time and how each played out since; opinions that contradict a language with compiler-enforced style laws, no `while`, and no escape hatch; and what Mo could take, tagged already in Mo / strengthens Mo / contradicts Mo / new. Cover Matz's principle of least surprise and why Ruby offers many ways; Meyer's "Right and wrong: ten choices in language design" (2022) and his diagnosis of why contracts never went mainstream; Czaplicki's "What is Success?" and "The Hard Parts of Open Source"; Hickey's "Simple Made Easy" and "Spec-ulation"; Kelley's Zen of Zig and no hidden control flow; Greef's Tiger Style origins and static allocation; Holzmann's "Mars Code"; Valim's set-theoretic types and the first-party-batteries model.

### Prompt 4b — the theorists and the elders of adoption
> Write primary-source profiles of Guy Steele ("Growing a Language", Scheme, Fortress), Graydon Hoare (Rust's origins and "Rust prehistory", what he would change), Alan Kay (Smalltalk, "the computer revolution hasn't happened yet"), Barbara Liskov (CLU, abstraction, the substitution principle as discipline), Simon Peyton Jones ("avoid success at all costs", Verse), Chris Lattner (Swift, Mojo, compiler pragmatism and adoption), Mark Miller (E, object-capability security), and Leslie Lamport (TLA+, "specification is what humans read"). Same shape as prompt 4a: verbatim quotes with URLs, defining decisions and how they aged, contradictions with Mo, what Mo could take. Emphasize how each thinks a language should grow and be governed, since Mo has one designer and an expensive model making decisions by log.

## R5 — manifestos, philosophy and specification (open)

### Prompt 5a — programming philosophies as candidate laws
> Survey the programming manifestos and proverb sets that engineers actually cite: the Unix philosophy (McIlroy, Pike and Kernighan's "The Unix Programming Environment", Raymond's list), Richard Gabriel's "Worse is Better" and his later reversals, the Zen of Python, the Go proverbs, the Zen of Zig, Rich Hickey's "Simple Made Easy", the Grug Brained Developer, the Handmade Manifesto, Mike Acton's data-oriented design, Ousterhout's "A Philosophy of Software Design" (deep modules, define errors out of existence), John Carmack's 2007 email on inlining and functional style, Dan McKinley's "Choose Boring Technology", and suckless. For each: the source text with URL, the three rules most relevant to a language designer, which of those rules a compiler could enforce as a law and which cannot be, and any published evidence or notable disagreement. Close with a table of every rule that appears in three or more of these documents.

### Prompt 5b — specification and abstraction classics
> Summarize, from the primary texts, what Leslie Lamport ("Specifying Systems", "Who Builds a House Without Drawing Blueprints?"), Daniel Jackson ("Software Abstractions", Alloy, "The Essence of Software" concepts), David Parnas ("On the Criteria To Be Used in Decomposing Systems into Modules", information hiding), Fred Brooks ("No Silver Bullet", essential vs accidental complexity), Barbara Liskov and Jeannette Wing (behavioral subtyping), and Hillel Wayne ("Crossover project", formal methods in practice) say about the layer of a program humans should read and check. Map each to a language where humans read only signatures, contracts, `never` clauses, and capability parameters: what each author would say that layer must contain, what it cannot express, and what evidence exists that specifications written at that altitude catch defects.

## Threads that cut across runs

- Thompson's "Reflections on Trusting Trust" to reproducible and bootstrappable builds of the Mo toolchain itself; Zig as the single dependency makes this tractable (R3, [[q17-package-management-and-supply-chain|Q17]]).
- SQLite's `NEVER()` and `ALWAYS()` macros as tested-untestable code, against Mo's `never` and the review's demand to mutation-test the contract machinery (R6).
- Ada's `pragma Restrictions` and MISRA's decidable-rule classification as precedents for tighten-only laws and for which laws a compiler can decide (R6, [[q12-law-numbers|Q12]]).
- Structured concurrency's inherited deadlines against [[d17-mandatory-deadlines|direction 17]]'s per-call literals (R2, R6).
- Cold start of a zero-corpus language: synthetic corpora, grammar-constrained decoding, transfer from Ruby-shaped syntax (R1, [[case-against-new-languages]]).

## Not scheduled, worth a run later

Hot code loading and distribution without the BEAM (what [[d08-beam-qualities-without-the-beam|direction 8]] gives up); WebAssembly as a sandbox for recipe execution and as a compile target; CHERI and hardware capabilities as the substrate under [[d15-effects-via-capabilities|direction 15]]; language governance and evolution (Go's compatibility promise, Elm's cadence, Steele's growth) once Mo has users other than Robert.

## Related
- [[prompts-language-landscape]]
- [[prompts-q17-supply-chain]]
- [[research-summary-2026-09]]
- [[steal-list]]
- [[outside-review-2026-09-13-response]]
- [[roadmap]]
