---
title: "Mo vs Elixir"
created: 2026-09-12
updated: 2026-09-17
type: comparison
tags: [research, types, processes]
sources: [raw/articles/elixir-v1-20-released.md, raw/articles/elixir-type-inference-next-15-months.md, raw/papers/elixir-type-system-design-principles.md, raw/papers/elixir-guard-analysis-safe-erasure.md, raw/articles/elixir-supervisor-docs.md, raw/articles/valim-elixir-best-language-for-ai.md, raw/articles/breitig-llms-write-elixir.md, raw/articles/gleam-otp-readme.md]
confidence: medium
---

# Mo vs Elixir

**One line:** Mo's declared flavor ([[d07-elixir-flavored-functional|direction 7]]); on the list because v1.20 made it a typed BEAM language by inference alone, and because OTP supervision is the shape Mo's [[q07-process-api|Q7]] copies.

## What it is (status as of Sep 2026)

Elixir is a gradually typed functional language on the Erlang VM (v1.20; corrected 17 Sep 2026), used by companies such as Discord and PepsiCo.[4] Elixir v1.20 shipped on 3 June 2026 and type checks every program by inference, with no annotations.[1] The type system came out of a partnership between CNRS and Remote. Its development is now sponsored by Fresha and Tidewave.[1] The theory is in two papers by Castagna, Duboc and Valim.[3][4] User-written type signatures are not in yet, and the team gates them on unsolved performance and research problems.[1] Admiration is high: 66% in the 2025 Stack Overflow survey, third behind Rust and Gleam.[10]

## The ideas, one by one

- **Inference-first, "verified bugs" only.** Every unknown is `dynamic()`, a *range* that narrows as the value is used. An error is raised only when the supplied and accepted types are disjoint, so every report is guaranteed to fail at runtime.[1]
  ```elixir
  v = if n > 1, do: n, else: "not well"   # dynamic(integer() or binary())
  v / 100                                  # no report: could be an integer
  Map.fetch!(v, :key)                      # report: can never be a map
  ```
  - *Mo today:* [[d11-statically-typed|direction 11]] requires types at every function boundary, so Mo has no `dynamic()` and no untyped legacy to rescue.
  - *Verdict:* **reject** the gradual part, **steal** the principle. Elixir says that "too many false positives" would "erode the trust" in its checker.[1] Mo has errors only, no warnings ([[q09-compiler-diagnostics|Q9]]), so a false positive costs Mo even more.

- **Structural map types with open rows.** `user.age` used as an integer infers the argument `%{..., age: integer()}`: any map with at least that key.[2]
  - *Mo today:* nominal `struct`s with named fields ([[p07-types-struct-enum-refinement|pick 7]]).
  - *Verdict:* **reject** for Mo. The spec altitude reads named types. An inferred open row is an interface nobody wrote down, and the boundary type is what [[d02-spec-altitude|direction 2]] puts on the page.

- **Guards and clauses narrow types.** `when is_integer(x)`, `is_map_key(x, :foo)`, and `tuple_size(x) < 3` all refine types. Earlier `case` clauses narrow later ones, which also finds redundant clauses and dead code.[1]
  - *Mo today:* exhaustive `case` with no catch-all on closed enums ([[p05-pattern-matching|pick 5]]), plus refinement types checked statically when provable ([[d22-rust-plus-refinements-types|direction 22]]).
  - *Verdict:* **already have** exhaustiveness. **Open** on flow narrowing: should `if amount > 0` give `amount` a refined type inside the branch? Elixir shows that runtime tests are what make inference precise.[4]

- **OTP supervision shapes.** Three strategies: `:one_for_one` restarts only the child that died, `:one_for_all` restarts all children, `:rest_for_one` restarts the child and those started after it. Restart values are `:permanent`, `:transient` and `:temporary`. Intensity defaults to 3 restarts in 5 seconds. A supervisor that exceeds it exits with `:shutdown` and escalates to its parent.[5]
  ```elixir
  Supervisor.start_link([Ledger, RefundQueue],
    strategy: :rest_for_one, max_restarts: 3, max_seconds: 5)
  ```
  - *Mo today:* [[q07-process-api|Q7]] has `:always` / `:on_crash` / `:never`, which match permanent / transient / temporary one for one, plus `max_restarts: N per Duration`. There is **no strategy field**, and nothing says what happens when `max_restarts` is exceeded.
  - *Verdict:* **open.** Without a strategy, Mo behaves like `:one_for_one` only. That breaks when one child depends on another (the queue needs the ledger connection it was started with).

- **Typed processes on the BEAM (via Gleam).** Gleam OTP types every actor's message, and a reply travels as a typed `Subject(Int)` inside the message.[9] OTP features that are "not possible to represent in a type safe way" are simply left out.[9]
  - *Mo today:* `Handle(Name)`, reply types on the `message` line, and no links, monitors, or `receive` in user code ([[q07-process-api|Q7]]).
  - *Verdict:* **already have.** Gleam's omissions are independent evidence that Q7's cuts are the price of typed processes, not an oversight.

- **Docs are not comments; examples are tests.** `@doc` is separate from `#` comments, and the `iex>` examples inside docs run as tests. Valim argues this separates "the public contract" from implementation detail for agents.[6]
  - *Mo today:* [[q01-comments|Q1]] made doc comments plain `#` blocks, with no separate form. Tests sit in the same file ([[p12-tests|pick 12]]).
  - *Verdict:* **open.** In Mo, the public contract is `intent` / `requires` / `ensures` / `never`, not prose, which weakens Valim's point. His point about training data holds, though: tested examples are correct examples.

