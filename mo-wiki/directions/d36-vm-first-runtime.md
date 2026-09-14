---
title: "Direction 36: VM-first runtime, C backend as an optimization"
created: 2026-09-13
updated: 2026-09-13
type: direction
tags: [runtime, compiler, performance, agents]
sources: [deep-dives/vm-first-vs-c-first.md, spec/design-v0/07-toolchain.md]
number: 36
status: liked
origin: "Robert (session, 13 Sep 2026)"
confidence: medium
---

# Direction 36: VM-first runtime, C backend as an optimization

Robert (session, 13 Sep 2026): "You are beginning to persuade me that we should be VM first because I love the idea of hot reloading and also allowing agents the ability to debug a process."

The current build order (chapter 7) is interpreter → C via Zig → native only if required. This direction flips that in framing: the VM is the reference runtime, the C backend is an ahead-of-time optimization of it. Nothing about today's implementation changes; the differential test discipline stays. What changes is what Mo optimizes for over the next year: features that live in the VM cleanly (hot reload, live introspection, reduction-counted scheduling) become priorities, and native code becomes a deployment target rather than the default.

Not locked. This direction is the frame under which [[d37-runtime-mcp-surface|d37]], [[d38-time-travel-debugging|d38]], [[d39-hot-code-reload|d39]], and [[d40-structured-runtime-events|d40]] all become easier.

## Related

- [[vm-first-vs-c-first]]
- [[agent-native-runtime-features]]
- [[d37-runtime-mcp-surface]]
- [[d38-time-travel-debugging]]
- [[d39-hot-code-reload]]
- [[d40-structured-runtime-events]]
