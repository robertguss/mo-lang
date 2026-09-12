---
title: "Direction 14: Processes are the only identity, and each is an Elm-shaped state machine"
created: 2026-09-12
updated: 2026-09-12
type: direction
tags: [processes, state]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 14
status: liked
origin: "Robert"
---

# Direction 14: Processes are the only identity, and each is an Elm-shaped state machine

State + message type + pure `update` returning new state and effect commands. No globals, statics, mutexes, or singletons. Shared things (config, caches, pools) are a process or a platform-provided capability. (Robert: "that sits with me")

## Related
- [[state-model]]
- [[p10-process]]
- [[q07-process-api]]
- [[d12-concurrency-at-the-edges]]