- **Pipes and immutable data flow.** `text |> String.split() |> Enum.frequencies()` reads left to right. Everything a function needs goes in, and everything it changes comes out.[6]
  - *Mo today:* dot calls are first-argument sugar ([[p15-methods-traits-generics|pick 15]]), so `text.split.frequencies` reads the same way. Immutable by default ([[d10-immutable-by-default|direction 10]]).
  - *Verdict:* **already have.**

## What it gives up

- **Signatures, for now.** No user-written types yet. They wait on type checker performance, efficient recursive and parametric types, and typed traversal of map key-value pairs.[1] Mo accepts the opposite cost: annotation at every boundary.
- **Types don't drive the compiler.** Types are erased and "not used by the compiler", which keeps BEAM compatibility.[4] Mo wants types to shape the C output ([[d24-compile-to-c-via-zig|direction 24]]), so it does not share this cost.
- **The VM.** Hot code loading and distribution come with it. Mo already gave these up ([[d08-beam-qualities-without-the-beam|direction 8]]).

## Evidence

- **Type narrowing benchmark:** Elixir passes 12 of 13 categories of the "If T" type-narrowing benchmark.[1]
- **Real codebases:** the 2024 paper reports type checker performance on Hex and Phoenix. Its numbers are in §7–8 and were not extracted this pass.[4]
- **LLM benchmark (claimed):** on AutoCodeBench, Claude Opus 4 scored 80.3% on Elixir against 74.9% for C#. 97.5% of Elixir problems were solved by at least one model, the highest of 20 languages.[6][8]
- **LLM benchmark (critique):** Elixir's problems were translated from Python. The easy-problem filter was weaker for low-resource languages. Elixir's tests were never checked by a human. Python's solved-by-any-model ceiling was 63.3%, against Elixir's 97.5%.[7] Fair reading: models handle functional, pattern-matched code at least competently. Whether it is *better* is unproven.
- **Adoption:** 66% admired in 2025, third of all languages.[10]

## What Mo should take from this

- **Proposal:** make "no false positives" an explicit bar for Mo diagnostics. Track the false-positive rate as a metric in the eval suite ([[d28-nothing-final-until-measured|direction 28]]). Elixir hedges with warnings; Mo can't.
- **Proposal:** a tier-3 prover result of "unknown" is not red. Only a found counterexample fails. This matches Elixir's disjointness rule and `proofs(k of n)` in [[q06-verified-line|Q6]]. [[q08-verification-tiers|Q8]] should say it explicitly.
- **Question for Robert:** add `strategy: :one_for_one | :rest_for_one | :one_for_all` to `supervisor`, or keep one-for-one only? Related: when `max_restarts` is exceeded, does the supervisor crash to its parent (OTP) or stop the program?
- **Question for Robert:** should `if` and `case` narrow a value into a refinement type inside the branch (flow typing), or must refinements always be constructed explicitly?
- ⚠️ **Tension with [[q01-comments|Q1]]:** Valim's case for a separate doc form with tested examples cuts against Q1's "no doc-comment variant". Not resolved here. A possible middle is `test` blocks as the examples, which Mo already has.
- **Proposal:** use Breitig's critique of AutoCodeBench as a checklist for Mo's own LLM eval: native problems, human-checked tests, and a per-language difficulty filter.

## Dated research follow-up

Hermes, 2026-09-16: [[hermes-daily-2026-09-16]] distinguishes the versioned Elixir and Erlang supervisor defaults, inspects the round-10 supervisor, and records recovery/error-path coverage questions. The comparison above is retained as the 12 September reading; its “Mo today” statements and open questions are historical, not the current implementation status. Consult the current chapter 3 and [[roadmap]] before using them.

## Related
- [[language-landscape]]
- [[d07-elixir-flavored-functional]]
- [[d11-statically-typed]]
- [[d14-processes-are-the-only-identity]]
- [[d18-two-kinds-of-failure]]
- [[q07-process-api]]
- [[q09-compiler-diagnostics]]
- [[q01-comments]]
- [[erlang]]

## Sources

[1] https://elixir-lang.org/blog/2026/06/03/elixir-v1-20-0-released — Elixir v1.20 released: now a gradually typed language
[2] https://elixir-lang.org/blog/2026/01/09/type-inference-of-all-and-next-15 — Type inference of all constructs and the next 15 months (Elixir blog)
[3] https://arxiv.org/abs/2306.06391 — The Design Principles of the Elixir Type System (Castagna, Duboc, Valim)
[4] https://arxiv.org/abs/2408.14345 — Guard Analysis and Safe Erasure Gradual Typing: a Type System for Elixir
[5] https://hexdocs.pm/elixir/Supervisor.html — Elixir Supervisor docs
[6] https://dashbit.co/blog/why-elixir-best-language-for-ai — Why Elixir is the best language for AI (Valim)
[7] https://lukabreitig.com/blog/llms-write-elixir — Do LLMs really write better Elixir than Python? (Breitig)
[8] https://arxiv.org/abs/2508.09101 — AutoCodeBench: LLMs are automatic code benchmark generators
[9] https://github.com/gleam-lang/otp — Gleam OTP README
[10] https://survey.stackoverflow.co/2025/technology — Stack Overflow Developer Survey 2025: Technology
