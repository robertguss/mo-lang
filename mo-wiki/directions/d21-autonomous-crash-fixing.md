---
title: "Direction 21: Production crashes are fully autonomous"
created: 2026-09-12
updated: 2026-09-12
type: direction
tags: [errors, agents]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 21
status: liked
origin: "Robert"
---

# Direction 21: Production crashes are fully autonomous

A tripped `never` or contract crashes the process, the supervisor restarts it, and the agent takes the crash as a task and fixes it with no human involvement. (Robert) Consequence: the runtime must emit a complete bug report (seed, message log, state snapshot, the violated clause and its contract chain), and a fix is acceptable only if it passes all tests and contracts and weakens no `never`. If the fix requires changing the shape, [[d20-human-pulled-in-when-shape-changes|item 20]] applies and a human is pulled in. That closes the loop: the human is involved only when the shape changes, never when it is merely enforced.

## Related
- [[d18-two-kinds-of-failure]]
- [[d20-human-pulled-in-when-shape-changes]]
- [[q08-verification-tiers]]
