---
title: "Landscape, second lane: what Robert's research runs add"
created: 2026-09-12
updated: 2026-09-12
type: concept
tags: [research, philosophy]
sources: [raw/research-runs/emerging_languages_2022_2026.md, raw/research-runs/pl-ideas-that-did-not-win.pplx.md, raw/research-runs/llm-authored-programming-languages.pplx.md]
confidence: medium
---

# Landscape, second lane: what Robert's research runs add

Claude's lane is [[language-landscape]] (web + catalogue, 12 Sep 2026) plus the 13 comparison pages. Robert's lane is three deep-research runs against [[prompts-language-landscape]]. The **emerging-languages run** answers prompt 1; its tool isn't recorded yet ("Robert to fill in"). The **did-not-win run** (Perplexity) answers prompt 2, and the **agent-languages run** (Perplexity) answers prompt 3. This page records only what the runs add or dispute. Judgments marked *Claude's recommendation* are Claude's, not Robert's.

## Languages Robert's lane found that Claude's lane missed

**New or redesigned, 2022–2026** (emerging-languages run)
- **Motoko**: "designed for AI agents building backends"; every canister is an isolated actor; 1.0 in Dec 2025, 1.16 in Sep 2026. Touches [[d14-processes-are-the-only-identity|direction 14]] and [[d01-agents-write-the-code|direction 1]].
- **Mojo**: 1.0 on 11 Aug 2026; Python-shaped with a compiler. High first-try validity, but agents emit plain Python by mistake. Touches [[d26-developer-and-agent-happiness|direction 26]].
- **Neut**: derives discard and copy functions from types, so no borrow checker or annotations are needed; 0.18, active. Touches [[d10-immutable-by-default|direction 10]] and [[d13-local-var-and-inout|direction 13]].
- **Granule**: graded modal types (for example, "a secret used at most once, never leaked"); research prototype, quiet since 2024. Touches [[d22-rust-plus-refinements-types|direction 22]] and `flows` in [[p09-module-header-and-never|pick 9]].
- **Nim 2**: ORC cycle-collecting reference counting by default, plus a `.forbids` pragma that bans effects. Touches [[d10-immutable-by-default|direction 10]] and [[d15-effects-via-capabilities|direction 15]].
- **Kotlin 2.0**: K2 compiler with flow-sensitive smart casts, which is the open flow-narrowing question on [[elixir]]. Touches [[d22-rust-plus-refinements-types|direction 22]].
- **Swift 6**: data races as compile errors, and typed `throws(E)` with `throws(Never)`. Touches [[d18-two-kinds-of-failure|direction 18]] and [[p06-results-and-propagation|pick 6]].
- **Idris 2**: full dependent types with *optional* totality (`total`); pre-1.0. Touches the recursion question on [[koka]] and [[d04-style-rules-become-laws|direction 4]].
- **Wing**: preflight code produces infrastructure and inflight code runs, in one typechecked program. Touches [[q11-platform-and-stdlib|Q11]].
- **Cangjie** (Huawei): 1.1.3 in May 2026, with an embedded AgentDSL. Touches [[d01-agents-write-the-code|direction 1]].
- *Considered and not listed* (no Mo decision touched): Carbon, Cairo, Noir, Sway, Leo, Juvix, Odin, C3, Hare, Onyx, Jakt, Amber, Pkl, Grain, ReScript, TypeScript 7.

