---
title: "Mo vs the agent-native cluster"
created: 2026-09-12
updated: 2026-09-12
type: comparison
tags: [research, agents, verification]
sources: [raw/articles/agentlanguages-dev-llms-full-2026-09-12.md, raw/articles/agentlanguages-dev-catalogue-2026-09-12.md, raw/articles/ntnt-github-repo.md, raw/articles/ntnt-about.md, raw/articles/neam-github-repo.md]
confidence: medium
---

# Mo vs the agent-native cluster

**One line:** thirteen 2025–26 languages built for agents as authors: eleven from the agentlanguages.dev catalogue, plus Neam and NTNT, which aren't in it. On the list to see which of Mo's decisions they share ([[d01-agents-write-the-code|direction 1]], [[d03-source-carries-its-evidence|direction 3]], [[q09-compiler-diagnostics|Q9]], [[q10-semantic-ids-and-editing|Q10]]) and what 42 separate attempts converged on. *Format note:* one page for many languages, so each gets a short entry rather than an idea list.

## What it is (status as of Sep 2026)

The catalogue tracks 42 languages whose designers explicitly target LLMs or agents as authors. Tools that merely *use* an LLM at runtime are out of scope.[111] By camp: 17 verification, 14 syntactic, 7 orchestration, 1 adjacent, 3 unclassified.[111] It is maintained by Alasdair Allan, who also wrote one of the entries, Vera.[111] Most entries were first seen between February and June 2026.[111] Neam and NTNT both exist: public repos created in January 2026, with 7 and 8 stars.[114][112]

## The ideas, one by one

**Verification camp**
- **Intent** (Go; v0.2.0, 5 stars). Every function has `requires`/`ensures`, and loops carry `invariant`/`decreases`. An `intent` block links a natural-language goal to contract clauses through `verified_by`, and an unresolved link is a compile error. Z3 proves what it can; the rest becomes runtime checks.[111]
  - *Overlap / verdict:* Mo's `intent` and `never` sentence-plus-block ([[p09-module-header-and-never|pick 9]]) and the tiers ([[q08-verification-tiers|Q8]]). **Already have.**
- **Vera** (Python; about 2,400 commits, 9,382 tests). Mandatory `requires`/`ensures`/`effects`, discharged by Z3 in the decidable fragment and as a runtime guard otherwise. Parameters have no names, only typed slots (`@Int.0`). LLM inference is a typed effect.[111]
  - *Overlap / verdict:* tiers and effects, yes. **Reject** unnamed slots: they cost human readability ([[d02-spec-altitude|direction 2]]).
- **Thermite** (Rust + Lean 4; June 2026). Mandatory `req`/`ens`/`fx`, plus loop `inv`/`dec`. The Forge tool records *per obligation* whether a clause was proved, bounded-checked, runtime-enforced or trusted. "The project-level headline is the minimum", and counterexamples stay failures.[111]
  ```
  fn sum(xs: &[u32]) -> u64
    req xs.len() <= 1_000_000
    ens result == spec_sum(xs)
    fx  pure
  ```
  - *Overlap / verdict:* the closest to Mo's contracts plus capabilities. **Steal** per-obligation evidence, with the minimum as the headline, for `verified:` ([[q06-verified-line|Q6]]).
- **Vow** (Rust, self-hosting; v0.2.0). `vow` blocks and loop invariants go to the ESBMC bounded model checker before codegen. JSON diagnostics blame the Caller (`requires`) or the Callee (`ensures`, `invariant`). The compiler writes a Claude Code skill "generated from the same compiler version".[111]
  - *Overlap / verdict:* Q9 plus crash reports ([[d21-autonomous-crash-fixing|direction 21]]). **Steal** the blame field and the version-matched skill.
- **Aver** (Rust; v0.21). Every function has a prose intent (`?`), declared effects (`!`), and a colocated `verify` block. That block runs as samples, as hostile checks, or exports to Lean 4 or Dafny, and "the four readings can disagree".[111]
  - *Overlap / verdict:* same-file tests ([[p12-tests|pick 12]]). **Already have.** Aver shows the risk of several verification readings of one block.
