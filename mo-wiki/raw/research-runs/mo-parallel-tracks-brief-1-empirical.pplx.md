---
tool: Perplexity
prompt: prompts-mo-parallel-tracks / brief for prompt 1
run: 2026-09-13
run_by: Claude (via Perplexity session 2c696217)
session_url: https://www.perplexity.ai/computer/tasks/2c696217-8105-4eea-98c1-c131b407077c
sha256: d77efa84d7bb7a20a657cd46dcb03c9addd2799c2bd856c09e3de013dfbf83d6
---
# Deep Research Prompt 1: Empirical Validation of a New Programming Language for AI Agents

## Context and premise

A new general-purpose programming language is being designed with the explicit goal of being written primarily by AI coding agents, adopted by human engineering teams, and used to build real production software. The design bets heavily on machine-checkable guarantees (contracts, capabilities, effect controls, bounded resource use, exhaustive error handling, deterministic simulation) and on a compiler and toolchain that treats the AI agent as its primary user (structured diagnostics, edit-by-ID, fast feedback loops, aggressive verification).

The central risk: the language may be strictly worse than an existing mainstream language (e.g., Go, TypeScript, Python, Rust) with the same checks bolted on around it, once you account for training-data gravity, ecosystem, and cold-start effects on agents. This is the null hypothesis.

The people building this language want to prove (or disprove) their central claim with real evidence, not vibes. They need to know:

1. What experiments would actually demonstrate that a new agent-authored language beats mainstream baselines?
2. What experiments would prove it does not?
3. How have comparable claims been evaluated in the past (programming languages, verification systems, AI coding tools, developer tools)?
4. What are the standard failure modes of such evaluations, and how are they defended against?

## Your task

Produce a comprehensive, evidence-rich research report that a language designer could use to design a rigorous, publication-quality evaluation program for their language. Assume the reader is a highly technical language designer and engineering leader who understands programming language design, verification, LLMs, and software engineering research methodology. Do not be shallow. Do not summarize the obvious. Go deep on the parts that matter.

## What to cover

### Part 1: How have new programming languages historically been evaluated?

- Survey the major published evaluations of new programming languages over the last 20 years: Rust, Go, Elixir, Kotlin, Swift, TypeScript, Zig, Roc, MoonBit, Haskell, OCaml, Erlang, and any others that produced rigorous evaluation evidence.
- For each: what did they measure, against what baseline, with what methodology, and what did the results actually show?
- Identify what a "language evaluation" typically consists of: microbenchmarks, macro benchmarks, developer productivity studies, defect studies, longitudinal case studies, industry adoption metrics, satisfaction surveys. Which of these produced actionable evidence and which produced noise?
- Which languages were evaluated well and which are still argued about because evaluation was weak? What can we learn from both?

### Part 2: How are AI coding tools and agent-authored code currently evaluated?

- Survey the current state of the art in evaluating LLMs and AI agents at code generation. Cover benchmarks (HumanEval, MBPP, SWE-bench, LiveCodeBench, VeraBench, SWE-AGI, DafnyBench, ARC-AGI-style code tasks, and any others), their strengths, their known flaws, and the meta-critiques of them.
- What does the research literature say about how to evaluate an agent's ability to author, maintain, and debug real software? What are the leaderboards missing?
- Specifically: how has the effect of programming language choice on agent performance been measured? Look at Dan Luu's work, the anup.io "training-data gravity" argument, CodeAct (Python as action language), Quasar (Python subset with guarantees), SWE-AGI with MoonBit, "No Resource, No Benchmarks, No Problem?" (arXiv 2606.16827), and any other primary sources you can find.
- What is known about how a language's design characteristics (verbosity, static/dynamic typing, error handling style, effect systems, verification support) actually affect agent success rates, defect rates, iteration counts, and token costs?

### Part 3: How is formal verification and contract-based programming evaluated?

- Survey rigorous evaluations of contract-based, refinement-typed, or fully verified languages: SPARK/Ada, Dafny, F*, Lean, Idris, Liquid Haskell, Verus, Aeneas, Bosque, TLA+, and any others.
- What evidence exists that mandatory contracts, effects, or capabilities actually reduce defects in real systems? What evidence exists that they do not, or that the friction outweighs the benefit?
- What are the best experimental designs to evaluate the impact of a verification mechanism on defect rate, development time, and maintainability? Reference specific published studies.
- The vericoding literature (Dafny going from 68% to 97% verification success in a year via LLM-assisted verification) — what were the actual experimental designs, what are their limitations, and what would it take to run the equivalent study for a new language?

### Part 4: Experimental design — what would a rigorous evaluation look like?

This is the highest-value section. Produce concrete, executable experimental protocols. For each, name the hypothesis, the baseline, the measurement, the threshold for success, the confounders, and the statistical analysis plan.

