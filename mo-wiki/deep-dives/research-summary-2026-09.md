---
title: "Research summary, Sep 2026"
created: 2026-09-12
updated: 2026-09-13
type: deep-dive
tags: [research]
sources: [raw/notion/design-journal-2026-09-12.md]
---

# Research summary, Sep 2026

### Headline
Nobody has built this yet. Mojo hit 1.0 in Aug 2026 but is "for AI" in the sense of running AI workloads. Pel is a Lisp-ish agent-orchestration language. The closest real design is a blog sketch (PACT-Lang) that stayed a sketch. The space is open.
### Three findings that shape everything
- **Training-data gravity is real.** Dan Luu benchmarked agents building a full zstd decoder and modifying Pandoc across many languages. Obscure languages did badly even when denser. Popularity correlated with correctness. A new language starts with zero corpus: **our single biggest risk.**
- **Strictness helps models converge.** Go-for-agents debate, Dafny vericoding (verification success 68% → 97% in one year), verified Rust via Verus and Aeneas. Agents thrive when the compiler rejects wrong programs loudly and there is one way to do things.
- **The ideal AI language is one humans keep rejecting.** Explicit effects, exhaustive result types, contracts, totality. Friction for a human typist, a gift for an agent that iterates in a loop and never tires of annotations.
### Smaller things worth stealing
- Token efficiency matters less than people think at scale (Dan Luu). Don't contort syntax for it.
- "Lingering Authority" paper: revocable, time-bounded capabilities for coding agents; separate permission from actual effect. Fits an effect system perfectly.
- Research trend toward compilers emitting structured diagnostics (category, cause, suggested fix) for agent feedback loops.
### Sources
- [AkitaOnRails: Best programming language for LLMs](https://akitaonrails.com/en/2026/02/09/ai-agents-best-programming-language-for-llms/)
- [Dan Luu: token efficiency and correctness by language](https://danluu.com/pl-tokens/)
- [Do programming languages still matter to your AI coding agent teammate?](https://arxiv.org/pdf/2606.13763)
- [Lingering Authority: Revocable Resource-and-Effect Capabilities for Coding Agents](https://arxiv.org/pdf/2606.22504)
- [A benchmark for vericoding (POPL 2026)](https://popl26.sigplan.org/details/dafny-2026-papers/13/A-benchmark-for-vericoding-formally-verified-program-synthesis)
- [Pel: A Programming Language for Orchestrating AI Agents](https://arxiv.org/abs/2505.13453)
- [A case for Go as the best language for AI agents (HN)](https://news.ycombinator.com/item?id=47222270)
- [Mojo hits 1.0](https://www.theregister.com/ai-and-ml/2026/08/12/modulars-mojo-programming-language-hits-10-milestone/5286545)
- [Aeneas: Bridging Rust to Lean](https://lean-lang.org/use-cases/aeneas/)
- [Token Sugar (ASE 2025)](https://dl.acm.org/doi/10.1109/ASE63991.2025.00201)
- [AI Coders Are Among Us: Rethinking Grammar](https://arxiv.org/pdf/2404.16333)

## Session 6 addendum (Fable, 13 Sep, from the agent-authoring deep run)

The numbers that bound Mo's cold start and its diagnostics bet, from [[prompts-mo-parallel-tracks]]'s third run.^[raw/research-runs/agent-authoring-research-frontier.pplx.md] A no-resource language gets 9 percent pass@1 against Python's 79, and on Gleam nine in ten generations did not compile; documentation in context moves the odds 1.2 to 11 times; further pre-training on 28 million tokens of a new language lifts hard tasks to 25 to 30 percent, still far from parity. On the diagnostics bet: the reference measurement is RustAssistant, 74 percent of real compiler errors fixed by a model given structured errors in a repair loop, and prompt shape alone moved ownership errors from 10 to 74 percent; structured test feedback beats structured compiler feedback beats prose. On the counter-position: a Python subset with a new discipline (Quasar) produced about seven times fewer erroneous programs than free Python without losing fluency, and the run's four tests a new language must pass are on [[case-against-new-languages]]. Nothing in the run measures capabilities or deterministic replay for agents head to head; the theoretical case is made and the experiment does not exist, which makes Mo's programs the first data.

## Related
- [[plang-history-2026-09-index]]
- [[fork-in-the-road]]
- [[steal-list]]
- [[idea-backlog]]
