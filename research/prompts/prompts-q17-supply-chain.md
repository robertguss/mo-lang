---
title: "Research prompts: Q17 supply-chain security and package management"
created: 2026-09-12
updated: 2026-09-12
type: concept
tags: [research, security, stdlib]
sources: [raw/notion/open-questions-2026-09-12.md]
status: open
---

# Research prompts: Q17 supply-chain security and package management

For Robert to run with his deep-research tools. Results go in `raw/research-runs/`. One topic per prompt.

## Prompt 1 — incidents, 2024–2026
> Compile a timeline of significant software supply-chain attacks on package ecosystems (npm, PyPI, crates.io, RubyGems, Go modules, Maven, NuGet, VS Code extensions, GitHub Actions) from January 2024 to today. For each: the vector (typosquatting, maintainer-account takeover, install scripts, dependency confusion, malicious update to a popular package, CI compromise, AI-generated slopsquatting, other), scale, and how it was detected. End with a ranked list of which vectors caused the most damage and which are growing fastest, with sources.

## Prompt 2 — defenses that exist
> Survey the defenses package ecosystems and languages have shipped or proposed against supply-chain attacks: Go's module proxy and checksum database, Deno's permission model, cargo-vet and cargo-crev, npm provenance / Sigstore, SLSA, reproducible builds, PyPI trusted publishing, capability-safe languages (Austral, Pony, E, Wyvern, Roc platforms). For each: what it prevents, what it does not, adoption, and the strongest published criticism. Include peer-reviewed papers (arXiv, USENIX Security, IEEE S&P, CCS) as well as engineering write-ups.

## Prompt 3 — the academic view
> Find academic papers (2019–2026) on: object-capability security applied to package/dependency management; language-level permission systems for third-party code; information-flow control for libraries; and measuring the attack surface of package registries. Summarize each in three sentences: claim, method, result. Flag any that propose a design where a dependency's permissions are visible in its type signature or manifest.

## Related
- [[q17-package-management-and-supply-chain]]
- [[d30-supply-chain-security]]
