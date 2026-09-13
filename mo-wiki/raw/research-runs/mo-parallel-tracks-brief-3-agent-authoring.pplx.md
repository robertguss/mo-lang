---
tool: Perplexity
prompt: prompts-mo-parallel-tracks / brief for prompt 3
run: 2026-09-13
run_by: Claude (via Perplexity session 2c696217)
session_url: https://www.perplexity.ai/computer/tasks/2c696217-8105-4eea-98c1-c131b407077c
sha256: 268926df54c8660fdf72a21d4d058131004911039662f7945f08a4b959e72b09
---
# Deep Research Prompt 3: The Research Frontier on Programming Languages and Toolchains for AI Agents

## Context and premise

A new general-purpose programming language and toolchain is being designed for a world where LLM-based coding agents write nearly all the code, iterate on it in a compile/test loop, and deploy it with limited human review. The design ambition is not just to be usable by agents but to be dramatically better for agents than any existing language — measurably better success rates, faster convergence, fewer defects, lower total token cost, more autonomous debugging.

The research field around this is moving quickly. Multiple threads matter: what language design features actually help LLMs generate correct code, what toolchain features close the cold-start gap for a language absent from training data, what verification and diagnostic strategies act as the best teachers, how grammar-constrained decoding and effect-typed generation change what a language can assume from its authors, and how RL on compiler feedback is changing what agents can do inside a tight loop.

The people building this language need to know:

1. What is the current research frontier on what makes languages easier or harder for LLMs to author correctly?
2. What is the frontier on toolchains, diagnostics, and feedback loops for coding agents?
3. What is the evidence on cold start, training-data gravity, and mitigations?
4. What is the frontier on verification-aware, contract-aware, and effect-aware code generation?
5. What are the emerging techniques (RL from compiler feedback, grammar-constrained decoding, test-time compute, agentic verification loops) that a new language should design around?
6. What implications does all of this have for concrete language and toolchain design choices?

## Your task

Produce a comprehensive, evidence-rich research report that maps the current research frontier on languages and toolchains for AI agents, and translates the findings into concrete implications for language and toolchain designers. Assume the reader is a highly technical language designer and engineering leader with strong background in PL, compilers, and modern LLMs. Do not summarize the obvious. Go deep on the parts that matter, name the labs and researchers doing the important work, and be specific about what the evidence supports and what it does not.

## What to cover

### Part 1: Training-data gravity and cold start

- What is the current best evidence that LLM performance on code generation correlates with the language's presence in training data? Cover Dan Luu's benchmarks, the "No Resource, No Benchmarks, No Problem?" paper (arXiv 2606.16827), the anup.io Markov language piece, the AkitaOnRails posts, and any other primary sources.
- Quantitatively: how much worse do models do on low-resource or brand-new languages? Does the gap close, and how, and by how much, with which interventions?
- What is the evidence on the effectiveness of interventions that a language designer controls? Cover in-context learning, retrieval-augmented generation, structured system prompts, grammar-constrained decoding, tool-augmented agent loops, iterative repair on compiler feedback, fine-tuning on synthetic corpora.
- What is the ceiling? Is there evidence that a well-designed toolchain can close the gap entirely, or does training-data presence dominate no matter what?
- What labs and researchers are doing the most credible work on this specific question?

### Part 2: Language design features and their measured effect on LLM code generation

- What is the evidence on the effect of specific language design choices on agent performance? Cover:
  - Static vs dynamic typing
  - Explicit vs inferred types
  - Verbosity and syntactic sugar
  - Error handling style (exceptions, Result types, panics, checked exceptions)
  - Effect systems and effect annotations
  - Contracts and refinement types
  - Pattern matching and exhaustiveness
  - Nullability and Option/Maybe types
  - Immutability by default
  - Purity and functional style
  - Concurrency primitives (async/await, actors, CSP, structured concurrency)
- For each, cite specific studies, benchmarks, or empirical arguments. Where the evidence is weak or absent, say so.
- What is the specific evidence on Rust vs Go vs Python vs TypeScript for agent code generation? What do the leaderboards actually show, and what do the meta-critiques of those leaderboards say?
- Cover CodeAct (Python as best action language) and Quasar (Python subset with guarantees) in depth as case studies in language choice affecting agent performance.

