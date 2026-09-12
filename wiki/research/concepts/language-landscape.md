---
title: "Language landscape: which languages deserve a deep comparison"
created: 2026-09-12
updated: 2026-09-12
type: concept
tags: [research, philosophy]
sources: [raw/articles/agentlanguages-dev-catalogue-2026-09-12.md]
confidence: medium
---

# Language landscape: which languages deserve a deep comparison

Claude's lane of the survey (web + catalogue; arXiv rate-limited this pass). Robert's lane runs the prompts in [[prompts-language-landscape]]; the two get compared. Goal: a long list, each entry with the *one idea worth stealing* for Mo, then a shortlist for the comparison pass in [[roadmap]].

Status labels are as of Sep 2026 from the cited source. `confidence: medium` because most entries rest on one source each.

## A. Contracts and verification (Mo's "source carries its evidence")

- **Eiffel** (1985) — invented Design by Contract: `require`/`ensure`/invariants as language, not comments. The reason it didn't win (an OOP language nobody adopted) doesn't apply to Mo's contracts.[17]
- **SPARK Ada** — contracts are part of the language, checked by the compiler, proved by the SPARK prover, and have execution semantics; the model for Mo's tier 2 / tier 3 split.[18] A 2025 study (Marmaragan) has an LLM generate SPARK annotations for existing code and proposes a hybrid: humans write high-level pre/post, the LLM proposes lower-level contracts and loop invariants, the prover checks.[17]
- **Dafny** — the language LLMs prove things in best: 82% vericoding success vs 44% Verus and 27% Lean on a 12,504-spec benchmark; pure-Dafny verification went 68% → 96% in a year.[29] A separate line proposes Dafny as a verification-aware *intermediate* language for code generation.[30] Steal: the shape of contracts models already discharge well.
- **Verus / Lean 4** — the same benchmark's harder end; relevant only as tier-3 backends, not as syntax to imitate.[29]
- **Bosque** (Microsoft Research, 2019) — "regularized programming": no loops, no mutable state, no reference equality, so that automated reasoning becomes trivial.[6][33] Closest older cousin to Mo's laws; it stalled, and *why* is worth a page.
- **Whiley, D, Cobra** — contract-language lineage; lower priority.

## B. Capabilities and security (Mo's "no capability, no effect")

- **E** (Mark Miller) — the origin of object-capability security; everything else here descends from it. Steal the discipline, not the syntax.
- **Wyvern** (CMU) — capability-safe modules: a module can only touch resources it is handed capabilities for; the authors note prior attempts to retrofit capability-safety onto existing languages had to redesign the standard library.[27] Directly on point for [[q17-package-management-and-supply-chain|Q17]].
- **"Capabilities: Effects for Free"** (Craig, Potanin, Groves, Aldrich 2018) — the paper behind [[d15-effects-via-capabilities|direction 15]]: capability passing gives you effect reasoning without an effect type system.[28]
- **Austral** — linear types plus capability-based security in a deliberately small systems language; bootstrapping compiler in OCaml implements the whole spec, stdlib with capability-based filesystem access in design.[12] The clearest existing "capabilities as the permission system."
- **Mog, AILANG, Boruna, SEMAPRAX** (2025–26, agent-native) — capability grants / capability effects / hash-chained evidence in languages built for agents.[1]

## C. Effects (how Mo decided *not* to do it, and who does)

- **Koka** — polymorphic type-and-effect system, effect handlers, and Perceus: reference counting with reuse that compiles to C with no GC, within ~10% of C++ on tree benchmarks.[25][26] Mo takes Perceus and skips the effect types.
- **Effekt** — lexical effect handlers and lightweight effect polymorphism; the static effect system "tells you where you forgot to handle something."[13]
- **Ante** — restricts `resume` to at-most-once, which simplifies resource handling and makes continuations cheap.[14] A useful constraint to study for Mo's direct-style I/O.
- **Flix** — effect-oriented, with 59 written design principles and language-integrated Datalog.[7] The *principles document* is the thing to steal: a language that wrote its laws down.

## D. State, memory, values (Mo's `var`/`inout`, processes as the only identity)