- **The null-hypothesis experiment.** How would you design a controlled comparison between agents writing a new language X versus agents writing a mainstream language (Go, TypeScript, Python) with equivalent checks bolted on (linters, contract libraries, capability shims, verifier harnesses)? What tasks, how many, from what sources, what metrics, what threshold?
- **The cold-start experiment.** How do you measure and mitigate the training-data gravity effect for a language with zero corpus? What is the evidence that structured diagnostics, in-context guidance, and toolchain-as-teacher can close the gap? How would you measure it? What is the ceiling, and what would prove the gap uncloseable?
- **The maintainability experiment.** How do you measure whether code written by agents in a new language is easier or harder to modify, debug, and extend six months later than code in a mainstream language? What are the best-known designs for longitudinal maintenance studies, and what have they shown?
- **The human review experiment.** If the claim is that humans read intent (signatures, contracts, tests) rather than bodies, how do you actually test whether humans can catch bugs, understand behavior, and make correct architectural decisions from the intent layer alone? Are there published studies on spec-altitude reading, code review comprehension, or specification review that inform this?
- **The defect study.** How do you measure whether a language's mandatory checks (contracts, capabilities, exhaustive matching, no exceptions) actually catch bugs that would have shipped in a mainstream language? What is the evidence from Rust, Elixir, Ada/SPARK, and others on this specific question? What experimental design would produce credible evidence?
- **The token and total-cost experiment.** How do you honestly account for all the tokens an agent spends learning a new language (skills, error catalogs, guidance, iteration on diagnostics) versus writing in a familiar language? The ilo case study suggests context overhead can eat per-generation savings; what is the right accounting methodology?
- **The agent-friendliness ablation.** How would you isolate which specific language and toolchain features (structured diagnostics, edit-by-ID, capability-checked effects, fast compile loop, deterministic simulation, contract runtime) actually improve agent success rates, versus which are cosmetic? What is the smallest set of features that captures most of the benefit?

### Part 5: Threat models and standard failure modes of language evaluation

- What are the known ways language evaluations produce misleading results? Cover: cherry-picked benchmarks, author-graded studies, publication bias, the "our language beat Language X on our benchmark" pattern that dominates the field, the "expert vs novice" confound, the "trained on this codebase" confound.
- What are the honesty practices that separate credible evaluations from spin? What do the best-run PL evaluations do that the worst do not?
- What are the pre-registration, blinding, and reproducibility practices that would apply to AI-coding-language evaluation? What has been tried, and what is missing?
- Specifically address: how do you avoid measuring your own model's ability to game your own benchmark? How do you handle the fact that model capabilities change monthly? How do you evaluate a language whose value is claimed to grow over time as agents get better?

### Part 6: What kinds of results would move the field?

- What single experiment, if it produced a positive result, would most strongly validate the thesis "a new language optimized for agent authorship can beat mainstream baselines"?
- What single experiment, if it produced a negative result, would most strongly refute it? (What is the falsification?)
- What would a small (3–5 experiments) evaluation program look like that maximizes credibility per unit of effort in the first 12 months?
- What would a 24-month program look like that could produce publication-quality evidence at a top PL, SE, or ML venue?

### Part 7: Synthesis — "if I ran this project"

Given everything above, produce a concrete, opinionated recommendation:

- What are the 3–5 most important experiments to run in the first year, in order?
- What thresholds should the project commit to publicly, in advance, that would declare the language a success or failure?
- What are the two or three specific things this project could do that would make its evidence more credible than any prior agent-language evaluation?
- What are the fatal mistakes to avoid?

## Requirements

- **Primary sources only.** Cite peer-reviewed papers, preprints on arXiv, primary benchmarks, and official documentation. Do not cite blog posts of blog posts of papers.
- **Quantitative wherever possible.** Numbers, effect sizes, confidence intervals, sample sizes. Where a claim rests on a single small study, say so.
- **Engage with the null hypothesis at every step.** Do not assume the language is worth building. Assume the opposite and let evidence overturn it.
- **Be specific.** "Design an experiment" means: name the tasks, name the metrics, name the threshold, name the analysis. "Evaluate carefully" is not an answer.
- **Long-form and comprehensive.** This is a research report, not a summary. Aim for depth on every part. Length should be whatever the evidence demands.
- **Cite everything inline.** Every non-obvious claim needs a source. If a claim is your synthesis, say so.
- **Name the frontier.** Which labs, researchers, and projects are doing the most credible work in each area right now? Name specific people, groups, papers, and venues.
- **Do not editorialize.** Report what the evidence says, then in Part 7 give your recommendation clearly separated from the evidence.

Deliver as a single long-form report with clear section headers matching Parts 1–7.
