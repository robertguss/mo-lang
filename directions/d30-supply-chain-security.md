---
title: "Direction 30: Supply-chain security is a first-class design goal"
created: 2026-09-12
updated: 2026-09-12
type: direction
tags: [security, stdlib]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 30
status: liked
origin: "Robert"
---

# Direction 30: Supply-chain security is a first-class design goal

(Robert, session 2, very important) AI has made package-ecosystem attacks (npm, PyPI, and the rest) massive and unlike anything before. Mo and its ecosystem are designed to mitigate this from the start: a Go-sized-or-larger stdlib so most programs have zero dependencies, and a package system where a dependency can only do what it is handed a capability for. Capabilities become the permission system for packages, visible at install time. No install scripts, macros, or build-time code execution. Full question and sub-questions: Open Questions [[q17-package-management-and-supply-chain|Q17]].

## Related
- [[q17-package-management-and-supply-chain]]
- [[q11-platform-and-stdlib]]
- [[d15-effects-via-capabilities]]
