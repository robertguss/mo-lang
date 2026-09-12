---
title: "Direction 18: Two kinds of failure, two mechanisms, never crossing"
created: 2026-09-12
updated: 2026-09-12
type: direction
tags: [errors, processes]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 18
status: liked
origin: "Robert"
---

# Direction 18: Two kinds of failure, two mechanisms, never crossing

Expected failure ("rain") is an `Err` value, exhaustive, in the signature, handled by the caller. A bug ("broken roof": contract or invariant violated) crashes the process. **No try-catch anywhere in the language.** A crash can only be restarted by a supervisor, logged, and handed to an agent with seed + message log. Agents can never convert a bug into a handled outcome. (Robert: "definitely in")

## Related
- [[errors-and-failure]]
- [[p06-results-and-propagation]]
- [[d21-autonomous-crash-fixing]]
