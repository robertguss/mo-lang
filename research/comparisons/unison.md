---
title: "Mo vs Unison"
created: 2026-09-12
updated: 2026-09-12
type: comparison
tags: [research, tooling, agents]
sources: [raw/articles/unison-the-big-idea.md, raw/articles/unison-1-0-announcement.md, raw/articles/lwn-programming-in-unison.md, raw/articles/unison-scratch-files.md, raw/articles/unison-release-1-1-0.md, raw/articles/unison-release-1-4-0.md, raw/articles/unison-update-code-workflow.md]
confidence: medium
---

# Mo vs Unison

**One line:** the direct ancestor of Mo's declaration IDs and content hashes ([[q10-semantic-ids-and-editing|Q10]], [[d29-edit-by-declaration-id|direction 29]]), and the cautionary tale of dropping text files; on the list to decide what to take and what that choice cost Unison.

## What it is (status as of Sep 2026)

Unison has been in development since 2013. It stores code "in a database, instead of a set of text files".[74] Version 1.0 "marks a point where the language, distributed runtime, and developer workflow have stabilized". It ships with Unison Share, a code host, and Unison Cloud, a deployment platform.[73] Releases continued through 1.4.0 in August 2026.[77] The codebase manager, `ucm`, now includes MCP tools for coding agents (`history`, `reflog`, `share-project-info`).[76]

## The ideas, one by one

- **A definition *is* its hash.** "Each Unison definition is identified by a hash of its syntax tree". Before hashing, argument names become positional references and dependencies become their own hashes. So the hash "pins down all its dependencies". Names are separate metadata that point at hashes.[72] Renaming "can never break anything".[74]
  - *Mo today:* a stable ID per declaration in a `.mo.ids` sidecar, with "the content hash of a declaration (for caching) … separate from its identity (for editing)" ([[q10-semantic-ids-and-editing|Q10]]).
  - *Verdict:* **already have**, split in two. **Steal** Unison's exact hash recipe (normalize names, substitute dependency hashes) as the definition of Mo's content hash.

- **The codebase is a database; text is a view.** Names live in the codebase and are "materialized as text only when reading or editing your code".[73] You type into a `.u` scratch file, and `ucm` watches it, parses it, and typechecks it on save.[75] Unison's move to SQLite gave a 100x smaller codebase.[73]
  - *Mo today:* "text as the source of truth" ([[q10-semantic-ids-and-editing|Q10]]).
  - *Verdict:* **reject**, as already decided. The cost is recorded below.

- **No builds, cached forever.** A definition's hash never changes meaning. It is parsed and typechecked once, and the result is stored "in a cache which is never invalidated", as part of the codebase format. The same holds for tests: "no need to rerun a deterministic test if none of its dependencies have changed".[72] Watch expressions are cached by hash too.[75]
  - *Mo today:* tests cached by hash ([[p12-tests|pick 12]]), and tier 3 cached by hash ([[q08-verification-tiers|Q8]]).
  - *Verdict:* **already have** the intent. **Steal** the granularity: per declaration, not per file as in [[roc]].

- **No dependency conflicts.** Two versions of a library's `Email` type are simply two hashes and can coexist. Even the standard library is handled like any library, so a program "can use different versions of the standard library internally without conflict".[74][72] Upgrades rely on three things: small libraries, interfaces expressed as abilities, and *patches*. A patch records which new definitions replaced which old ones, so dependents can be upgraded mechanically.[74] Locally, `update` opens any dependents that stop typechecking in your editor, on a temporary branch, until they typecheck again.[78]
  - *Mo today:* "a package is a set of hashes", with registry design explicitly unresolved ([[q17-package-management-and-supply-chain|Q17]]). A changed `pub` signature is a breaking version ([[p14-modules|pick 14]]).
  - *Verdict:* **open** (a Q17 input). Coexisting versions end version conflicts but allow two `Email` types that don't unify.

- **Code moves across machines by hash.** A sender ships bytecode, and the receiver fetches missing dependencies by hash.[72] Unison Cloud deploys this way.[73]
  - *Mo today:* a single static binary, no VM, no hot loading ([[d08-beam-qualities-without-the-beam|direction 8]]).
  - *Verdict:* **reject** for Mo's domain.