- **AILANG** (Go; 110 releases, 26 stars). Pure functional, with row-polymorphic effects. Capability categories (`IO`, `FS`, `Net`, `Clock`, `AI`) are granted at launch with `--caps`. No loops. The compiler itself is written by AI agents.[111]
  - *Overlap / verdict:* capabilities ([[d15-effects-via-capabilities|direction 15]]); Bosque's no-loops move ([[bosque]]). **Open:** operator-granted capabilities at launch.
- **Hale** (Rust; May 2026). One primitive, the "locus", replaces class, module, actor and service, and loci talk over a typed topic bus. Contracts range from `@no_syscall` up to program-wide `forbid reaches(A, B)`, answered with countermodel witnesses. No async colouring, lifetimes or locks. An MCP server ships in the compiler.[111]
  - *Overlap / verdict:* processes ([[d14-processes-are-the-only-identity|direction 14]]) and `flows(...)` ([[p09-module-header-and-never|pick 9]]). **Open:** `forbid reaches` as the general form of `flows`.

**Syntactic camp (and the verification crossovers)**
- **Tacit** (Rust; v0.7.7, 3 stars). The AST is authoritative and serializes to exactly one canonical text. Definitions are BLAKE3-addressed, names live in a JSON sidecar, and malformed code becomes typed `Hole` nodes instead of a parse failure.[111]
  - *Overlap / verdict:* the inverse of Q10, which keeps names in text and IDs in a sidecar. **Reject** the sidecar names. **Open:** typed holes, so diagnostics keep working on partial files.
- **Zero** (Vercel Labs; C bootstrap; v0.1.1, 3.3k stars). Stable diagnostic codes (`NAM003`), typed repair plans (`zero fix --plan --json`), and guidance served by the CLI and pinned to the installed version. Capability objects on `main`, no hidden allocator. A "pre-1 experiment".[111]
  - *Overlap / verdict:* this is [[q09-compiler-diagnostics|Q9]] plus [[p13-capabilities-and-logging|pick 13]]. **Already have** by design; Zero is the backed competitor on this axis.
- **Codong** (Go; v0.1.3, 67 stars). One canonical function per task. Nine bundled modules and zero dependencies. JSON errors carry `fix` and `retry` fields. Compiles through Go.[111]
  - *Overlap / verdict:* a batteries-included stdlib ([[q11-platform-and-stdlib|Q11]]), Q9. **Already have.**
- **Axis** (Rust; 3 stars, one initial commit). Aimed at 1B–7B models: twelve constructs for a backend, an LL(1) grammar, and grammar-aware logit masks shipped as JSON. "Failure is syntax": missing auth and unindexed queries are compile errors.[111]
  - *Overlap / verdict:* laws ([[d04-style-rules-become-laws|direction 4]]). **Open:** constrained decoding, as on [[moonbit]].

**Outside the catalogue**
- **NTNT** (Rust; created Jan 2026). "Intent-Driven Development": `.intent` scenario files checked by `ntnt intent check`, plus `requires` contracts. 480 built-in functions, including auth, databases and background jobs. String interpolation is borrowed from Ruby. It claims "running production apps" but warns of breaking changes.[112][113]
  - *Overlap / verdict:* humans state intent and agents implement ([[d19-negative-space-is-the-contract|direction 19]]). **Already have.** Its stdlib reaches well past Q11's ceiling.
- **Neam** (C++; created Jan 2026). A compiled DSL for *building* AI agent systems: LLM providers, RAG, multi-agent orchestration, governance, running on a bytecode VM.[114]
  - *Overlap / verdict:* none with Mo's core. Claude's reading: it uses LLMs at runtime, which the catalogue excludes.[111] **Reject** as a design peer.

### What 42 attempts converged on

