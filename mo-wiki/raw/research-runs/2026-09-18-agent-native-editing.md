---
source_url: https://ampcode.com/user-content/attachments/5ff68390c0771c187423b1641db5a8bee951a5c9b560ab920a7cf3a5ce7f20d5-Program-Editing-Paradigms-for-AI-Agents.md
ingested: 2026-09-18
sha256: bb9523f0c25ca776e7f0dc24f9c50a1a510be1e271346027811e5939149c3274
---
# Program Editing Paradigms for AI Agents

## Overview

Four families of code-editing mechanism are in serious use by AI coding agents today: source-text patches (unified diffs and search/replace blocks), declaration-ID or symbolic editing (address by name or hash instead of literal text), compiler-assisted refactoring (LSP `WorkspaceEdit`, IntelliJ PSI, Roslyn workspaces, rust-analyzer), and structured or projectional program editing (JetBrains MPS, Hazel, Sandblocks). Each paradigm answers a different question: how do you name the place in the program you want to change, and what does the system guarantee about the change before it lands.

The evidence from Aider, SWE-agent, Cursor, Claude Code, Morph, Kiro, and recent SWE-bench trajectory studies converges on a nuanced picture. Text-based edits dominate real deployments and reach very high per-call success on frontier models, but they carry a long tail of formatting, staleness, and cross-file failures. Semantic tools eliminate the whole class of "string not found" failures and enforce cross-file consistency for a narrow set of operations, but they constrain the agent on transient invalid states and on edits that outrun a given language's semantic model. Projectional editors demonstrate the theoretical endpoint — no invalid states — at a real cost in adoption friction and diff/VCS ergonomics.

## Source-Text Patches

Source-text patches address a location by reproducing the surrounding characters. The three deployed variants are unified diff (with `@@` hunks), search/replace blocks (Aider's SEARCH/REPLACE, Cursor's diff hunks), and exact `str_replace` (Anthropic's `str_replace_based_edit_tool`, SWE-agent's `edit`).

### Measured failure rates

