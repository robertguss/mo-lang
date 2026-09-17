---
title: "Mo vs aube"
created: 2026-09-12
updated: 2026-09-17
type: comparison
tags: [research, security, tooling]
sources: [raw/articles/aube-security-docs-2026-09-12.md]
confidence: medium
---

# Mo vs aube

**One line:** aube is a Node package manager in Rust (jdx, 2026) whose security defaults are the most complete client-side answer to the 2024–26 npm incidents. Robert asked what Mo can glean from it (session 3). It is a *client* over a registry it doesn't control, so everything it does is a heuristic where Mo can have a rule. Read against [[q17-package-management-and-supply-chain|Q17]] and [[supply-chain-defenses]].

## What aube does, and the Mo verdict

- **A defaults table with a boundary per check.** Every protection is listed with its default and whether it fails, warns, or needs opt-in; `paranoid: true` flips the whole strict bundle. Stable error codes (`ERR_AUBE_MALICIOUS_PACKAGE`, exit 48).[152]
  - *Verdict:* **steal the form.** Mo's package chapter in `spec/design-v0/06-packages.md` gets the same table, and the package manager's errors go in the [[q09-compiler-diagnostics|Q9]] error catalog. Mo's difference: agents are the caller, so every "prompt the human" row is "fail; a human overrides".
- **Trust policy `no-downgrade`.** A version with weaker publishing evidence (staged approval > trusted publisher > provenance > none) than an earlier version is blocked. Versions already in the lockfile are trusted. A built-in list of 12 popular packages is exempted because their release process is inconsistent.[152]
  - *Verdict:* **steal, moved to the registry.** Mo's registry refuses the publish, so no client ever needs an exceptions list. The built-in exemptions are what a client-only policy costs. It joins Mo's rule that capability widening is a breaking change: *trust and capabilities are both monotone across versions unless a human says otherwise.*
- **Release age gate.** 24 hours by default (3 days in their example), separate from a 30-day new-*name* quarantine. Non-strict mode falls back to the newest old-enough version; strict fails.[152]
  - *Verdict:* **already have** (Q17 layer 4, 3 days). Take the two-clock split: version age and name age are different gates. Take the fallback rule: `mo update` picks the newest version older than the gate rather than failing.
- **Four reputation signals on `add`:** known-malicious advisory (fail), similar name against a 100K-name popularity snapshot compiled into the binary (did-you-mean, fail when non-interactive), low weekly downloads under 1,000 (prompt, fail when non-interactive), name created under 30 days ago (same).[152]
  - *Verdict:* **steal all four** as registry-side data served with the package index, since Mo has one registry. The namespace-aware similarity rule (compare basenames within a scope, full names across scopes) is worth copying exactly.
- **Malicious-advisory checks with a bloom filter.** Live check on `add`/`update`/fresh resolution; a ~380 KB bloom filter (0.1% false positives) for plain reinstalls; a local mirror as a third backend. Each has a documented fail-open or fail-closed setting.[152]
  - *Verdict:* **steal** the bloom trick for `mo build` offline: the registry publishes a signed revocation filter; hits escalate to an exact check.
- **Block exotic transitive sources.** Transitive deps may not come from git, paths or tarball URLs; only direct deps you pinned yourself may.[152]
  - *Verdict:* **steal**, stricter: in Mo *no* dependency bypasses the registry except a path dep inside the same repo.
- **Default-deny lifecycle scripts, a suspicious-script sniff, and a jail** (Landlock + seccomp on Linux, Seatbelt on macOS; writes and network denied, *reads unrestricted*).[152]
  - *Verdict:* **already have, by construction.** Mo has no install or build scripts ([[d30-supply-chain-security|direction 30]]), so the sniff, the allowlist and the jail have no job. The admitted hole, "reads remain unrestricted", is exactly what capability parameters close. Mo's manifest is what the sniff approximates.
- **Content-addressed store (BLAKE3) and `find-hash`:** which cached packages contain a given file hash.[152]
  - *Verdict:* **steal** as `mo find-hash` over declaration hashes ([[q10-semantic-ids-and-editing|Q10]]): given a malicious function's hash, list every package version that contains it. Incident response in one command.
- **Pluggable scanner (Bun's API), fail-closed on any failure**, with the scanner's environment scrubbed of tokens.[152]
  - *Verdict:* **later.** The fail-closed contract is right. Mo's scanner hook, if any, is a `Platform`-less Mo function that receives the resolved graph and returns advisories, so it cannot exfiltrate anything.

## What aube cannot do

- It cannot know what a package *does*. Every gate is about who published it, when, and what its name looks like. Mo's compiler computes the capability manifest.[152]
- It cannot stop a script that reads secrets (reads are unrestricted in the jail).[152]
- Its strongest rule needs a hand-maintained exceptions list because the registry doesn't enforce it.[152]

## What Mo takes (added to the Q17 answer)

1. The defaults table with a boundary per check, and stable error codes.
2. Trust is monotone across versions, enforced at publish time.
3. Two gates: version age (3 days) and name age (30 days); `mo update` falls back to the newest old-enough version.
4. Four reputation signals served by the registry; namespace-aware similarity.
5. A signed revocation bloom filter for offline builds.
6. No dependency bypasses the registry except in-repo path deps.
7. `mo find-hash` over declaration hashes.

## Sources

[152] https://aube.sh/security.html — aube: Security and related docs (raw/articles/aube-security-docs-2026-09-12.md)

## Related
- [[q17-package-management-and-supply-chain]]
- [[supply-chain-defenses]]
- [[go]]
- [[d30-supply-chain-security]]
