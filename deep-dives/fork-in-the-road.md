---
title: "The fork in the road: three products called 'a language for AI'"
created: 2026-09-12
updated: 2026-09-12
type: deep-dive
tags: [philosophy, agents]
sources: [raw/notion/design-journal-2026-09-12.md]
---

# The fork in the road: three products called 'a language for AI'

"A language for AI" means three different products:
1. **A language AI writes and humans review.** Optimized for verification and review, not typing. Contracts, effects, exhaustive errors, no hidden control flow, structured compiler diagnostics that act as the agent's teacher. **Claude leans here.**
2. **A language for orchestrating agents.** LLM calls, tool capabilities, budgets, retries, structured concurrency as primitives. Pel lives here. Smaller, DSL-shaped bet.
3. **A spec language where the AI is the compiler.** Humans write intent, model generates a verified implementation, code is an invisible intermediate. Boldest, mostly a research project.
**Recommendation:** option 1, with the capability model from option 2 baked in, since agents will also be the ones running the code.

## Related
- [[d01-agents-write-the-code]]
- [[research-summary-2026-09]]