**Built for AI authors, outside Claude's cluster** (agent-languages run; 49 entries, including 7 not in the catalogue)
- **Quasar** (UPenn): models write a Python subset that is transpiled underneath. Reports 42–56% faster execution and 52–53% fewer approvals (peer-review track; paper only). It challenges [[d01-agents-write-the-code|direction 1]]'s new-language bet.
- **ilo**: published its own failure. On Haiku 4.5, 11 of 13 scripted personas failed, and the spec grew from ~16K to ~51K tokens. Touches [[q09-compiler-diagnostics|Q9]].
- **X07**: source is a canonical JSON AST; edits are RFC 6902 JSON Patches; `x07 fix --write`. It is the inverse of [[q10-semantic-ids-and-editing|Q10]]'s text-first design.
- **NanoLang**: the compiler refuses any function without a shadow test; 627 stars; the author calls it "a total thought experiment". Touches [[p12-tests|pick 12]].
- **Pact** (Kikot, not Kadena's): `intent`, a `needs db, time` effect list, and `-> User or NotFound`. Touches [[d15-effects-via-capabilities|direction 15]] and [[p06-results-and-propagation|pick 6]].
- **Prove**: verbs such as `transforms` and `validates` encode intent, and contracts are enforced. Its licence *forbids AI training* on code written in it. Touches [[d01-agents-write-the-code|direction 1]]'s cold-start problem.
- **reqlan**: a requirements graph in which a dangling edge fails the checker; served over MCP. Touches [[d19-negative-space-is-the-contract|direction 19]].
- **Jacquard**: effects in signatures, and the runtime *refuses ungranted effects*; content-addressed identity. Touches [[d15-effects-via-capabilities|direction 15]] and [[q17-package-management-and-supply-chain|Q17]].
- **B-IR / Loom**: asked to design a language for themselves, models abandoned dense encodings and went back to readable keywords. Touches [[d26-developer-and-agent-happiness|direction 26]].
- **Faber Romanus**: keywords picked by a "council" of models, one highest-probability token per concept. Touches [[p01-blocks-keyword-end|pick 1]].
- **Magpie**: SSA form as the surface syntax; no evidence models write it better. A counterpoint to [[d27-simple-and-elegant-like-ruby|direction 27]].
- **BHC / hx**: argues Haskell loses agent benchmarks because of toolchain friction, not language design, so it fixes the toolchain instead. Touches [[d01-agents-write-the-code|direction 1]].
- **BAML**: 9.2K stars, the most adopted entry; repositioned from human to agent authorship; claims 30% fewer tokens (self-reported). Touches [[d01-agents-write-the-code|direction 1]].
- **Fabro**: an agent harness written as a Graphviz digraph; self-reported SWE-Bench-Lite 65.7% (GPT-5.4). Touches [[q14-first-real-program|Q14]] (the agent-harness option).
- **Codex** (Tedrow): claims a self-hosting, agent-written compiler, OS and TCP stack in weeks; everything is self-reported. Touches [[d01-agents-write-the-code|direction 1]].
- **Aether** (a Google Cloud org repo): an "LLM-first" language archived after 9 months. A survivorship datapoint for [[d01-agents-write-the-code|direction 1]].

**Older languages** (did-not-win run; absent from Claude's lane)
- **Mercury**: mode and determinism declarations (`is det`, `is semidet`) checked by the compiler. Touches [[p06-results-and-propagation|pick 6]] and [[d22-rust-plus-refinements-types|direction 22]].
- **Newspeak**: no global namespace and no static state; every module receives `platform` as a factory argument. It is the closest precedent for `main(platform)` in [[p13-capabilities-and-logging|pick 13]].
- **Joe-E**: capability safety as a *verified subset* of Java, with the library "tamed". Touches [[q17-package-management-and-supply-chain|Q17]].
- **Liquid Haskell**: optional refinement types restricted to a decidable logic (QF-EUFLIA). Touches [[d22-rust-plus-refinements-types|direction 22]].
- **Frank**: effect polymorphism without writing effect variables ("ambient ability"). Touches the closure-capture gap on [[koka]].
- **Limbo**: module types checked again at load time. Touches [[q17-package-management-and-supply-chain|Q17]], at the package boundary.
- **Oberon**: "no hidden mechanisms", watertight cross-module checking, fast compilation. Touches [[d23-compile-speed-first-class|direction 23]].
- **Oz / Mozart**: dataflow (single-assignment, blocking) variables as the concurrency primitive. Touches [[d12-concurrency-at-the-edges|direction 12]].
- **Cyclone, Clean, ATS, Alias Types / L³**: the ownership and uniqueness lineage beneath Rust and Perceus. Touches [[d13-local-var-and-inout|direction 13]].

## Ideas Robert's lane surfaced that Claude's lane missed

- **Three kinds of cost** (did-not-win run). Annotation cost collapses when agents write code; proof cost shrinks but stays; runtime and cultural costs don't move. It is a sharp test for [[d05-old-ideas-rethought-ai-first|direction 5]]: revive ideas that lost on *annotation* cost.
- **Absorption, not adoption.** Winning ideas enter the mainstream renamed (Cyclone into Rust, E into JS promises, Newsqueak into Go), and the original languages die. This is a positioning risk for Mo.
- **Rust removed typestate in 2012** over "cognitive burden", not unsoundness. It is the cleanest evidence for the linear `resource` question on [[austral]].
- **D had contracts for two decades and they went mostly unused.** The barrier was that the author got no visible payoff, not the notation. This supports [[d03-source-carries-its-evidence|direction 3]]: contracts pay off for the *reviewer*.
- **Whiley's subtyping by implication puts a solver inside the type checker.** Expect timeouts. This sets [[d22-rust-plus-refinements-types|direction 22]] against [[d23-compile-speed-first-class|direction 23]].
- **Wyvern's type-specific languages.** User-supplied strings structurally cannot become format strings. It is an injection defence to set beside `flows` ([[p09-module-header-and-never|pick 9]]).
- **Dhall's normal form.** Review generated configuration flattened into inert data. Touches [[d02-spec-altitude|direction 2]].
- **Lua's "mechanisms, not policy" is a human-scale virtue.** Agent-written code drifts in convention without enforced policy. This supports [[d26-developer-and-agent-happiness|direction 26]]'s "one way to write it".
- **Forth is the one case where agent authorship makes things worse:** non-local meaning is bad for human readers. It supports [[d02-spec-altitude|direction 2]].
- **Grammar-constrained decoding has made syntax validity nearly free** (agent-languages run). SynCode removes 96.07% of syntax errors in Python and Go, and AI-oriented grammar saves only 10–15% of tokens. The syntactic camp's headroom is mostly gone, which argues for keeping [[d26-developer-and-agent-happiness|direction 26]]'s readable syntax.
- **Cold start is the field's unaddressed risk** (Ronacher; anup.io). CodeAct found unchanged Python the best agent action language, up to 20% better. This is the null hypothesis for [[d01-agents-write-the-code|direction 1]].
- **Editions** (Rust 2024, emerging-languages run): opt-in, per-crate semantic changes. A mechanism for the compatibility question on [[go]].

## Where the two lanes disagree

- **Bosque's status.** [[bosque]]: BosqueCore last pushed on 3 Sep 2026, 198 stars, 1.0 declared in Nov 2024. The emerging-languages run: last commit 2022-10-27, "BosqueCore returns HTTP 404", excluded as dormant. **Claude's lane is better supported:** its API call succeeded, and the run appears to have queried `microsoft/BosqueCore` instead of `BosqueLanguage/BosqueCore`. The did-not-win run also files Bosque as "stays niche", a judgment rather than a factual conflict.
- **Hylo's activity.** [[hylo]]: effort moved to `hylo-new`, pushed 12 Sep 2026. The emerging-languages run: "active but slowed", with the last commit on 13 Jul 2026. The run inspected only the old repo, so **Claude's lane is more complete**.
- **Roc.** [[roc]] and the landscape: platforms, the Zig rewrite, 0.1.0 later in 2026. The emerging-languages run: "the official pages … do not name a single distinctive semantic idea", with its latest release at alpha4 (Aug 2025). **Not a factual conflict**, but the run missed platforms. Claude's sources (the language reference and Feldman's post) are deeper.
- **MoonBit's "33% faster than Rust".** [[moonbit]] reports it as a vendor number. The agent-languages run cites Chris Allen's rebuttal: corrected Rust is 3.2–3.4× *faster*, and the original gap was attributed to mimalloc. **The run adds decisive counter-evidence;** the MoonBit page should carry it, but it isn't edited here. On the 1.0 date, the run's "H1 2026, not found" is superseded by v0.10.0's Q3 target, so Claude's newer source wins there.
- **Benchmarks for agent-native languages.** [[agent-native-cluster]]: "LLM benchmarks comparing these languages: none found." The agent-languages run: VeraBench shows Vera 98.7%, Python 96.7%, TypeScript 99.7%. On a zero-training-data subset: Vera 98.2%, AILANG 96.8%, Aver 92.4%, Python 97.0%. **The run is right that numbers exist; Claude's lane missed them.** They are graded by Vera's own author, who also maintains the catalogue.
- **Star counts.** [[agent-native-cluster]] quotes the catalogue snapshot: Zero 3.3K, Codong 67, AILANG 26. The run's live API: Zero 5,360, Codong 73, AILANG 34, and Fabro rising from 1,221 to 1,595. **The run is newer;** both labelled their source.
- **The syntactic camp.** The landscape calls Axis's LL(1) grammar "the syntactic camp's strongest technical argument". The run: Axis went dormant a month after launch, and decoding research removes most syntax errors in existing languages. **The run is better evidenced.**
- **Gleam's version.** The landscape says v1.16 (Apr 2026); the run says v1.18.0 (29 Jul 2026). **The landscape entry is stale.**
- **Pel.** The landscape lists grammar-level capability control as Pel's idea to steal. Both runs: paper only, with no implementation or benchmark. **No conflict in substance,** but it lowers Pel's weight.
- **MoonBit's camp.** The catalogue and Claude's lane file it under verification; the agent-languages run files it as syntactic, because its argument is grammar shape plus a sampler. A classification choice with no effect on the page.

## Should the 13-entry shortlist change?

*Claude's recommendation. The shortlist is not changed here; Robert decides.* The comparison pass is already done, so "change" means follow-up pages.

- **No removals.** Bosque's "dormant" verdict rests on a failed repo lookup, and every other entry still touches a live Mo decision.
- **Add Motoko** as a comparison. It is the only 1.x language whose own docs say it is designed for AI agents, and it pairs that with actor isolation, which is Mo's [[d14-processes-are-the-only-identity|direction 14]] and [[d01-agents-write-the-code|direction 1]] together.
- **Add a concept page: the case against new languages.** Quasar, CodeAct, SynCode, token-sugar grammars, cold start, ilo's self-reported failure. It is the null hypothesis the v0 design doc must answer.
- **Add a concept page: capability module lineage.** Newspeak, Joe-E, Wyvern's type-specific languages, Limbo's load-time checks. They feed [[p13-capabilities-and-logging|pick 13]] and [[q17-package-management-and-supply-chain|Q17]] more directly than another single-language page would.
- **Refresh [[agent-native-cluster]]** with VeraBench, the ilo result and live star counts, rather than adding more languages.
- **Add a short note to [[moonbit]]** with the FFT rebuttal.
- **Maybe:** a combined page on annotation-cost ideas (Mercury determinism, Rust typestate, Liquid Haskell, Whiley), where the did-not-win run's thesis predicts revival.
- **Not recommended:** Mojo (not agent-authored by its own FAQ), the smart-contract and ZK languages, Forth, Curry.

## Related
- [[language-landscape]]
- [[comparison-synthesis-draft]]
- [[comparison-pass]]
- [[agent-native-cluster]]
- [[prompts-language-landscape]]
- [[d01-agents-write-the-code]]
- [[d05-old-ideas-rethought-ai-first]]
- [[d14-processes-are-the-only-identity]]
- [[d26-developer-and-agent-happiness]]
- [[q17-package-management-and-supply-chain]]