### Part 3: The compiler as teacher — diagnostics and feedback loops

- Cover the frontier on structured, machine-readable compiler diagnostics. Rust's diagnostic model, Elm's error messages, TypeScript's suggestions, Roc's approach, and any research on machine-consumable error formats.
- What is the evidence that error message quality actually affects agent success rates? Cite the RustAssistant paper, Marmaragan (LLM-SPARK annotation), and any other primary sources.
- What is the current best practice for a compiler that treats an agent as a first-class consumer of its output? Structured records, stable error codes, machine-applicable fixes, category taxonomies, "why" text as pedagogy. What has actually been built and measured?
- The Elm-style compiler-as-friend approach: what is the evidence that it works for humans, and does the evidence transfer to agents? What is the difference between "kind" errors and "informative" errors for an agent?
- Iterative repair: how effective is the pattern of "agent generates code, compiler rejects, agent reads error, agent repairs"? What are the measured convergence rates, and what makes them succeed or fail?
- Structured diagnostics as pedagogy: what is the state of the art on using compiler output to teach an LLM a language it has never seen? Are there published results on this specifically?

### Part 4: Grammar-constrained decoding, syntax-aware generation, and token efficiency

- Cover SynCode and related work on grammar-constrained decoding. What are the measured effects on syntactic correctness, semantic correctness, and generation speed? What are the tradeoffs?
- Cover Token Sugar (ASE 2025) and related work on token-efficient grammar for LLM consumption. What are the measured token savings, and do they translate to end-to-end wins?
- What is the state of the art on syntax-aware, type-aware, and effect-aware constrained decoding? What are the open problems?
- What are the implications for language design? Does a language designed knowing agents will use grammar-constrained decoding look different from one that assumes free-form generation?

### Part 5: Verification-aware code generation

- Cover the vericoding literature deeply. Dafny went from 68% to 97% verification success in a year via LLM-assisted synthesis. What are the actual experimental designs, what benchmarks were used, what worked, what did not?
- Cover Verus, Aeneas, F* + LLM, Lean + LLM, and related work on verified code generation.
- Cover the SPARK/Ada + LLM work (Marmaragan and its follow-ups).
- Cover Bosque, Quasar, and any other language designs that were explicitly built to be verifier-friendly for LLMs.
- What is the evidence on contract-driven development with agents? When does the agent generate the contract, when does the human, when does neither? What are the measured effects on defect rate and iteration count?
- What is the state of the art on tier-1 (types, lints), tier-2 (runtime contracts, tests), and tier-3 (property tests, simulation, SMT proofs) verification in an agent authoring loop? What is the right balance and what evidence supports it?

### Part 6: Agent architectures, tool use, and edit models

