---
title: "The case against new languages"
created: 2026-09-12
updated: 2026-09-12
type: concept
tags: [research, agents, philosophy]
sources: [raw/research-runs/llm-authored-programming-languages.pplx.md, raw/articles/ronacher-a-language-for-agents-2026.md, raw/articles/anup-markov-cold-start.md, raw/papers/codeact-executable-code-actions.md, raw/papers/syncode-grammar-augmentation.md]
confidence: medium
---

# The case against new languages

**The null hypothesis the v0 design doc must answer:** agents would do as well or better writing an *existing* language, with better tooling and checks around it, than writing Mo. This page states that case as strongly as the evidence allows. It carries **no verdict**. It is a follow-up from [[landscape-second-lane]] and the counterweight to [[d01-agents-write-the-code|direction 1]].

## The case, piece by piece

- **Cold start.** anup.io: "LLMs perform dramatically better on languages already in their training data, and a brand-new language has none."[139] Ronacher agrees that an agent does better on a language in its weights: "Obviously yes."[138] Robert's agent-languages run calls cold start "the field's unaddressed risk".[137] The measured version is on [[moonbit]]: zero-shot MoonBit and Gleam score close to 0% on hard tasks.[90]

- **CodeAct: the best agent language so far is Python, unchanged.** Across 17 LLMs, executable Python as the action format beats JSON and text formats by "up to 20% higher success rate".[140] The run calls it "the single most important piece of counter-evidence".[137]

- **Quasar: the strongest result keeps Python on the surface.** UPenn's Quasar has models write a Python *subset* and transpiles it to a language with guarantees underneath. It reports up to 56% faster execution and 53% fewer user approvals against a Python baseline.[137] The run's reading: that design "concedes the field's core premise". Also: paper only, no public implementation, still under review.[137]

- **SynCode: syntax errors are nearly free to remove in any language.** Grammar-constrained decoding "reduces 96.07% of syntax errors in generated Python and Go code" and eliminates all syntax errors in JSON.[141]

- **Token sugar: most token savings don't need a new language.** Sun et al. measured AI-oriented grammar at 10.4–13.5% fewer tokens. Their follow-up gets up to 15.1% source-token reduction from 799 reversible shorthand rules layered over existing Python, at near-identical pass@1.[137] anup.io adds that token-efficient formats such as TOON reach about 40% fewer tokens without any new language.[139]

- **ilo: the one self-published failure.** ilo, designed around total token cost, ran scripted agent personas on Haiku 4.5. One produced working code, one partial, eleven failed, and twelve of thirteen exhausted three attempts.[137] Its spec grew from about 16K to about 51K tokens, and per-generation savings were "eaten by context overhead in short sessions".[137]

- **Aether: an archived negative result.** A Google Cloud Platform repo for an "LLM-first" systems language, describing itself as a "demonstration of vibe coding", was archived on 7 May 2026 after 31 commits.[137]

- **BHC / hx: the problem is the toolchain, not the language.** Raffael Schneider argues Haskell's types-as-proofs already give models what they need. He attributes Haskell's weak agent benchmarks to toolchain friction, and builds a single `hx` front end and a new compiler instead of a new language. The claim is "asserted and unmeasured".[137]

- **Who measures anything.** Of 49 agent-language entries, only four publish head-to-head numbers against a mainstream language, and all but Quasar are graded by their own authors. No third-party reproduction exists.[137] The best self-graded result, Vera at 98.7%, still loses to TypeScript at 99.7% on the same suite.[137]

## The other side, stated briefly

These are the arguments Mo would lean on, not a rebuttal.

- **Ronacher, same essay:** "just because it's new also doesn't mean that the agent is going to struggle". Tooling and churn matter too, and falling coding costs make ecosystem breadth matter less.[138] He also names agent-hostile features of existing languages, such as reliance on a running LSP and exceptions agents "are afraid of".[138]
- **SWE-AGI:** agents with a tight toolchain loop built most of 22 spec-driven systems in MoonBit, a no-resource language (GPT-5.3-codex solved 19 of 22).[91]

## What Mo would have to show to beat this

- **Beat the baseline, not a strawman.** On the program menu ([[program-menu]]), agents writing Mo must beat agents writing a mainstream language (Go, or TypeScript, the strongest in VeraBench)[137] given the *same* checks: contracts via a verifier, tests, and linters. Measure time to green, defects found later, and human review minutes ([[d28-nothing-final-until-measured|direction 28]]).
- **Guarantees that can't be retrofitted.** A property an existing language can't enforce even with a Quasar-style subset or tooling, and that shows up in the measurement: capabilities as package permissions, no try/catch, bounded everything.
- **A spec altitude a human can actually use.** The claim that humans read contracts and `never` clauses instead of bodies ([[d02-spec-altitude|direction 2]]) needs a timed reading study, not an assertion.
- **Cold start closed by the toolchain, measured.** Zero-shot, then with diagnostics and repairs ([[q09-compiler-diagnostics|Q9]]), SWE-AGI-style,[91] reported against the same model on the baseline language.
- **Honest failure data.** Publish ilo-style persona runs,[137] including the bad ones, and have at least one benchmark graded by someone other than the Mo authors.
- **Token and context cost, counted in total.** Spec, skills and diagnostics count against Mo, the way ilo's context overhead ate its savings.[137]
- **A subset-of-an-existing-language control.** Test whether a Quasar-style route (Mo's checks over a Python or Go subset) gets most of the benefit.[137] If it does, that result changes the project.

## Related
- [[landscape-second-lane]]
- [[d01-agents-write-the-code]]
- [[d28-nothing-final-until-measured]]
- [[moonbit]]
- [[agent-native-cluster]]
- [[program-menu]]
- [[comparison-synthesis-draft]]

## Sources

[90] https://arxiv.org/abs/2606.16827 — No Resource, No Benchmarks, No Problem? Evaluating and Improving LLMs for Code Generation in No-Resource Languages (accepted IEEE TSE)
[91] https://arxiv.org/abs/2602.09447 — SWE-AGI: Benchmarking Specification-Driven Software Construction with MoonBit
[137] raw/research-runs/llm-authored-programming-languages.pplx.md — Robert's research run: LLM-Authored Programming Languages, evidence base 2023–2026 (Perplexity, landscape prompt 3)
[138] https://lucumr.pocoo.org/2026/2/9/a-language-for-agents — A Language For Agents (Armin Ronacher, Feb 2026)
[139] https://www.anup.io/til-markov-language — TIL: Markov language, and the cold-start problem (anup.io)
[140] https://arxiv.org/abs/2402.01030 — Executable Code Actions Elicit Better LLM Agents (CodeAct)
[141] https://arxiv.org/abs/2403.01632 — SynCode: LLM Generation with Grammar Augmentation
