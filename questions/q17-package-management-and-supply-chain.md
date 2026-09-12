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

## Related
- [[d30-supply-chain-security]]
- [[q11-platform-and-stdlib]]
- [[q16-escape-hatch]]
- [[q17-supply-chain|research prompts]]
