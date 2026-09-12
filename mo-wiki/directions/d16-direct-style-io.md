---
title: "Direction 16: Direct-style I/O with runtime interception"
created: 2026-09-12
updated: 2026-09-12
type: direction
tags: [effects, runtime]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 16
status: liked
origin: "Robert"
---

# Direction 16: Direct-style I/O with runtime interception

`fs.read(path)` reads like Go and blocks like Erlang, but compiles to "suspend, hand a command to the runtime, resume with result." The runtime is the single interception point for capability checks, replay logging, and fault injection. Green threads, no `async` keyword, no function coloring. (Robert: matches)

## Related
- [[effects-and-capabilities]]
- [[d17-mandatory-deadlines]]
