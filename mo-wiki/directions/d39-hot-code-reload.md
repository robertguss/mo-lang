---
title: "Direction 39: Hot code reload"
created: 2026-09-13
updated: 2026-09-13
type: direction
tags: [runtime, processes, tooling]
sources: [deep-dives/vm-first-vs-c-first.md, spec/design-v0/08-milestone.md]
number: 39
status: liked
origin: "Robert (session, 13 Sep 2026): 'I love the idea of hot reloading'"
confidence: medium
---

# Direction 39: Hot code reload

Swap a module's code while its processes are running. BEAM's signature feature. Chapter 8 lists it as an open question; Robert promoted it in the 13 Sep 2026 conversation as one of the two reasons to go VM-first.

What "reload" means, split by scope:

- **Dev.** Save a file, the VM reloads the module, running processes pick up the new code on the next function call. The supervisor tree keeps its shape.
- **Prod.** Deploys become code swaps, not process replacement. Long-lived processes (connections, sessions, in-flight `update` transactions) survive the deploy.

What breaks without it: dev iteration eats a 116 ms rebuild plus process teardown every save, which is fine but not zero. Prod loses the "keep the supervisor tree alive across a deploy" property that makes BEAM systems feel different.

What's hard: state migration. A process holding a `State { count: Int }` under v1 can't just start running v2 code that expects `State { count: Int, updated_at: Time }`. Erlang's answer is `code_change/3`; Mo needs its own answer. This is real design work, not just implementation.

Not on the critical path. Attractive; earn it.

## Related

- [[vm-first-vs-c-first]]
- [[d36-vm-first-runtime]]
- [[agent-native-runtime-features]]
