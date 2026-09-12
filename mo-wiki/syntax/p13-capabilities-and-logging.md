---
title: "Syntax pick 13: Capabilities and logging"
created: 2026-09-12
updated: 2026-09-12
type: syntax-pick
tags: [syntax, effects]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 13
status: liked
chosen_by: Robert
---

# Syntax pick 13: Capabilities and logging

capabilities are ordinary types obtained only at the program root (`fn main(platform: Platform)`), passed down explicitly, narrowed on the way (`fs.scoped("/var/app").read_only`). No global `File.open`; a signature is the complete list of what a function can touch. **No log statements exist in Mo.** The runtime already traces calls, arguments, results, and messages deterministically for replay, and crashes carry seed + trace; ad-hoc logs are a worse copy of that and the most common secret leak. Domain events go out through a typed `Events` capability (`events.emit(RefundFailed(...))`), so `flows(CardNumber, into: Events)` is checkable.

## Related
- [[d15-effects-via-capabilities]]
- [[effects-and-capabilities]]
