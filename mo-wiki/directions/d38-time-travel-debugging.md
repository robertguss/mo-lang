---
title: "Direction 38: Time-travel debugging for Mo processes"
created: 2026-09-13
updated: 2026-09-13
type: direction
tags: [runtime, agents, tooling, verification]
sources: [deep-dives/agent-native-runtime-features.md, spec/design-v0/03-semantics.md]
number: 38
status: liked
origin: "Session, 13 Sep 2026"
confidence: medium
---

# Direction 38: Time-travel debugging for Mo processes

The agent asks a running Mo system what any process was doing at any past point.

```ruby
# usage pattern the agent programs against
snapshot = at(pid, time: T - 30.seconds)
state    = snapshot.state
message  = snapshot.in_flight_message
stack    = snapshot.call_stack

next_step = snapshot.step_forward   # replay one message
until_bad = snapshot.step_until { |s| s.state.balance < 0 }
```

Mo is unusually close to this already. `Mo.Sim` is deterministic; the failure model (chapter 3) is designed around replay from snapshot plus message log; fault injection is seed-reproducible. What's missing is periodic snapshots at runtime and a query interface.

The bet: time-travel debugging is not exotic — it's the natural output of features Mo already has. Not exposing it wastes them.

Cost is real: 4–6 weeks in the VM (see [[d36-vm-first-runtime]]), and needs a story for snapshot storage (in-memory ring, on-disk, both).

## Related

- [[agent-native-runtime-features]]
- [[vm-first-vs-c-first]]
- [[d36-vm-first-runtime]]
- [[d37-runtime-mcp-surface]]