- Cover the frontier on how agents actually edit code. `str_replace`, line-range edits, tree-sitter-based edits, hash-identified declaration edits (Unison-style), AST-shaped tools, MCP-based tool exposure. What does the evidence say about which edit models produce more reliable outcomes?
- Cover the state of the art on how agents use compilers, test runners, and linters in a tight loop. What are the emerging patterns (SWE-agent, Aider, Cursor's approach, Devin's approach, Cognition's approach, Claude Code, Codex)? What has been measured?
- Cover CodeAct and related work on executable code as the action format for agents. What are the implications for language design of "the language is also the action language"?
- Cover the emerging research on capability-based, permission-scoped agent execution. What are the primitives, what are the open problems, and how does language-level capability design (a la E, Newspeak, Wyvern, Austral) intersect with agent-level permission scoping?

### Part 7: RL from compiler feedback and test-time compute

- Cover the frontier on reinforcement learning from compiler and test feedback. What has been published, what has been demonstrated, and what are the labs (OpenAI, Anthropic, DeepMind, Meta, academic groups) doing publicly and semi-publicly?
- What is the evidence that RL from verifier/compiler/test feedback improves an agent's ability to author correct code in a specific language? What are the transfer effects — does RL on Language A improve Language B?
- What are the implications for a language whose central bet is fast, strict feedback loops? Does a language designed around RL-from-compiler-feedback look different?
- Cover the emerging frontier on test-time compute, iterative refinement, and self-play for code generation. What is real and what is projection?

### Part 8: Effects, capabilities, and side-effect visibility

- Cover the frontier on effect systems in modern languages (Koka, Unison abilities, Roc's pure model, Verse's transactional effects, Austral's linear capabilities, Wyvern's capability-safe modules). What is the state of the art on effect polymorphism, effect handlers, and capability tracking?
- What is the evidence that effect and capability annotations help agents specifically? What is the evidence that they hurt via annotation overhead?
- Cover the "Lingering Authority" paper (arXiv 2606.22504) and related work on revocable capabilities for coding agents.
- What is the frontier on making information-flow, permissions, and side effects visible in ways that both humans and agents can reason about? What are the emerging techniques (taint tracking at the type level, effect-typed IR, capability manifests) and what is measured?

### Part 9: Deterministic execution, replay, and simulation as agent primitives

- Cover the frontier on deterministic execution and simulation for testing (FoundationDB's deterministic sim, TigerBeetle, Antithesis, Jepsen, DST research in academia).
- What is the evidence that deterministic simulation with fault injection produces materially better software, and does the evidence transfer to agent-authored software?
- What is the state of the art on replay-based debugging for agents? If a crash produces a seed + message log + state snapshot, does an agent actually use that to fix bugs more effectively? Any published measurements?
- What are the implications for language design of "the runtime is a deterministic simulator by default"? What has to be true at the language level for this to work?

### Part 10: Emerging techniques and forward bets

- What are the emerging research directions that a language designer starting now should design around, not against? Cover:
  - Long-context models and their effect on how much of a program an agent can reason about at once.
  - Reasoning models and their effect on tolerance for verbose annotations.
  - Multi-agent systems and their effect on how code review, refactoring, and verification are distributed.
  - Structured output and constrained decoding becoming standard.
  - Verifier-in-the-loop training becoming standard.
  - Code-generation-specialized models (Codex, Claude Code, DeepSeek-Coder, StarCoder, Qwen-Coder) diverging from general models.
- Which of these are load-bearing bets that a language should assume as background, and which are speculative?
- What forward bets, if made now, would look prescient in 3 years and foolish if they do not pan out? Name specific bets, not vague trends.

### Part 11: The counter-position

- State the strongest version of the case that a new language is the wrong answer, and the right answer is a subset of an existing language with better tooling. Cover Quasar, CodeAct, Token Sugar, SynCode, the "training-data gravity dominates" argument. What is the strongest evidence for this position?
- What would a language designer have to show to overcome this position with empirical evidence?

### Part 12: Synthesis — "if I ran this project"

Given everything above, produce a concrete, opinionated recommendation:

- What are the 5–10 most important research findings that a language and toolchain design should be built around?
- What are the 3–5 highest-leverage toolchain features that most reliably improve agent performance, per the evidence?
- What are the 2–3 language design bets that most reliably improve agent performance, per the evidence?
- What are the specific open research questions where a new language project could produce publishable results that advance the field?
- What are the fatal misreadings of the current frontier to avoid?

## Requirements

- **Primary sources.** Cite arXiv papers with numbers, published venues (POPL, PLDI, OOPSLA, ICSE, FSE, ASE, NeurIPS, ICLR, ICML, EMNLP), primary benchmarks, and named researchers' technical writing. Where a claim rests on a blog post, name the author and their basis.
- **Quantitative wherever possible.** Effect sizes, benchmark scores, sample sizes, error bars. Where a claim rests on a single small study, say so.
- **Name the frontier.** Which specific labs, researchers, and projects are doing the important work in each area right now? Name people.
- **Be specific.** "Effect systems help" is not an answer. Which effect system, on which benchmark, versus which baseline, with what effect size.
- **Distinguish real from projected.** Where a technique is demonstrated, say so. Where it is speculated, say so. Where it is marketed but not evidenced, say so.
- **Long-form and comprehensive.** This is a research report, not a summary. Depth on every part.
- **Cite everything inline.** Every non-obvious claim needs a source.
- **Do not editorialize until Part 12.** Report evidence in Parts 1–11. Recommend in Part 12.

Deliver as a single long-form report with clear section headers matching Parts 1–12.
