---
title: "PL history research, Sep 2026: bundle index"
created: 2026-09-13
updated: 2026-09-17
type: deep-dive
tags: [history, research]
sources:
  - "../raw/plang-history-2026-09/synthesis/00_README.md"
---
# PL history research, Sep 2026: bundle index

> **17 Sep 2026.** This page is the 13 Sep synthesis of an external research run. The Mo it describes — brace syntax, effect rows, a Rust implementation, a package registry, an RFC process — was never Mo's design. Mo's decisions are the spec chapters under `spec/design-v0/` and the [[decision-log]]. Read this page as landscape only.

## Headline

A 2026-09 research bundle covering ninety years of programming-language history, eight design camps, an implementation engineering menu, and a synthesis for Mo. Every wiki summary in this section links back to the raw material under [`raw/plang-history-2026-09/`](../raw/plang-history-2026-09/).

## What's in the bundle

The bundle is organized as five nested layers, from surveys to Mo-specific decisions:

**History (three eras)** — a source-cited walk through the field:

- [[plang-history-lambda-to-1970s]] — Lambda calculus through the paradigm explosion of the 1970s
- [[plang-history-1980s-to-2000s]] — Objects, functional purity, the internet, and virtual machines
- [[plang-history-2010-to-2026]] — Systems renaissance, verification, and the AI era

**Design camps** — the ideological landscape:

- [[plang-design-camps]] — Eight camps: paradigm, types, memory, concurrency, syntax, compilation, philosophy, ecosystem

**Implementation menu** — the engineering choices:

- [[plang-implementation-menu]] — Parsing, IRs, back ends, GCs, package managers, tooling

**Mo synthesis** — the point of the exercise:

- [[plang-mo-synthesis]] — What history says to Mo
- [[plang-decision-matrix]] — 18 axes, each with a Mo direction and rationale

## Language-by-language deep-dives

Fifteen numbered deep-dives sit under `raw/plang-history-2026-09/deep-dives/`; thirteen of them are summarized in [`research/languages/`](../research/languages/), the other two (rust, elixir) in `research/comparisons/`:

- [[c]] · [[lisp]] · [[smalltalk]] · [[ml]] · [[haskell]] · [[erlang]] · [[cpp]] · [[java]] · [[python]] · [[javascript]] · [[go-history]] · [[zig]] · [[dependent-types]]
- ([[rust]] — already covered under `research/comparisons/rust.md`)
- Elixir has both a language page ([[elixir]] under comparisons) and is treated in the history summaries.

## Three findings that shape everything

- **Annotation economics are inverted.** When agents write code, an annotation that costs the language designer thirty minutes and buys machine-verifiable structure is nearly free — the human review it saves compounds forever. Ceremony that was expensive to humans is cheap to agents.
- **Supply-chain security is the highest-leverage decision.** Every modern package ecosystem (npm, PyPI, crates.io) has produced live incidents (typosquatting, dependency confusion, post-install scripts, slopsquatting). A language whose module and dependency system is validated at edit time avoids an entire class of production breach. See [[q17-package-management-and-supply-chain]] and [[d30-supply-chain-security]].
- **Effects + capabilities + regions are complementary, not competing.** The 2010s treated them as rival research programs; the 2020s (Austral, Hylo, Koka, Roc, OCaml 5) show they compose well. Mo's [[d15-effects-via-capabilities]] takes this seriously.

## How to use the wiki pages

- The **history pages** are for orientation — read them once, refer back for citations.
- The **camp and implementation pages** are for design decisions — read them when you're about to choose a direction.
- The **Mo synthesis and decision matrix** are the working outputs — this is where "what should Mo do?" gets answered with links to specific research.
- The **language deep-dives** are for depth on a single tradition. Read them when a specific language is being cited as a model or anti-model for Mo.

## Cross-references

- Existing overview: [[research-summary-2026-09]]
- Existing shortlists: [[steal-list]], [[fork-in-the-road]]
- Related concepts already in the wiki: [[language-landscape]], [[case-against-new-languages]], [[capability-module-lineage]], [[supply-chain-defenses]], [[comparison-synthesis-draft]]

## Sources

- [Bundle README](../raw/plang-history-2026-09/synthesis/00_README.md)
- [Executive summary](../raw/plang-history-2026-09/synthesis/executive_summary.md)
- [Mo synthesis](../raw/plang-history-2026-09/synthesis/mo_synthesis.md)
- [Decision matrix](../raw/plang-history-2026-09/synthesis/decision_matrix.md)


## Related

- [[research-summary-2026-09]]
- [[steal-list]]
- [[language-landscape]]
- [[capability-module-lineage]]
