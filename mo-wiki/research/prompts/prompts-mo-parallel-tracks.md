---
title: "Research prompts: Mo's three parallel research tracks"
created: 2026-09-13
updated: 2026-09-13
type: concept
tags: [research, meta]
sources: [raw/research-runs/mo-parallel-tracks-brief-1-empirical.pplx.md, raw/research-runs/mo-parallel-tracks-brief-2-ecosystem.pplx.md, raw/research-runs/mo-parallel-tracks-brief-3-agent-authoring.pplx.md]
status: answered
---

# Research prompts: Mo's three parallel research tracks

Origin: [[session-02|session 2]] (Perplexity task `2c696217`), when Robert said "I honestly think all three of these are their own research projects and maybe you can help me run these in parallel to speed this up." Claude wrote three self-contained deep-research briefs for Perplexity, Robert ran each in its own dedicated session, and the long reports came back into `raw/research-runs/`. Each brief and its answering deep-run report are paired below.

Context to paste with each prompt: *"Mo is a statically typed, Ruby-looking, Elixir-flavored functional language where AI agents write ~100% of the code and humans read only intent, contracts, and `never` clauses. Processes are the only mutable state, effects are capability parameters, style rules are compiler laws, every crash is a bug an agent fixes. We want evidence, not vibes."*

## Prompt 1 — Empirical validation
> If you built a new general-purpose programming language for AI agents to author, adopted by human engineering teams, using contracts, capabilities, effect controls, bounded resource use, exhaustive error handling, and deterministic simulation — how would you actually prove or disprove the central claim that this beats an existing mainstream language with the same checks bolted on? Survey how new languages have historically been evaluated, how AI coding tools are evaluated today, how verification systems are evaluated. Then design rigorous experimental protocols: the null-hypothesis experiment, the cold-start experiment, the maintainability experiment, the human-review experiment. Reference primary sources (published papers, Dan Luu's benchmarks, DafnyBench, SWE-AGI, the "No Resource, No Benchmarks" study).

- Brief: `raw/research-runs/mo-parallel-tracks-brief-1-empirical.pplx.md`
- Deep run: `raw/research-runs/empirical-validation-agent-language.pplx.md`
- Touches: [[d28-nothing-final-until-measured|d28]], [[d01-agents-write-the-code|d01]], [[d03-source-carries-its-evidence|d03]]

## Prompt 2 — Ecosystem, standard library, and platform depth
> Survey stdlib and ecosystem strategy for a language whose primary authors are AI agents and whose customers are engineering teams building production services. How Go, Rust, Elixir, Python, and JavaScript grew their stdlibs; the Laravel/Phoenix/shadcn "first-party kits" pattern; what "recipes over dependencies" looks like when the language is agent-first; how supply-chain defaults (Go's checksum db, npm provenance, PyPI Trusted Publishers) shape adoption. Then take a position on Mo's stdlib and platform strategy.

- Brief: `raw/research-runs/mo-parallel-tracks-brief-2-ecosystem.pplx.md`
- Deep run: `raw/research-runs/ecosystem-stdlib-platform-depth.pplx.md`
- Touches: [[q11-platform-and-stdlib|Q11]], [[d35-mo-is-an-ecosystem|d35]], [[d34-packages-are-recipes|d34]], [[d30-supply-chain-security|d30]]

## Prompt 3 — The agent-authoring research frontier
> Map the current research frontier on how programming languages and toolchains should be designed for a world in which LLM-based coding agents author most code. Training-data gravity and cold start. The "language for LLMs" thesis. Structured diagnostics as the agent's teacher. Verification-in-the-loop (Dafny vericoding, Verus, Aeneas). Effect systems and capabilities for agents. Agent-authored language attempts (Pel, Quasar, Markov, PACT-Lang, the agentlanguages.dev catalogue). Where the interesting research is going and what a serious language design should take from it.

- Brief: `raw/research-runs/mo-parallel-tracks-brief-3-agent-authoring.pplx.md`
- Deep run: `raw/research-runs/agent-authoring-research-frontier.pplx.md`
- Touches: [[d01-agents-write-the-code|d01]], [[d02-spec-altitude|d02]], [[d15-effects-via-capabilities|d15]], [[q09-compiler-diagnostics|Q9]]

## What these runs added to the vault

The three deep runs and the three briefs are all in `raw/research-runs/`. They are new inputs for Fable, not yet synthesized into a `research/concepts/` page. When Fable takes them up, the natural output shape is:

- an **empirical-validation-plan** concept page that turns the report into a concrete evaluation protocol for Mo, and revises the "nothing final until measured" language on [[d28-nothing-final-until-measured|d28]] with named experiments
- an **ecosystem-strategy** concept page that turns the ecosystem report into Mo's stdlib scope and kit list, feeding [[q11-platform-and-stdlib|Q11]] and the `directions/d34–d35` cluster
- additions to [[case-against-new-languages]] and [[research-summary-2026-09]] from the agent-authoring frontier report — especially the Giagnorio et al. numbers (79% Python vs 9% no-resource pass@1), the Berger et al. reproduction protocol, and the Lingering Authority capability model

The three adjacent Perplexity runs from the same week (search toolbox, sandbox providers, Rust-for-ETL) are filed under `raw/articles/` as `pplx-*` and are context for Robert's other projects, not this wiki.

## Related

- [[prompts-language-landscape]]
- [[prompts-q17-supply-chain]]
- [[research-summary-2026-09]]
- [[case-against-new-languages]]
- [[session-06]]
