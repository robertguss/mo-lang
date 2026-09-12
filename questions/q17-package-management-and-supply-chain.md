---
title: "Q17: Package management and supply-chain security"
created: 2026-09-12
updated: 2026-09-12
type: question
tags: [security, stdlib]
sources: [raw/notion/open-questions-2026-09-12.md]
number: 17
status: answered
answer: in
asked: 2026-09-12
---

# Q17: Package management and supply-chain security

**Raised by Robert (session 2), flagged as very important.** Two linked goals:
1. **A robust standard library that minimizes the need for third-party packages.** Learn from Go: most programs should have zero dependencies.
2. **An ecosystem designed against supply-chain attacks from day one.** npm and the other popular package managers are being hit at a scale AI has made unprecedented (malware, typosquatting, maintainer takeover, install scripts, dependency confusion). Mo and its ecosystem must be designed to mitigate this and keep people and software safe. Robert: "I don't know what this looks like yet, but we need to enforce security somehow."
**What Mo already has that helps (to build on, not yet decided):**
- **Capabilities are the permission system.** A package can only do what it is handed. A JSON library that takes no `Network` parameter provably cannot phone home. This is the property npm fundamentally cannot offer, and it should be visible at install time: "this package needs: nothing" vs "this package needs: Network, FileSystem".
- **No escape hatch in application code ([[q16-escape-hatch|Q16]]).** Unsafe code lives only in platforms, so a library cannot smuggle in raw syscalls.
- **No install scripts, no macros, no build-time code execution.** The three biggest npm/PyPI attack surfaces do not exist in the language.
- **Content-addressed declarations ([[q10-semantic-ids-and-editing|Q10]]).** Every function has a hash; a package is a set of hashes, so "what changed in this version" is exact and "the registry served different bytes" is detectable.
- **`flows(...)` checks.** Information-flow rules can state that no secret reaches a dependency's outputs.
**Open sub-questions for the design pass:** registry model (central vs. vendored vs. Go-style URL modules); immutable versions and a transparency log; signing and who signs; capability manifests as part of a package's published interface, with any widening being a breaking change a human sees (the same rule as `never` clauses); minimum-privilege by default when adding a dep; typosquat resistance (namespacing, name reservation, similarity checks); how the toolchain audits a platform, since platforms are the trusted layer; whether the stdlib ceiling ([[q11-platform-and-stdlib|Q11]]) should be raised to keep more of the common surface first-party. Needs fresh web research on 2025–2026 supply-chain incidents and on what Go, Deno, and cargo-vet have tried.

## Answer

✅ **Robert: IN on ordering B** (session 2): start `docs/design-v0.md` now, research Q17 in parallel, slot the package chapter in when it lands. No package design is recommended until the research pass is done. Robert will run deep-research prompts with his own tools and share results back (see SCHEMA, "Research"). Research must include academic papers (arXiv etc.), not only blog posts and incident reports.

## Session 3 answer: the package design

✅ **Robert: IN** (session 3) on Claude's recommendation from [[supply-chain-defenses]]. Six layers, no new language syntax:

1. **Language.** No install scripts, macros, or build-time code. Capabilities are the permission system; [[d31-effects-never-hide-in-a-value|direction 31]] closes the callback hole. Platforms are the whole trusted base: the lockfile records each platform's native-code hash, and `mo` refuses an unaudited platform without a human's `--trust`.
2. **Identity.** A package version is a set of declaration hashes ([[unison]], [[q10-semantic-ids-and-editing|Q10]]) pinned in the lockfile. The registry serves bytes that must match; every version goes into a transparency log ([[go]]). Source only, never binaries.
3. **Registry policy.** One central registry. Publishing needs a WebAuthn key; no token type can publish alone; CI publishes only through short-lived identity, with a second signer required for widely used packages.
4. **Age gate.** `mo add` and `mo update` refuse versions younger than 3 days by default. Override needs a human, never an agent.
5. **The install conversation.** `mo add` prints the compiler-computed capability manifest (`json 1.4.2  needs: nothing`). A widening on update is a breaking change that pulls a human in, the same rule as `never` ([[d20-human-pulled-in-when-shape-changes|direction 20]]). Unknown or hours-old names are refused (slopsquatting).
6. **Stdlib.** Keep [[q11-platform-and-stdlib|Q11]]'s Go-sized ceiling plus an explicit "copy a function rather than add a dependency" norm in the agent guidance. Dependencies are source in the tree.

Deferred until measured: cargo-vet-style shared audits; two versions of one package in one program (forbidden in v0).

**Additions from [[aube]]** (Robert asked for it to be reviewed the same message): a defaults table with a fail/warn/opt-in boundary per check and stable error codes; trust evidence is monotone across versions, enforced at publish; two separate gates, version age (3 days) and name age (30 days), with `mo update` falling back to the newest old-enough version; four reputation signals served by the registry with namespace-aware name similarity; a signed revocation bloom filter for offline builds; no dependency bypasses the registry except in-repo path deps; `mo find-hash` over declaration hashes for incident response.

First tested by: a registry prototype and `mo add` against the example corpus.

## Related
- [[d30-supply-chain-security]]
- [[q11-platform-and-stdlib]]
- [[q16-escape-hatch]]
- [[prompts-q17-supply-chain|research prompts]]