The trajectory study *Coherence Collapse* reports per-call `str_replace` reliability across frontier and open models on SWE-Bench Verified and PolyBench Verified: GPT-5 at 98.8%/99.4%, GPT-5-mini at 98.9%/99.8%, Qwen3-Coder-30B at 99.5%/99.9%, Qwen3-Coder-480B at 98.4%/99.2%, Qwen3-235B at 97.2%/98.2%, and Qwen3-32B at 92.6%/83.5% ([Coherence Collapse](https://arxiv.org/html/2603.24631v2)). Reliability drops on longer, more diverse files: Qwen3-32B's `create` success falls from 78.9% on SWE-Bench to 58.7% on PolyBench, and its `undo_edit` from 71.7% to 43.8% ([Coherence Collapse](https://arxiv.org/html/2603.24631v2)).

Aider's own comparative benchmark contradicts the intuition that diffs beat whole-file rewrites for weaker models. In the original Exercism benchmark, GPT-3.5 achieved 46% first-attempt with whole-file replacement and only 30% with SEARCH/REPLACE-style diff, and GPT-3.5 frequently mangled the function-calling variant, returning invalid JSON with the entire Python file inside the arguments field ([Aider benchmarks](https://aider.chat/docs/benchmarks.html)). For GPT-4-Turbo, however, unified diff pushed the laziness benchmark from a 20% SEARCH/REPLACE baseline to 61%, and disabling flexible patching produced a 9x increase in editing errors, showing how much of the observed reliability depends on parser tolerance rather than the format itself ([Aider unified diffs](https://aider.chat/docs/unified-diffs.html)).

Morph's independent measurement across Claude Code, Cursor, and Aider deployments claims a 65% first-attempt success rate for text-based approaches with 2.3 average attempts per successful edit, rising to a 70%+ failure rate when `formatOnSave` reformats between read and write, and a 50%+ failure rate on sessions longer than 30 edits ([Morph error report](https://www.morphllm.com/common-errors/error-editing-file)). These numbers describe a different denominator than the trajectory study — user-visible edit sessions rather than per-tool-call success — but they identify the same failure modes.

### Failure modes

The Anthropic issue tracker documents the concrete failure surface for `str_replace_based_edit_tool`: CRLF/LF line-ending mismatches, tab-versus-space indentation, backslash escape sequences, and duplicate matches that make the edit ambiguous. One user reported "15 consecutive failed edit attempts due to backslash escape sequences," and another described tab-indented Go files and Makefiles as "essentially uneditable" ([Claude Code #25775](https://github.com/anthropics/claude-code/issues/25775)). A separate issue described "About 80% of all actions it tried to take failed" on a real project, with the fallback being to have Claude write bash scripts to make the changes instead ([Claude Code #167](https://github.com/anthropics/claude-code/issues/167)).

Cursor's engineering blog is explicit about why models struggle with diff formats: diffs force the model to think in fewer output tokens, they are out-of-distribution relative to whole files in pretraining, and models are "notoriously bad at counting line numbers" ([Cursor Instant Apply](https://cursor.com/blog/instant-apply)). Cursor's stated summary: "Most models fail to output accurate diffs, with the exception of Claude Opus" ([Cursor Instant Apply](https://cursor.com/blog/instant-apply)).

The CODESTRUCT paper quantifies the wasted work text editing imposes on the agent itself. On a single Django issue, a text-based agent read ~300 lines and regenerated ~44 lines verbatim for removal in 54 total steps, versus a structured agent's 2 steps to locate and ~2-line removal in 24 total steps. Without the structured `str_replace` fallback, Qwen3-32B's `str_replace` usage increased 7.8× — from 314 to 2,456 operations on regressed instances — as the agent thrashed against exact-match failures ([CODESTRUCT](https://openreview.net/pdf/94418c024818218653b1ee53372a2aa1c59ef0c3.pdf)).

### Cross-file changes

Source-text patches provide no cross-file guarantee. A patch is applied file-by-file; consistency across a rename or interface change must be produced by the agent, verified by tests, or discovered by re-reading. RefactorBench reports that reference refactorings touch on average 4.3 files, which stresses this weakness directly ([Can LLMs Generate Human-Level Code Refactorings?](https://arxiv.org/html/2603.04177v2)). The observed compensating behavior is destructive: agents fall back to repository-wide `sed -i` or Perl-based global substitutions across 231–232 files at a time to force consistency, with mixed success and frequent broken intermediate states ([Can LLMs Generate Human-Level Code Refactorings?](https://arxiv.org/html/2603.04177v2)).

### Temporarily invalid code

Source-text patches accept any string. Between two related edits — e.g., changing a function signature and its callers — the code is temporarily invalid, and this is fine, expected, and cheap. This is the paradigm's structural advantage that projectional editors give up. SWE-agent's line-based `edit` runs a Python syntax check and rejects the edit on failure, which improves the resolved rate from 15.0% to 18.0% on SWE-bench Lite (versus 10.3% for a shell-only baseline) — a guardrail without denying invalid intermediate states across the multi-edit sequence ([SWE-agent](https://proceedings.neurips.cc/paper_files/paper/2024/file/5a7c947568c1b1328ccc5230172e1e7c-Paper-Conference.pdf)).

### Stale edits

Stale reads are a first-class problem for text patches. A file read at turn 1 of a 50-turn session may be referenced at turn 48 after 47 turns of change, and most assistants have no mechanism to detect that previously-read files have changed ([Stale Context in AI Coding](https://vexp.dev/blog/stale-context-ai-coding-problem)). Cursor's Fast Apply documentation lists "concurrent edits create race conditions" and "large files overwhelm context" as first-order failure sources; Morph specifically calls out "context drift (file changed between edit generation and application)" as a case its apply model is designed to survive ([Morph error report](https://www.morphllm.com/common-errors/error-editing-file), [Morph Fast Apply](https://www.morphllm.com/fast-apply-model)).

### Recovery

Recovery on failed patches is retry-and-reread. Anthropic issue #25775 documents retry loops of 15+ attempts and proposes hash-based line addressing with fuzzy fallback tiers — exact match, whitespace-insensitive, indentation-preserving, and threshold-based Levenshtein — arguing Aider's tolerant matcher already improves success rates by 10–30% ([Claude Code #25775](https://github.com/anthropics/claude-code/issues/25775)). SWE-agent's `undo_edit` provides a first-class rollback; its measured reliability tracks the same model quality gradient as `str_replace` itself ([Coherence Collapse](https://arxiv.org/html/2603.24631v2)).

## Declaration-ID and Symbolic Editing

Declaration-ID editing addresses a location by its symbolic identity — function name, class name, hash of the current line, or AST-node handle — instead of its surrounding characters. Three variants are in production: the fast-apply model architecture (Cursor, Morph), AST-typed edit operations (Kiro's `insert_node`, `replace_node`, `delete_node`, `replace_in_node`), and hash-addressed lines (the proposed `hashline` scheme in Anthropic issue #25775).

### Fast-apply models

Cursor and Morph split editing into a planning model that emits an edit sketch and an apply model that merges the sketch into the current file. Cursor reports 1000 tokens/second on this specialized task; Morph's Fast Apply reports 10,500 tok/s at claimed 98% accuracy, marketed against text search-and-replace at a stated 84–96% accuracy that "requires 2-3.5x more retry turns on failures" ([Cursor Instant Apply](https://cursor.com/blog/instant-apply), [Morph Fast Apply](https://www.morphllm.com/fast-apply-model)). Cursor's justification is direct: whole-file rewrites give the model more forward passes to reason, keep the model in-distribution, and avoid line-number arithmetic ([Cursor Instant Apply](https://cursor.com/blog/instant-apply)).

The apply model is not free of the paradigm's underlying issues. Cursor documents that the apply model may hallucinate, may produce output that does not match the original file structure, and creates race conditions under concurrent edits; Morph's own documentation warns "you must always mark sections you want to keep," because omitting a section instructs removal ([Morph error report](https://www.morphllm.com/common-errors/error-editing-file), [Morph Fast Apply](https://www.morphllm.com/fast-apply-model)).

### AST-typed operations

Kiro's AST-based engine addresses code structurally — functions, classes, methods, imports, and fields — with typed operations that mirror LSP `WorkspaceEdit` at a lower level. On the reported feature-request demonstration, the AST engine had 0 tool errors versus 2 for text-based tools; token usage on SWE-PolyBench dropped 20% ([Kiro AST](https://kiro.dev/blog/surgical-precision-with-ast/)). CODESTRUCT reports Pass@1 improvements of 1.2–5.0% and token-consumption reductions of 12–38% across six LLMs on SWE-Bench Verified ([CODESTRUCT](https://www.emergentmind.com/papers/2604.05407)).

### Hash-based line addressing

The `hashline` proposal makes each source line addressable by a short whitespace-insensitive content hash — for example, `1:a3| function hello() {` — and lets the model say `replace line 2:f1`. This eliminates the entire class of whitespace and reformatting failures that dominate `str_replace` errors, at a cost of pre-processing every file read to attach hashes ([Claude Code #25775](https://github.com/anthropics/claude-code/issues/25775)).

### Where the paradigm helps

Declaration-ID edits are resilient to formatting drift, indentation style, and formatter runs between read and apply. Kiro states this explicitly: "Whether you use 2 spaces or 4, tabs or spaces, the AST edit succeeds." Morph makes the same claim for its semantic apply model against "repetitive code structures, nested blocks, overlapping edit regions, and context drift" ([Kiro AST](https://kiro.dev/blog/surgical-precision-with-ast/), [Morph Fast Apply](https://www.morphllm.com/fast-apply-model)).

### Where it constrains the agent

Declaration-ID schemes require the target symbol or node to already exist under a stable identity. This is fine for edits to a known function but awkward for creating a new file, splitting a function, or introducing a new abstraction whose name has not yet been chosen. Hash-based addressing partially escapes this by falling back to line hashes rather than semantic identities, but at that point it has become a robust variant of source-text patching rather than a semantic tool.

## Compiler-Assisted Refactoring

Compiler-assisted refactoring — LSP `WorkspaceEdit`, IntelliJ PSI, Roslyn workspaces, rust-analyzer — provides safe, cross-file transformations whose correctness is verified by a real language front end. It is the strongest safety guarantee in the four paradigms and the narrowest in scope.

### LSP `WorkspaceEdit` semantics

The LSP 3.17 rename request "asks the server to compute a workspace change so that the client can perform a workspace-wide rename of a symbol." Its result is a `WorkspaceEdit` whose `changes` map every affected URI to a list of `TextEdit` values, or whose `documentChanges` include resource operations (create, rename, delete of files). The specification is explicit that rename may fail when the code is invalid — "e.g. does not compile" — and that `textDocument/prepareRename` is the correct way for the client to check whether the position is renameable before proposing a new name ([LSP 3.17](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)).

### IntelliJ PSI

IntelliJ's rename works by calling `PsiNamedElement.setName()` on the target and `PsiReference.handleElementRename()` on every reference, using the Find Usages index to identify potentially affected files. Safe Delete builds on the same infrastructure. Names are validated by a language-specific `NamesValidator`, and specific elements can veto renaming via the `vetoRenameCondition` extension point ([IntelliJ Rename Refactoring](https://plugins.jetbrains.com/docs/intellij/rename-refactoring.html)).

### Roslyn workspaces

The Roslyn Workspace API "is the starting point for doing code analysis and refactoring over entire solutions," organizing projects into an immutable solution model with syntax trees, semantic models, and compilations. Changes are applied by constructing new solution instances and applying them back to the workspace — the paradigm assumes an entire well-typed solution, not a temporarily broken one ([Roslyn Workspaces](https://learn.microsoft.com/en-us/dotnet/csharp/roslyn-sdk/work-with-workspace)).

### Rust-analyzer

rust-analyzer's operational writeup is candid about the limits. Macros are "disproportionally hard to support in an IDE. If adding macros to a batch compiler takes X amount of work, making them play nicely with all IDE features takes X²." The lesson stated by the project is that meta-programming should be "append only" and should not change the meaning of existing code — because Find-Usages, rename, and any refactor built on top of it becomes unsound the moment a macro can produce or hide references ([IDEs and Macros](https://rust-analyzer.github.io//blog/2021/11/21/ides-and-macros.html)). Community discussion notes that handling every case is impossible because the macro system is Turing-complete, but that partial handling is worth building anyway ([Macros vs Rename](https://www.reddit.com/r/rust/comments/frskuh/blog_post_macros_vs_rename/)).

### Cross-file correctness

This is where compiler-assisted tools genuinely shine. A well-typed rename across every reference is a single atomic operation whose correctness the compiler front end certifies. IntelliJ's rename dialog shows a preview tab so the user (or agent) can inspect exactly which usages will change ([IntelliJ Rename docs](https://www.jetbrains.com/help/idea/rename-refactorings.html)).

### Where the tools constrain the agent

Three constraints matter:

1. Rename fails when the code does not compile — LSP explicitly returns a `ResponseError` in that case ([LSP 3.17](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)). An agent halfway through a multi-file change cannot ask the compiler to finish the change for it; it must first restore the code to a compileable state.
2. Dynamic languages get unsafe or unavailable refactorings. IntelliJ documentation and user reports repeatedly note that in dynamic languages, "sometimes refactorings go through, sometimes it changes things across the project and what not," and that users must repeatedly toggle "search in comments and strings," "search for text occurrences," "rename tests," and "rename variables" to avoid corrupting the code ([IntelliJ IDEA 13 refactor discussion](https://stackoverflow.com/questions/20871171/intellij-idea-13-how-do-i-disable-refactor-comments-and-strings)).
3. Not every edit is a named refactoring. Compiler-assisted refactoring covers rename, extract, inline, safe-delete, move, and a handful of language-specific transforms. It does not cover "introduce a new module and re-route callers through it" as a single atomic operation. Ad-hoc structural edits fall back to text or AST tools.

## Structured Program Editing

Structured or projectional editors — JetBrains MPS, Hazel, Sandblocks — represent the program as an abstract syntax tree at rest, projecting text (or non-textual notations) for the user to edit. The editor's edit actions are typed: they never produce an unparseable file, and in Hazel's case they never produce an ill-typed or undefined program at all.

### JetBrains MPS

MPS is the mature production example. Its projectional editor "can feel odd because it is different from a textual editor," and JetBrains reports that UX research shows most users adjust within a few days ([MPS FAQ](https://www.jetbrains.com/help/mps/mps-faq.html)). Because "the concrete syntax is not pure text, a generic persistence format must be used" — MPS stores code in XML and provides diff/merge tools that operate on that representation ([MPS FAQ](https://www.jetbrains.com/help/mps/mps-faq.html)). MPS's biggest structural claim is that arbitrary language combinations are guaranteed to be syntactically valid, because there is no parser to be ambiguous ([MPS FAQ](https://www.jetbrains.com/help/mps/mps-faq.html)).

### Hazel

Hazel is a research language whose editor is defined by a bidirectionally typed structure-editor calculus (Hazelnut). Its central invariant: "There are no meaningless editor states." Every incomplete program is statically and dynamically well-defined; typed holes stand for missing subterms and mark erroneous ones, and the language can typecheck and even run programs with holes ([Hazel](https://hazel.org/), [Hazelnut](https://users.cs.northwestern.edu/~robby/courses/395-495-2017-winter/Hazlenut.pdf)). Recent work extends this to live pattern matching, polymorphism, and total type-error localization on holes ([Live Pattern Matching with Typed Holes](https://hazel.org/papers/peanut-oopsla2023.pdf)).

### Adoption friction

The reddit thread on MPS captures the friction honestly. One commenter: "Free-form text editing basically won out last time around." Another: "Being able to transition through grossly invalid intermediate states when evolving between two valid states may seem inelegant but it sure is fast." A third: "I hate the idea that the IDE won't let me do syntactically incorrect stuff. I do that a lot during refactoring" ([Reddit MPS thread](https://www.reddit.com/r/programming/comments/37xlm1/jetbrains_mps_projectional_editor/)). Sandblocks explicitly targets this by deriving structured editors from grammars so that adoption cost is lower, and reports usability across languages, but does not overturn the finding that grossly invalid intermediate states are a productive editing technique ([Sandblocks paper](https://dl.acm.org/doi/fullHtml/10.1145/3544548.3580785)).

### Diff and VCS handling

Projectional editors do not store text. MPS and mbeddr store XML that integrates with SVN and Git, and provide custom diff/merge tools; the persistence format is not what humans read. This is a real deployment cost when the surrounding ecosystem — code review, PR tooling, blame, grep, `sed`, agent read tools — assumes text ([MPS FAQ](https://www.jetbrains.com/help/mps/mps-faq.html), [Reddit MPS thread](https://www.reddit.com/r/programming/comments/37xlm1/jetbrains_mps_projectional_editor/)).

### Where the paradigm helps agents

Hazel-style holes give an agent an explicit representation of "not yet written" that the type system understands and the runtime can execute around. That directly addresses the "temporarily invalid code" failure mode: instead of the code being invalid, the code is incomplete in a well-defined way, and the agent can query types, run tests against filled subterms, and refine holes one at a time. Sandblocks and MPS show that the invariant "the file always parses" is achievable in production with acceptable UX cost.

### Where it constrains the agent

The same invariant that eliminates unparseable states eliminates the fast, sloppy edits that AI agents rely on today. Every LLM-produced patch, diff, or full file must be re-projected through the editor's typed edit actions to land, which either requires the LLM to speak those actions natively (nothing in current training data resembles this) or requires a translation layer that reintroduces the parsing problem projectional editing was supposed to remove. Rust-analyzer's warning about non-deterministic procedural macros — "rust-analyzer actually *can* get a different syntax tree" — has a projectional analog: LLM outputs are non-deterministic, and forcing them into typed edit actions is either a lossy round-trip or a hard rejection ([IDEs and Macros](https://rust-analyzer.github.io//blog/2021/11/21/ides-and-macros.html)).

## Comparative Summary

| Dimension | Source-text patches | Declaration-ID / apply model | Compiler-assisted refactor | Structured / projectional |
|---|---|---|---|---|
| Addressing | Literal characters or line numbers | Symbol name, node handle, or content hash | Semantic reference from front end | Direct AST node |
| Per-call reliability (frontier models) | 97–99% for GPT-5/Claude Opus on SWE-Bench; drops to 83–93% on weaker models and larger repos ([Coherence Collapse](https://arxiv.org/html/2603.24631v2)) | Claimed 98% for Morph Fast Apply, comparable for Cursor Instant Apply ([Cursor Instant Apply](https://cursor.com/blog/instant-apply), [Morph Fast Apply](https://www.morphllm.com/fast-apply-model)) | Deterministic when the code compiles and the transform is defined ([LSP 3.17](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)) | Deterministic by construction ([Hazel](https://hazel.org/)) |
| Cross-file changes | Agent must coordinate; destructive `sed` fallback is common ([Can LLMs Generate Human-Level Code Refactorings?](https://arxiv.org/html/2603.04177v2)) | Per-file; some AST engines expose multi-file operations ([Kiro AST](https://kiro.dev/blog/surgical-precision-with-ast/)) | First-class via `WorkspaceEdit` with atomic multi-file diff ([LSP 3.17](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)) | First-class at model level, but ecosystem lags |
| Temporarily invalid code | Accepted; guardrails (linting on save, syntax check) optional ([SWE-agent](https://proceedings.neurips.cc/paper_files/paper/2024/file/5a7c947568c1b1328ccc5230172e1e7c-Paper-Conference.pdf)) | Accepted at file boundaries | Rejected — rename fails when code does not compile ([LSP 3.17](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)) | Impossible by design; holes carry the incompleteness explicitly ([Hazel](https://hazel.org/)) |
| Stale edits | High risk; drives concurrent-edit and formatOnSave failures ([Morph error report](https://www.morphllm.com/common-errors/error-editing-file), [Stale Context](https://vexp.dev/blog/stale-context-ai-coding-problem)) | Reduced by re-reading current file at apply time ([Morph Fast Apply](https://www.morphllm.com/fast-apply-model)) | Reduced — file version tracked by workspace ([Roslyn Workspaces](https://learn.microsoft.com/en-us/dotnet/csharp/roslyn-sdk/work-with-workspace)) | Not applicable — AST is the source of truth |
| Recovery from failed edits | Retry-and-reread, or `undo_edit` with model-dependent reliability ([Coherence Collapse](https://arxiv.org/html/2603.24631v2)) | Apply model retries the merge on the current file ([Cursor Instant Apply](https://cursor.com/blog/instant-apply)) | Preview before commit; atomic apply ([IntelliJ Rename docs](https://www.jetbrains.com/help/idea/rename-refactorings.html)) | Undo through the edit-action calculus ([Hazelnut](https://users.cs.northwestern.edu/~robby/courses/395-495-2017-winter/Hazlenut.pdf)) |
| Failure surface | Whitespace, line endings, ambiguous matches, formatter drift ([Claude Code #25775](https://github.com/anthropics/claude-code/issues/25775), [Claude Code #167](https://github.com/anthropics/claude-code/issues/167)) | Apply-model hallucination on large files or overlapping edits ([Morph error report](https://www.morphllm.com/common-errors/error-editing-file)) | Macros, dynamic dispatch, reflection, incomplete code ([IDEs and Macros](https://rust-analyzer.github.io//blog/2021/11/21/ides-and-macros.html), [IntelliJ IDEA 13 discussion](https://stackoverflow.com/questions/20871171/intellij-idea-13-how-do-i-disable-refactor-comments-and-strings)) | Adoption friction; text-tool ecosystem gap ([MPS FAQ](https://www.jetbrains.com/help/mps/mps-faq.html), [Reddit MPS thread](https://www.reddit.com/r/programming/comments/37xlm1/jetbrains_mps_projectional_editor/)) |

## Refactoring Benchmarks

Two benchmarks now target the multi-file, behavior-preserving refactorings where compiler-assisted tools should shine. RefactorBench (ICLR 2025) reports GPT-4o refactorings on Python tasks touching on average 4.3 files ([Can LLMs Generate Human-Level Code Refactorings?](https://arxiv.org/html/2603.04177v2), [RefactorBench](https://github.com/microsoft/RefactorBench)). Scale's SWE Atlas — Refactoring reports 70 tasks across 10 production repositories and 6 languages (Go, TypeScript, Python, C, C++, JavaScript), with 2x the LOC changes and 1.7x the files-per-task of SWE-Bench Pro; the top score is Claude Opus 4.7 with Claude Code at 48.57, and "top models score well under 50%" ([SWE Atlas Refactoring](https://labs.scale.com/leaderboard/sweatlas-refactoring)).

The trajectory-level *Coherence Collapse* study is more diagnostic: 60–69% of capable-model failures on SWE-Agent and OpenHands "reach and edit the correct functions yet still produce incorrect patches." Within that residual, Coherence Collapse — "the agent reaches correct code and then overwrites or thrashes it" — accounts for 39.7% of edit-quality failures (22.6% of all SWE-Agent failures) on SWE-Bench and 32.3% on PolyBench. This sub-type is length-independent and dissociates from context-window degradation ([Coherence Collapse](https://arxiv.org/html/2603.24631v2)). A follow-up formalizes the underlying phenomenon as *coherence debt*: "an edit is correct only when the facts it depends on are available as the agent writes," and success tracks coverage of coupled facts, not context volume ([Coherence Debt](https://arxiv.org/html/2608.16630v1)).

The implication is important. Localization is largely solved. The dominant failure mode is that after the agent has found the right code, it destroys its own progress with a subsequent bad edit. This failure is not something a better text-patch parser fixes, and it is not what compiler-assisted rename addresses. It is what a queryable runtime, structured invariants, or an event ring of the agent's own edits would surface.

## Where Semantic Tools Help vs. Constrain

Semantic tools help decisively in three regimes:

1. **Cross-file symbol changes with a stable definition.** A rename that must propagate across 20 call sites is a solved problem for compiler-assisted refactoring and an unresolved risk for text patches. RefactorBench's 4.3-file average is squarely in this zone ([Can LLMs Generate Human-Level Code Refactorings?](https://arxiv.org/html/2603.04177v2)).
2. **Formatting-hostile environments.** `formatOnSave`, tab-versus-space heterogeneity, and pre-commit hooks that reformat files break `str_replace` reliably ([Morph error report](https://www.morphllm.com/common-errors/error-editing-file)). Declaration-ID and AST-typed edits sidestep this entirely.
3. **Stable-shape edits inside a known symbol.** Inserting a parameter, wrapping a call, adding an import — all cases where a typed operation (`insert_node`, `replace_node`) is shorter, cheaper in tokens, and less error-prone than reproducing the surrounding lines ([CODESTRUCT](https://openreview.net/pdf/94418c024818218653b1ee53372a2aa1c59ef0c3.pdf), [Kiro AST](https://kiro.dev/blog/surgical-precision-with-ast/)).

Semantic tools constrain the agent unnecessarily in four regimes:

1. **Transiently invalid states across a multi-edit sequence.** LSP rename refuses to operate on non-compiling code. This punishes an agent that has correctly staged an intermediate broken state on the way to a valid target. The Reddit MPS quote — "Being able to transition through grossly invalid intermediate states when evolving between two valid states may seem inelegant but it sure is fast" — is the right diagnosis ([Reddit MPS thread](https://www.reddit.com/r/programming/comments/37xlm1/jetbrains_mps_projectional_editor/)).
2. **Languages with weak semantic front ends.** Dynamic languages, macro-heavy Rust, template-heavy C++, and reflection-heavy Java all narrow the domain over which "safe" refactoring is actually safe. IntelliJ users describe rename in dynamic languages as unreliable enough to require multiple checkboxes and manual audit ([IntelliJ IDEA 13 discussion](https://stackoverflow.com/questions/20871171/intellij-idea-13-how-do-i-disable-refactor-comments-and-strings)); rust-analyzer's own writeup admits macros make Find-Usages "impossible to handle in general" and requires that meta-programming be "append only" for the story to hold ([IDEs and Macros](https://rust-analyzer.github.io//blog/2021/11/21/ides-and-macros.html)).
3. **Edits that outrun the toolkit's transform library.** A named refactoring is not always available. When "route callers through a new abstraction" is not a menu item, semantic tools fall back to text tools with no continuity of guarantee.
4. **Ecosystem edges around projectional storage.** Diff, code review, `grep`, blame, and the entire text-tool ecosystem assume text. MPS integrates but does not eliminate the mismatch ([MPS FAQ](https://www.jetbrains.com/help/mps/mps-faq.html)).

## Synthesis for a Mo-Style Runtime

The evidence does not support a single winner. It supports a layered mechanism where the coarsest, most permissive layer is the default and semantic layers are invoked deliberately.

- **Default surface: source-text patches with tolerant matching.** Frontier-model reliability at 97–99% per call ([Coherence Collapse](https://arxiv.org/html/2603.24631v2)) is not the problem to solve first. Investment goes into hash-addressed line references or Aider-style flexible matching to eliminate whitespace and formatting failure modes ([Claude Code #25775](https://github.com/anthropics/claude-code/issues/25775), [Aider unified diffs](https://aider.chat/docs/unified-diffs.html)).
- **Semantic layer for cross-file identity changes only.** Rename, move, extract — the operations where LSP `WorkspaceEdit` semantics genuinely dominate — surfaced as capability-gated agent tools. The rest of the compiler-assisted surface is not worth the API weight if it forces the agent to hold valid intermediate code.
- **Structured invariants at runtime, not at edit time.** Hazel-style typed holes and MPS's "no invalid states" invariant are attractive theoretical endpoints but expensive to force onto the whole codebase. The Mo runtime-first thesis — capability-mediated inspection, structured events, deterministic replay — provides most of the same feedback loop without paying projectional-editor adoption cost.
- **Explicit protection against Coherence Collapse.** The dominant failure mode is not localization or edit-format parsing; it is the agent destroying its own recent correct work ([Coherence Collapse](https://arxiv.org/html/2603.24631v2), [Coherence Debt](https://arxiv.org/html/2608.16630v1)). A live edit-history ring, a rewind-and-replay capability ([Claude Code stale-context fix](https://aiproductivity.ai/news/claude-code-stale-context-rewind-replay-fix/)), and file-hash-based stale detection address this more directly than any editing paradigm change.
- **Stale-edit and race-condition invariants as a runtime capability.** Files change under the agent — from formatters, from concurrent teammates, from the agent's own earlier edits. A capability that returns file version, content hash, and last-write causality on every read closes the gap without requiring a new editing surface.

The choice between paradigms is best framed not as "which is right" but as "which invariant does the agent need to hold at this edit site." Text patches assume nothing and demand everything of the model. Compiler-assisted tools assume compilable code and pay back cross-file consistency. Projectional editors assume nothing invalid and pay back total correctness, at ecosystem cost. A runtime that exposes these invariants explicitly — and lets an agent choose which one it needs for a given operation — is more useful than any single paradigm run to its endpoint.