- **Checkable beats correct.** Verification is the largest camp.[111] The catalogue itself notes that nine entries enforce something per function, so "the live differentiator sits in what discharges the obligations rather than in their being compulsory".[111]
- **The same three layers as Mo's Q8:** mandatory contracts, a solver or model checker for what's decidable, and runtime checks for the rest (Intent, Vera, Thermite, Vow).[111]
- **Diagnostics built for agents:** stable codes, JSON, and repair plans (Zero, Codong, Vow, Tacit).[111]
- **Toolchains that ship their own agent guidance:** skills or MCP pinned to the compiler version (Zero, Vow, Hale).[111]
- **Explicit effects or capabilities** in most verification-camp entries (AILANG, Aver, Thermite, Vera, Zero, Hale).[111]
- **Rare:** content addressing (Tacit) and no loops (AILANG). A rough keyword pass over all 42 entries (loose: a mention isn't a feature) found content hashing in 4 and constrained decoding in 2, against contract language in 28.[111]

## What it gives up

- **Readability for humans.** Vera drops parameter names, and Tacit drops comments and free formatting.[111]
- **Stability and safety.** Zero says breaking changes and security vulnerabilities "should be expected".[111]
- **Maturity.** Most are single-author projects with single- or double-digit stars at cataloguing. Axis arrived as one commit.[111]

## Evidence

- **Size of the field:** 42 catalogued, by camp as above.[111]
- **Engineering signals:** Vera's 9,382 tests, Codong's 1,427, AILANG's 110 releases.[111]
- **Adoption:** stars only. Zero at 3.3k is the outlier. No usage data found.[111][112][114]
- **LLM benchmarks comparing these languages:** none found.
- **Source caveat:** the catalogue's maintainer also authors Vera.[111]

## What Mo should take from this

- **Positioning:** contracts, a solver and agent-facing diagnostics are now the camp's *consensus*, not Mo's edge.[111] Mo's differentiation has to be elsewhere, and the v0 design doc should say so:
  - spec altitude a human can actually read ([[d02-spec-altitude|direction 2]], [[d26-developer-and-agent-happiness|direction 26]])
  - processes with supervision and deterministic replay ([[d14-processes-are-the-only-identity|direction 14]], [[d21-autonomous-crash-fixing|direction 21]])
  - capabilities as package permissions ([[d30-supply-chain-security|direction 30]])
  - laws
- **Proposal:** a per-obligation `verified:` record whose headline is the weakest obligation (Thermite).[111]
- **Proposal:** contract-violation diagnostics carry blame, `requires` → caller and `ensures`/`invariant` → callee (Vow). This feeds the crash report in [[d21-autonomous-crash-fixing|direction 21]].[111]
- **Proposal:** `mo` serves version-pinned agent guidance itself (Zero, Vow), alongside the MCP server proposed on [[unison]].[111]
- **Question for Robert:** should operators also grant capabilities at launch (AILANG's `--caps`), on top of narrowing inside the code? It is an input for [[q17-package-management-and-supply-chain|Q17]].[111]
- **Question for Robert:** adopt Hale's `forbid reaches(A, B)` as the general form of `flows(...)`?[111]
- **Watch:** Zero, the only entry with corporate backing and real attention.[111]

## Related
- [[language-landscape]]
- [[q08-verification-tiers]]
- [[q09-compiler-diagnostics]]
- [[q10-semantic-ids-and-editing]]
- [[q17-package-management-and-supply-chain]]
- [[moonbit]]
- [[unison]]
- [[bosque]]

## Sources

[111] https://agentlanguages.dev/llms-full.txt — agentlanguages.dev full catalogue (llms-full.txt)
[112] https://github.com/ntntlang/ntnt — NTNT: agent-native language with Intent-Driven Development (GitHub)
[113] https://ntnt-lang.org/about — About NTNT
[114] https://github.com/neam-lang/Neam — Neam: compiled DSL for AI agent systems (GitHub)