- **Hylo** (ex-Val) — mutable value semantics: all types are value types, mutation without aliasing, borrowing/copy-on-write managed by the compiler; new compiler under active development, pre-1.0.[10][32][11] The direct source of [[d13-local-var-and-inout|direction 13]].
- **Vale** — generational references: every object carries a generation counter, every pointer remembers it, dereference asserts they match; region borrow checking planned; pre-1.0.[16] An alternative to both GC and borrow checking worth one page.
- **Inko** — Rust's single ownership + Erlang's isolated processes with message passing, values *moved* into the receiving process; deterministic memory, one binary.[24] The existence proof for [[d08-beam-qualities-without-the-beam|direction 8]].
- **Pony** — reference capabilities (six of them) so mutable data moves between actors without copies or locks; too many caps, but the core idea is gold. (from session 1)
- **Toka** (2026 paper) — "explicit resource semantics" for a systems language; unread beyond the abstract, flagged for the paper lane.[21]

## E. Fault tolerance and processes

- **Erlang / Elixir** — processes, supervision, let-it-crash. Elixir v1.20 (Jun 2026) is now *gradually typed with full inference and no annotations*, reporting "verified bugs" with very low false positives; type signatures come later.[22] Watch: their inference-first approach vs Mo's annotate-every-boundary.
- **Gleam** — static types on the BEAM, v1.18 (Jul 2026; Robert's lane), 2nd most-admired language in the 2025 Stack Overflow survey; most users come from outside the BEAM.[23] Evidence that "typed BEAM" has an audience; Mo's syntax rejection of Gleam still stands.
- **Verse** (Epic, with Simon Peyton Jones) — functional *logic* language: every function runs inside a transaction that can roll back and be resimulated; distributed transactional memory planned for UE6 (2027).[8][9] Wild idea to study: transactional semantics as the failure story instead of crash-and-restart.

## F. Simplicity by law, and tooling as language

- **Go** — one formatter, one build tool, batteries stdlib, ~25 keywords. (session 1)
- **Zig** — comptime, own backend for debug builds, the C toolchain we'll use. Roc's rewrite from Rust to Zig: 487 days, ~300K lines, incremental rebuilds 3.4s → 35ms, fewer memory bugs than the Rust version; Roc 0.1.0 targeted for later 2026.[15]
- **Roc** — the *platform* concept we adopted in [[q11-platform-and-stdlib|Q11]].[15]
- **Unison** — every definition identified by the hash of its syntax tree; code stored as ASTs in a database; exact dependencies by hash, no dependency hell, renames can't break references; 1.0 shipped (Nov 2025).[4][5] Direct ancestor of [[q10-semantic-ids-and-editing|Q10]] — and the cautionary tale (no text files).
- **MoonBit** — self-described "AI-native language toolchain": Wasm-first, multi-backend, with *MoonBit Pilot*, a code agent built into the toolchain that generates libraries with docs and tests and does large refactors that pass CI.[2][3] The closest *shipping* competitor to Mo's premise; must be a comparison page.
- **Bend / HVM** — Python-feel language on interaction nets, automatic massive parallelism on GPU; Bend2 planned with a parallel CPU runtime.[19] Not for Mo's domain, but the "parallel for free" claim deserves a look.

## G. Built for AI authors (the new wave)

The agentlanguages.dev catalogue tracks **42 languages** whose designers explicitly target LLMs or agents as authors, in three camps — syntactic ("every token has one job"), verification ("the model doesn't need to be right, it needs to be checkable"), orchestration ("it's an agent-coordination problem").[1] Almost all are 2025–2026, most have a working compiler, none has users.[1]

Mo is squarely in the verification camp with a syntactic conscience. The ones to read closely, because they overlap with specific Mo decisions:[1]
- **Intent, Vera, Thermite, Vow, Aver** — mandatory contracts with Z3 / ESBMC / Lean-Dafny exports; Thermite's mandatory `req/ens/fx` is nearly Mo's `requires/ensures` + capability params.
- **AILANG** — capability effects and *no loops* (Bosque's move again).
- **Hale** — compile-time effect certificates for concurrent systems.
- **Tacit** — AST-first with BLAKE3 addressing (Q10's content hashes).
- **Zero** (Vercel Labs), **Codong**, **Valea** — structured JSON diagnostics as a headline feature ([[q09-compiler-diagnostics|Q9]]).
- **Pel** — grammar-level capability control for agent orchestration, homoiconic, LLM-evaluated conditions.[20]
- **Axis** — LL(1) grammar for constrained decoding on small models; the syntactic camp's strongest technical argument.
- **Modula-9** — Wirth lineage with differential execution validation (compare against our interpreter-vs-C differential testing).

Also relevant papers surfaced: "Specifications: the missing link to making the development of LLM systems an engineering discipline" (2024),[31] and the vericoding benchmark itself.[29]

## Shortlist for the comparison pass

✅ **Robert: IN** (session 2). These 13 are the comparison pass.

One page each, in `research/comparisons/`. Chosen for *overlap with a Mo decision*, not popularity.

1. **Elixir** (incl. the new type system) — our flavor; typed BEAM done inference-first.
2. **Go** — simplicity by law, stdlib, tooling.
3. **Rust** — the type system we borrow minus lifetimes.
4. **Roc** — platforms, Zig rewrite, Perceus-style memory.
5. **Koka** — effects + Perceus; the road not taken.
6. **Austral** — capabilities + linearity as the security model.
7. **Hylo** — mutable value semantics.
8. **Unison** — content-addressed code; what to take, what to avoid.
9. **MoonBit** — the shipping "AI-native toolchain."
10. **Bosque** — regularized programming; why it stalled.
11. **SPARK Ada + Dafny** — contracts that provers and LLMs both handle.
12. **The agent-native cluster** (Intent/Vera/Thermite/Vow/Aver/AILANG/Hale/Tacit/Zero as one page) — what 42 fresh attempts converged on.
13. **Verse** — transactional semantics as a failure story (wildcard).

Dropped from the original nine: **Gleam** (syntax already rejected; BEAM covered by Elixir), **Elm** (its lessons are in the steal list; Roc carries them forward), **Zig** (it's our implementation language, not a design peer — covered inside the Roc page).

## Related
- [[steal-list]]
- [[roadmap]]
- [[q17-package-management-and-supply-chain]]
## Sources

[1] https://agentlanguages.dev — agentlanguages.dev catalogue (42 languages, updated 12 Sep 2026)
[2] https://www.moonbitlang.com/blog/intro-moonbit-pilot — MoonBit Pilot
[3] https://www.moonbitlang.com/blog/beta-preview — MoonBit beta preview
[4] https://www.unison-lang.org/docs/the-big-idea — Unison: the big idea
[5] https://www.infoworld.com/article/4100673/futuristic-unison-functional-language-debuts.html — Unison 1.0 (InfoWorld)
[6] https://github.com/microsoft/BosqueLanguage — Bosque repo
[7] https://dl.acm.org/doi/pdf/10.1145/3563835.3567661 — The Principles of the Flix Programming Language (Madsen)
[8] https://verselang.github.io/book/00_overview — Book of Verse
[9] https://www.unrealengine.com/news/the-road-to-ue-6 — The road to UE6 (Verse)
[10] https://github.com/hylo-lang/hylo — Hylo repo
[11] https://arxiv.org/abs/2106.12678 — Native Implementation of Mutable Value Semantics
[12] https://github.com/austral/austral — Austral repo
[13] https://effekt-lang.org — Effekt
[14] https://antelang.org/blog/why_effects — Ante: why algebraic effects
[15] https://www.developersdigest.tech/blog/roc-rust-to-zig-rewrite-feldman — Roc Rust-to-Zig rewrite numbers
[16] https://vale.dev/memory-safe — Vale memory safety
[17] https://arxiv.org/abs/2502.07728 — Verifying LLM-Generated Code with Ada/SPARK (Marmaragan)
[18] https://www.adacore.com/languages/spark — SPARK
[19] https://github.com/HigherOrderCO/Bend — Bend
[20] https://arxiv.org/abs/2505.13453 — Pel: a language for orchestrating AI agents
[21] https://arxiv.org/abs/2606.01974 — Toka: explicit resource semantics
[22] https://elixir-lang.org/blog/2026/06/03/elixir-v1-20-0-released — Elixir v1.20: gradually typed
[23] https://gleam.run — Gleam
[24] https://inko-lang.org — Inko
[25] https://koka-lang.github.io/koka/doc/book.html — Koka book
[26] https://dl.acm.org/doi/10.1145/3453483.3454032 — Perceus (PLDI 2021)
[27] https://wyvernlang.github.io — Wyvern
[28] https://potanin.github.io/files/CraigPotaninGrovesAldrichICFEM2018.pdf — Capabilities: Effects for Free
[29] https://arxiv.org/abs/2509.22908 — A benchmark for vericoding
[30] https://arxiv.org/abs/2501.06283 — Dafny as verification-aware IL for code generation
[31] https://arxiv.org/abs/2412.05299 — Specifications: the missing link
[32] https://hylo-lang.org — Hylo site
[33] https://www.microsoft.com/en-us/research/project/bosque-programming-language — Bosque (Microsoft Research)