- **Abilities (effects) in types.** A function can't use an ability it hasn't declared, and a test swaps in a different handler.[74]
  - *Mo today:* capabilities, no effect types ([[d15-effects-via-capabilities|direction 15]]).
  - *Verdict:* **reject**, as already weighed on [[koka]].

- **An agent interface in the toolchain.** Since 1.1.0 `ucm` exposes MCP tools for history, reflog, and project info,[76] with further MCP tweaks in 1.4.0.[77]
  - *Mo today:* `mo edit <id>`, `mo rename`, and JSON diagnostics are designed for agents ([[q10-semantic-ids-and-editing|Q10]], [[q09-compiler-diagnostics|Q9]]). No MCP decision yet.
  - *Verdict:* **steal**: an MCP server over Mo's edit-by-ID, diagnostics and history from the first toolchain release.

## What it gives up

The cost of leaving text, in LWN's words:[74]
- **Existing tools.** "The community can't really reuse existing tooling. Tools like Unison Share must be written from scratch."
- **Git as a reading surface.** Code pushed to Git "isn't human-readable" without Unison's own tools.
- **Mixed-language programs.** The benefits come "only when an entire program is written in it". With no stable FFI, programs "reimplement a lot of functionality".

Mo keeps text, so it keeps Git, GitHub review, grep and every editor ([[q10-semantic-ids-and-editing|Q10]]). Its FFI home is the platform ([[q16-escape-hatch|Q16]]). Mo's counter-risk: `.mo.ids` can drift from the text when someone edits outside the tools. That is untested.

## Evidence

- **Codebase size:** the move to SQLite cut codebase size 100x.[73]
- **Longevity:** in development since 2013, 1.0 stabilized,[74][73] steady releases through August 2026.[77]
- **Adoption:** no user or package counts found this pass. LWN notes the library ecosystem has "a long way to go".[74]
- **LLMs and content-addressed code:** MCP tooling exists,[76] but no measured results were found.

## What Mo should take from this

- **Confirmed, no change:** Q10's text-first split stands. Unison's recorded costs are the ones Mo avoids.[74]
- **Proposal:** define Mo's declaration content hash Unison's way: normalize local names to positions and replace every referenced declaration with its hash.[72] "A package is a set of hashes" ([[q17-package-management-and-supply-chain|Q17]]) then becomes literally true, and test caching ([[p12-tests|pick 12]]) becomes exact.
- **Proposal:** keep the typecheck and test cache inside the project, keyed by that hash and never invalidated,[72] rather than in a disposable build directory.
- **Question for Robert (Q17):** may one program hold two versions of a package, as Unison allows, or exactly one per package, as Go's minimal version selection allows ([[go]])?
- **Proposal:** every published version carries a toolchain-generated patch (old hash → new hash)[74] so dependents upgrade mechanically. It pairs with `mo fix` from [[go]].
- **Proposal:** ship an MCP server over `mo edit` / `rename` / diagnostics / history in the first toolchain release.[76]
- **Risk to measure:** `.mo.ids` drift after plain-text edits ([[d29-edit-by-declaration-id|direction 29]]). Count ID-loss events in the corpus.

## Related
- [[language-landscape]]
- [[q10-semantic-ids-and-editing]]
- [[d29-edit-by-declaration-id]]
- [[q17-package-management-and-supply-chain]]
- [[p12-tests]]
- [[q08-verification-tiers]]
- [[go]]
- [[roc]]

## Sources

[72] https://www.unison-lang.org/docs/the-big-idea — Unison: The big idea
[73] https://www.unison-lang.org/unison-1-0 — Announcing Unison 1.0
[74] https://lwn.net/Articles/978955 — Programming in Unison (LWN.net)
[75] https://www.unison-lang.org/docs/tour/_scratch-files — Unison's interactive scratch files
[76] https://github.com/unisonweb/unison/releases/tag/release/1.1.0 — Unison release 1.1.0
[77] https://newreleases.io/project/github/unisonweb/unison/release/release%2F1.4.0 — Unison release 1.4.0 (Aug 2026)
[78] https://www.unison-lang.org/docs/usage-topics/workflow-how-tos/update-code — Unison: Common workflows for updating code
