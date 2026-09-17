---
title: "Language design for LLMs: what is actually measured"
created: 2026-09-13
updated: 2026-09-17
type: concept
tags: [research, laws, meta]
sources: [raw/research-runs/2026-09-13-papers-llm-facing.pplx.md]
confidence: medium
contested: true
contradictions: [research-agenda-2026-09-response]
---

# Language design for LLMs: what is actually measured

Cluster B of the 2026-09-13 research run: token cost, cold start for an unknown language, whether strictness helps agents, how humans review agent code, and what style constraints actually buy. Confidence is medium because almost nothing here isolates a single language feature.

## Mo starts in the bottom tier, by construction

A reproducible resource classification groups 646 languages into four tiers and finds that 1.9% of languages (Tier 3, High) account for 74.6% of all tokens across seven major corpora, while 71.7% of languages (Tier 0, Scarce) contribute 1.0% ([arXiv:2604.00239](https://arxiv.org/abs/2604.00239)).

A TOSEM survey of 111 papers filtered from over 27,000 studies notes that even Rust, with 3.5 million users, cannot fully exploit LLM capabilities, and that no standard low-resource benchmark exists ([arXiv:2410.03981](https://arxiv.org/abs/2410.03981)).

Judgment: adoption will not fix Mo's corpus problem. Mo has to manufacture its corpus and its eval.

## Cold start: validated synthetic data, at three known scales

| Approach | Scale reported | Source |
|---|---|---|
| Translate high-resource code, keep only test-validated results | "tens of thousands" of items, 5 languages | [2308.09895](https://arxiv.org/abs/2308.09895) |
| Domain instruction synthesis (HPC) | 122k+ samples, near-GPT-4 in domain | [ISC 2025 PDF](https://www.cs.umd.edu/~bhatele/pubs/pdf/2025/isc2025.pdf) |
| Verifier-filtered program-and-proof synthesis | 6.9M verified Rust programs | [2602.04910](https://arxiv.org/abs/2602.04910) |

Two levers make this cheaper. Cross-lingual transfer beats zero-shot across 10-41 languages on five tasks, with a predictor that identifies good source languages ([arXiv:2310.16937](https://arxiv.org/abs/2310.16937)), and an embedding study over 21 linguistic features and 19 languages finds latent language families whose proximity improves transfer, curriculum order, and intermediary translation ([arXiv:2512.19509](https://arxiv.org/abs/2512.19509)).

The risk is that agents route around the language entirely. Across six agents and four esoteric languages, the strongest models spontaneously wrote Python metaprograms that emit the target language, and performance dropped substantially when that was restricted ([arXiv:2606.10933](https://arxiv.org/abs/2606.10933)). An earlier system made this a deliberate design: generate an intermediate language the model knows, then compile down to the very low-resource target ([arXiv:2406.03636](https://arxiv.org/abs/2406.03636)).

Judgment: Mo's evals must record whether the model wrote Mo or wrote a Mo generator, or the cold-start numbers measure the wrong thing.

17 Sep 2026, recorded: every round so far wrote Mo directly; no worker wrote a generator.

## Grammar and types at generation time remove the cheap errors

- Grammar-constrained decoding: "a 96.07% reduction in syntax errors for Python and Go code generation" ([arXiv:2403.01632](https://arxiv.org/abs/2403.01632)).
- Type-constrained decoding "reduces compilation errors by more than half" and lifts functional correctness ([arXiv:2504.09246](https://arxiv.org/abs/2504.09246)).
- Grammar prompting needs no decoder integration: put the BNF in the demonstrations ([arXiv:2305.19234](https://arxiv.org/abs/2305.19234)).
- Precompute for constrained decoding is now 17.71x faster, so regenerating a mask store per grammar change is affordable ([arXiv:2502.05111](https://arxiv.org/abs/2502.05111)).
- Few-shot examples raise grammar conformance more than scale across 39 open models from 0.5B to 32B ([arXiv:2605.15865](https://arxiv.org/abs/2605.15865)).

The caution, from roughly 10,000 real JSON schemas over six frameworks: "constrained decoding enforces syntactic validity but may degrade semantic fidelity" ([arXiv:2501.10868](https://arxiv.org/abs/2501.10868)).

## Token cost is real but confounded

Removing formatting cut input tokens by 24.5% on average across ten models and four languages with no measured performance loss, and prompting or fine-tuning cut generated code length by up to 36.1% without compromising correctness ([arXiv:2508.13666](https://arxiv.org/abs/2508.13666)).

Language-level token gaps exist but are fragile. A blog eval reports "a very meaningful gap of 2.6x between C (the least token efficient language I compared) and Clojure (the most efficient)" and J at "just 70 tokens average, nearly half of Clojure (109 tokens)" — while also documenting a harness bug in which a stray symlink made every language run a Go binary, and a single library gotcha causing test failures in 36 of 40 Clojure programs at medium effort ([danluu.com/pl-tokens](https://danluu.com/pl-tokens/)). Not peer-reviewed.

Direction of effect flips by model: Chinese prompts cost 1.28x more tokens on one model and fewer on another, with generally lower success rates than English ([arXiv:2604.14210](https://arxiv.org/abs/2604.14210)). And LLM-generated code reaches "only around 62% of human efficiency on average" at best across six languages ([arXiv:2505.13004](https://arxiv.org/abs/2505.13004)).

Judgment: no Mo compactness claim should be made from one tokenizer or one task suite.

## Does strictness help agents? Thin and mixed

For: the only feature-isolating study found reports that detailed type errors improve agent repair, and that a type system helps more than test failures alone ([arXiv:2606.01522](https://arxiv.org/abs/2606.01522)).

Against: a production Rust agent ported to Python shrank 648K LOC to 41K (15.9x) and reached near-parity on agentic benchmarks, 73.8% versus 70.0% on SWE-bench Verified and 42.5% versus 47.5% on Terminal-Bench ([arXiv:2604.11518](https://arxiv.org/abs/2604.11518)). Across 721 functional-programming tasks, error rates stayed significantly higher in pure Haskell and OCaml than in hybrid Scala or imperative Java, and models frequently wrote imperative patterns in functional languages ([arXiv:2601.02060](https://arxiv.org/abs/2601.02060)).

Adjacent: over 500k samples show AI code is simpler and more repetitive but more prone to unused constructs, hardcoded debugging, and high-risk vulnerabilities ([arXiv:2508.21634](https://arxiv.org/abs/2508.21634)); 200 security tasks show models failing to use modern language security features ([arXiv:2502.01853](https://arxiv.org/abs/2502.01853)); a taxonomy of 333 bugs names ten recurring patterns including wrong input type, hallucinated object, and missing corner case ([arXiv:2403.08937](https://arxiv.org/abs/2403.08937)); and models perform poorly at static analysis tasks themselves, with no transfer in either direction ([arXiv:2505.12118](https://arxiv.org/abs/2505.12118)).

Judgment: argue Mo's strictness from verifiability and review cost. The raw agent-success evidence does not support it yet, and the pure-functional penalty is a live risk for Mo's shape.

## Shape laws: the weakest-supported part of Mo

After controlling for code length, classical complexity metrics show no consistent correlation with LLM performance, while an LLM-oriented metric built from entropy-based semantic units and branching divergence does, and lowering it improves performance ([arXiv:2602.07882](https://arxiv.org/abs/2602.07882)).

Correctness and quality barely correlate: Pearson r = 0.075 across 85 C# tasks and 340 solutions, so pass@k rankings misrepresent quality ([arXiv:2608.22529](https://arxiv.org/abs/2608.22529)).

Prompt-level style control decays as code grows. Over N=160 paired programs, combined instruction-plus-example prompts gave the best initial compression and expansion discipline, while examples alone had no expansion discipline ([arXiv:2511.13972](https://arxiv.org/abs/2511.13972)). Persistent machine-readable rules are already common practice: 401 repositories with cursor rules cluster into Conventions, Guidelines, Project Information, LLM Directives, Examples ([arXiv:2512.18925](https://arxiv.org/abs/2512.18925)).

Judgment: keep the length law, which has support; justify nesting and parameter caps as human-review economics; consider restating shape laws in compositional-depth terms.

17 Sep 2026, outcome: the 500-line law is gone and the shape laws became project settings on 14 Sep.

## Humans review worse over time

400 repeat reviewers submitting 11,429 reviews over seven months approved 30.1% early and 36.8% late — a 6.7-point rise across the population, while the +14.5 points is the cumulative within-reviewer gradient across experience deciles, a different measure (noted 17 Sep 2026) — with review latency up 3.5x and inline comments down 22% ([arXiv:2606.22721](https://arxiv.org/abs/2606.22721)).

Practitioners (N=17, validated N=43) describe reviewing multi-file LLM changes as trust calibration rather than diffing, and want risk signals per line and per file; 63% expected reduced overall review effort from such a workflow ([arXiv:2606.01969](https://arxiv.org/abs/2606.01969)).

Labelling code as LLM-generated increased fixation time without changing thoroughness ([arXiv:2606.26505](https://arxiv.org/abs/2606.26505)), while an earlier study with 28 participants found provenance awareness improved performance at higher cognitive load ([arXiv:2405.16081](https://arxiv.org/abs/2405.16081)). Agent-written code is already at human readability parity in one industrial case ([arXiv:2501.11264](https://arxiv.org/abs/2501.11264)) and across 5,869 scenarios, where function signatures, constraints and style descriptions were the most influential prompt dimensions ([arXiv:2605.13280](https://arxiv.org/abs/2605.13280)).

Finally, developer intuition about agent productivity was wrong by about 40 points in a randomized trial: 16 developers on 246 tasks were 19% slower with early-2025 AI tools while forecasting a 24% speedup ([metr.org](https://metr.org/Early_2025_AI_Experienced_OS_Devs_Study-paper.pdf)).

## What Mo could take

| idea | maps to | status |
|---|---|---|
| Manufacture a verifier-filtered Mo corpus (~100k scale first) | [[d28-nothing-final-until-measured]] | new idea for Mo |
| Pick corpus source languages by predicted transfer, not taste | [[d07-elixir-flavored-functional]] | new idea for Mo |
| Ship a machine-readable grammar plus few-shot pack | [[d35-mo-is-an-ecosystem]] | strengthens Mo |
| Detect agents writing Mo generators instead of Mo | [[d01-agents-write-the-code]] | new idea for Mo |
| Compact wire form for agents, formatted form for humans | [[d26-developer-and-agent-happiness]] | new idea for Mo |
| Numeric shape laws as model-performance levers | [[q12-law-numbers]] | contradicts Mo |
| Length limits, which do survive measurement | [[q12-law-numbers]] | already in Mo |
| Compiler-enforced rules instead of prompt-level rules | [[d04-style-rules-become-laws]] | strengthens Mo |
| Emit review risk signals: capabilities touched, contracts changed | [[d03-source-carries-its-evidence]] | strengthens Mo |
| Pure-functional, no-`while` shape carries a measured error-rate risk | [[d10-immutable-by-default]] | contradicts Mo |
| Multi-tokenizer check before any compactness claim | [[d28-nothing-final-until-measured]] | new idea for Mo |

17 Sep 2026: both "contradicts Mo" rows were ruled on 13 Sep — see [[research-agenda-2026-09-response]]. Rounds 5 and 6 ran on them.

## Related

- [[q12-law-numbers]]
- [[d04-style-rules-become-laws]]
- [[d28-nothing-final-until-measured]]
- [[case-against-new-languages]]
- [[d01-agents-write-the-code]]
- [[d26-developer-and-agent-happiness]]
- [[prompts-research-agenda-2026-09]]
- [[d41-small-model-round]]
- [[control-run-9]]
- [[research-agenda-2026-09-response]]
