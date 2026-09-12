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

## Prompt 1 — incidents, 2024–2026 (rephrased: the first version was refused by model providers as malicious-looking)
> I'm designing the package manager for a new programming language and want it to be resilient to the software supply-chain incidents that have hit existing ecosystems. Using public post-mortems, vendor advisories (GitHub, npm, PyPI, crates.io, RubyGems, Go, Maven Central, NuGet, VS Code Marketplace, GitHub Actions), and security-firm reports (Socket, Phylum, Sonatype, Snyk, ReversingLabs), summarize the notable incidents from January 2024 to today. For each, record: the ecosystem, the date, the category the reporters assigned it (e.g. compromised maintainer account, malicious version of a popular package, lookalike package name, install-time script abuse, dependency confusion, CI/build-pipeline compromise, AI-related name hallucination), the estimated reach (downloads or affected projects, as reported), who detected it and how (registry scanning, community report, vendor telemetry), and what mitigation the ecosystem adopted afterward. Close with a table ranking categories by reported impact and by trend over the period, and a list of the defenses that have demonstrably reduced repeat incidents. Cite every source.

If a tool still refuses, drop the parenthetical category list and let it classify on its own.

## Prompt 2 — defenses that exist
> Survey the defenses package ecosystems and languages have shipped or proposed against supply-chain attacks: Go's module proxy and checksum database, Deno's permission model, cargo-vet and cargo-crev, npm provenance / Sigstore, SLSA, reproducible builds, PyPI trusted publishing, capability-safe languages (Austral, Pony, E, Wyvern, Roc platforms). For each: what it prevents, what it does not, adoption, and the strongest published criticism. Include peer-reviewed papers (arXiv, USENIX Security, IEEE S&P, CCS) as well as engineering write-ups.

## Prompt 3 — the academic view
> Find academic papers (2019–2026) on: object-capability security applied to package/dependency management; language-level permission systems for third-party code; information-flow control for libraries; and measuring the attack surface of package registries. Summarize each in three sentences: claim, method, result. Flag any that propose a design where a dependency's permissions are visible in its type signature or manifest.

## Related
- [[q17-package-management-and-supply-chain]]
- [[d30-supply-chain-security]]
