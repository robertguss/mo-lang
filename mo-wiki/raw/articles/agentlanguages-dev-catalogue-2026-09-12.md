---
source_url: https://agentlanguages.dev
ingested: 2026-09-12
sha256: ce6f7b4da89b2236acb7f5433956cb04f714e4051a3bb6898f3d82e3b12205ce
---
# agentlanguages.dev — catalogue as of 12 Sep 2026

Community-edited catalogue of programming languages designed for AI agents as the primary authors of code. 42 languages tracked; last updated 12 Sep 2026; stars refreshed 7 Sep 2026. Inclusion criterion is intent: designers explicitly target LLMs/agents as authors (token-friendly syntax, mechanically checkable contracts, agent-coordination primitives, or first-class effect declarations for model calls). Runtime LLM integration alone does not qualify. Machine-readable versions at /llms.txt and /llms-full.txt.

Three camps, in the site's words:
- **Syntactic** — "models choke on tokens that mean different things in different positions"; "build a syntax where every token has one job."
- **Verification** — "the model doesn't need to be right. It needs to be checkable." Contracts, refinement types, formal-methods machinery.
- **Orchestration** — "it isn't a language problem. It's an agent-coordination problem." Sequencing, sandboxing, human approval.

| Name | Description | Camp | Status |
|---|---|---|---|
| Axis | Backend API language for small LLMs with LL(1) grammar and constrained decoding | Syntactic + Verification | Working compiler (May 2026) |
| B-IR | Three attempts at LLM-optimised languages with unicode opcodes and control characters | Syntactic | Thought experiment (Jan 2026) |
| Codong | AI-written language with canonical operations, JSON errors, and Go compilation | Syntactic | Working compiler (Mar 2026) |
| Faber Romanus | Typed compute language with multi-model council keywords and multiple targets | Syntactic | Working compiler (Jul 2026) |
| ilo | Token-minimal language driven by scripted agent sessions | Syntactic + Verification | Working compiler (Feb 2026) |
| Laze | Minimal indentation syntax without punctuation, Python to C compiler | Syntactic | Early (Apr 2026) |
| LLMLang | Prefix-arity AST with De Bruijn indices and linear ownership enforcement | Syntactic + Verification | Working compiler (May 2026) |
| Lume | AI-first backend with immutability defaults and token-budgeted retrieval | Syntactic | Early (May 2026) |
| Magpie | SSA as surface syntax with %-prefixed values and LLVM compilation | Syntactic | Early (Apr 2026) |
| Mog | Statically typed embedded language with flat operators and capability grants | Syntactic | Working compiler (Mar 2026) |
| NERD | Replaces operators with English keywords for token efficiency | Syntactic | Working compiler (Jan 2026) |
| Sever | Single-character opcodes for extreme density (Claude-generated art piece) | Syntactic | Thought experiment (Feb 2026) |
| Tacit | AST-first with BLAKE3 addressing and DeBruijn indices | Syntactic + Verification | Working compiler (Apr 2026) |
| X07 | Programs as canonical JSON ASTs with RFC 6902 patches | Syntactic | Working compiler (Apr 2026) |
| AILANG | Row-polymorphic Hindley-Milner with capability effects, no loops | Verification | Working compiler (Sep 2025) |
| Aver | Intent and effect declarations with Lean 4 and Dafny proof exports | Verification | Working compiler (Feb 2026) |
| BHC/hx | Haskell toolchain wrapper (hx) and clean-slate compiler (BHC) | Verification | Early (Apr 2026) |
| Codex | Self-hosting bare-metal x86-64 with dependent and linear types | Verification + Orchestration | Working compiler (Mar 2026) |
| Hale | Concurrent systems with compile-time effect certificates | Verification | Working compiler (May 2026) |
| Intent | Mandatory contracts with Z3 SMT verification and multi-target output | Verification | Working compiler (Feb 2026) |
| Modula-9 | Wirth-lineage with range checking and differential execution validation | Verification + Syntactic | Working compiler (Aug 2026) |
| MoonBit | ICSE 2024 semantics-aware token sampling for general-purpose AI code | Verification + Syntactic | Working compiler (Jan 2023) |
| NanoLang | Mandatory shadow tests with 193 zero-axiom Coq theorems | Verification | Working compiler (Sep 2025) |
| Pact | Intent blocks, pipeline syntax, HTTP/SQLite/LSP/MCP in single binary | Verification | Working compiler (Apr 2026) |
| Prove | Intent-first with source license prohibiting AI training use | Verification | Working compiler (Feb 2026) |
| reqlan | Named requirement ideas linked to symbols and tests | Verification + Syntactic | Working compiler (Jun 2026) |
| SEMAPRAX | Graph-native systems language with persistent identities and capabilities | Verification + Syntactic | Working compiler (Aug 2026) |
| Thermite | Contract-first with mandatory req/ens/fx and Forge assurance reporting | Verification + Syntactic | Working compiler (Jun 2026) |
| Vera | Mandatory contracts with Z3 SMT and slot references replacing variables | Verification | Working compiler (Feb 2026) |
| Vow | Machine-checked vows with ESBMC bounded model checking | Verification | Working compiler (Feb 2026) |
| Zero | Vercel Labs' sub-10 KiB binaries with structured JSON diagnostics | Verification + Syntactic | Early (May 2026) |
| Boruna | Deterministic, capability-safe workflow with hash-chained evidence bundles | Orchestration + Verification | Working compiler (Apr 2026) |
| Fabro | Workflow harness with Graphviz digraphs routed to language models | Orchestration | Working compiler (Mar 2026) |
| Lumen | Markdown-native source with algebraic effects and deterministic enforcement | Orchestration | Working compiler (Feb 2026) |
| Marsha | English-based declarations compiled to tested Python by LLM | Orchestration | Early (Jul 2023) |
| Pel | Lisp-flavoured agent orchestration with grammar-level capability control | Orchestration | Research paper (Apr 2025) |
| Plasm | Catalog-hosted path expressions over typed API graphs | Orchestration + Syntactic | Working compiler (Apr 2026) |
| Quasar | Penn's LLM-agent language with parallelisation and conformal prediction | Orchestration + Verification | Research paper (Jun 2025) |
| Plumbing | Typed language for agent wiring using symmetric monoidal categories | Adjacent/Infrastructure | Early (Mar 2026) |
| Koru | Zig-superset with event continuations and purity tracking | Unclassified | Early (Dec 2025) |
| Spec | Language-agnostic IR for six-agent collaboration | Unclassified | Thought experiment (Apr 2026) |
| Valea | AI-native systems language with JSON diagnostics and C backend | Unclassified | Early (Mar 2026) |
