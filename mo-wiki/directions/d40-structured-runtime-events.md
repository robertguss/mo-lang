---
title: "Direction 40: Structured runtime events, not log lines"
created: 2026-09-13
updated: 2026-09-14
type: direction
tags: [runtime, agents, tooling, errors]
sources: [deep-dives/agent-native-runtime-features.md, spec/design-v0/05-verification.md]
number: 40
status: liked
origin: "Session, 13 Sep 2026"
confidence: medium
---

# Direction 40: Structured runtime events, not log lines

Every scheduler preemption, GC pass, supervisor restart, capability check, mailbox overflow, and timeout is a structured event with a schema — not a log message.

The gap: chapter 5's structured diagnostics apply to compiler output; the crash report is structured; runtime events currently emit as prose. That leaves the same gap Mo already rejects everywhere else — the agent parses text at runtime that could have been structured at emission.

Two forms of the same event, for contrast:

```
# prose (what runtime emits today, at scheduler preemption)
process 42 preempted after 4096 reductions

# structured (what this direction proposes)
{ kind: :scheduler.preempted,
  pid: 42,
  reductions: 4096,
  blocked_on: { kind: :http.get, url: "...", deadline_ms: 500, remaining_ms: 340 },
  mailbox_depth: 14,
  mailbox_limit: 100 }
```

The event stream feeds the [[d37-runtime-mcp-surface|MCP surface]], feeds the [[d38-time-travel-debugging|time-travel debugger]], and feeds crash reports. Design-heavy (defining the taxonomy of events), code-light (emission is 15-ish sites in the runtime).

Open question: what the events go over (a ring buffer queryable via MCP, a stream to stdout in structured form, both). Worth answering as part of the MCP surface work.

## Built, step 23 (14 Sep)

The ring of structured events in both runtimes (`Updated` with its duration and wait, `Started`, `Ended`, `Restarted`, `Crashed` with the report's fields, `Overflowed`, `TimedOut`, `SourcePaused`, `SourceResumed`, `Sent`, `Paused`, `Resumed`), 4,096 by default, read by the surface and printed after a failed seed's interleaving; 112 bytes an event native, 1.4 percent on a hot native path ([[interpreter-step-23]]).

## Related

- [[agent-native-runtime-features]]
- [[vm-first-vs-c-first]]
- [[d37-runtime-mcp-surface]]
- [[d38-time-travel-debugging]]
