---
title: "Research prompts: the language landscape (which languages deserve a deep comparison)"
created: 2026-09-12
updated: 2026-09-12
type: concept
tags: [research, philosophy]
sources: []
status: open
---

# Research prompts: the language landscape

Goal: a long list of languages — old, obscure, mainstream, brand-new or beta — each with the one idea worth stealing for Mo, so we can pick a shortlist for the comparison pass. Robert runs these with his deep-research tools; Claude runs the same sweep with web + arXiv + Exa. Results go in `raw/research-runs/` and get compared.

Context to paste with each prompt: *"Mo is a statically typed, Ruby-looking, Elixir-flavored functional language where AI agents write ~100% of the code and humans read only intent, contracts, and `never` clauses. Processes are the only mutable state, effects are capability parameters, style rules are compiler laws, every crash is a bug an agent fixes. We want to steal the best ideas from any language, old or new."*

## Prompt 1 — new and beta languages, 2022–2026
> List programming languages first released or substantially redesigned between 2022 and 2026, including ones still in alpha/beta or research prototypes (examples to seed, not limit: Hylo, Roc, Koka, Austral, Inko, Gleam, Unison, Mojo, MoonBit, Verse, Bend/HVM, Carbon, Vale, Flix, Effekt, Ante, Grain, Toka, Pel, Bosque). For each: one-paragraph summary, its single most distinctive idea, maturity (release stage, activity in 2026), and whether the idea is relevant to a language written by AI agents. Prefer primary sources (language site, papers, repo). Aim for 30+.

## Prompt 2 — older and obscure languages with ideas ahead of their time
> Survey older or obscure programming languages (1970–2021) that contained a design idea that mainstream languages later adopted or still have not: contracts (Eiffel, SPARK Ada, D, Cobra, Whiley, Dafny), capability security (E, Joe-E, Wyvern, Newspeak), totality and bounded execution (Idris, Agda, Dhall, Bosque), fault tolerance (Erlang, Pony, Oz), simplicity by law (Oberon, Go's ancestors, Lua, Forth), transactional or logic semantics (Verse, Mercury, Curry, Prolog), effect systems (Koka's ancestors, Eff, Frank, Links), regions and linearity (Cyclone, ATS, Clean, Rust's ancestors). For each: the idea, why it did not win, and whether the reason still applies when agents write the code. Aim for 25+.

## Prompt 3 — languages built for AI agents to write
> Find every programming language, DSL, or serious proposal (2023–2026) explicitly designed for LLMs or AI agents as the primary authors of code — including the GitHub catalogue "aallan/agentlanguages", Pel, MoonBit's AI-native toolchain, PACT-Lang, and any others. Classify each as syntactic (easier for models to emit), verification-oriented (contracts, proofs, checkable specs), or orchestration-oriented (agents calling agents). For each: status, what it claims, evidence it works, and its biggest weakness. Include academic papers on LLM-friendly language design and grammar constraints for constrained decoding.

## Related
- [[prompts-q17-supply-chain]]
- [[steal-list]]
- [[roadmap]]
