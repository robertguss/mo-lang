---
title: "Direction 37: Runtime MCP surface — every Mo program is queryable"
created: 2026-09-13
updated: 2026-09-14
type: direction
tags: [runtime, agents, tooling]
sources: [deep-dives/agent-native-runtime-features.md, spec/design-v0/07-toolchain.md, spec/design-v0/08-milestone.md]
number: 37
status: liked
origin: "Session, 13 Sep 2026 (in response to Robert asking about agent debugging)"
confidence: medium
---

# Direction 37: Runtime MCP surface — every Mo program is queryable

Every running Mo program exposes an MCP server. The agent debugging (or operating) it calls tools directly instead of parsing logs.

```ruby
# starting tools — the surface should stay small
tools = [
  list_processes(),
  inspect_process(pid),
  query_message_history(pid, since: Time),
  send_message(pid, msg),
  pause_process(pid),
  resume_process(pid),
  get_supervisor_tree(),
  get_capabilities_in_use(pid),
  get_recent_crashes(limit),
]
```

Mo already has the data. Processes are isolated, capabilities tracked, executions deterministic. `mo check --json` and the error catalog are the compile-time surface an agent programs against today (there is no `mo mcp` command yet; Fable, on filing). This is the runtime equivalent.

The one design question worth flagging: is the MCP surface always on (with a capability required to attach), on by default in dev and opt-in in production, or off by default everywhere. Robert's framing — "allowing agents the ability to debug a process" — reads like at least dev-on. Prod is a security conversation.

Answered (Fable's recommendation, Robert agreed, 13 Sep night): the surface is a capability. `mo run` and `mo test` hold it, so it is on in development; a built binary has it off unless `main` is handed the capability and passes it down, narrowed like `Fs`. Recorded in the [[decision-log]].

## Program 1's questions (14 Sep, night)

The worker writing `jobq` listed what it wanted to ask the running service during the measurements and could not; these are the surface's first requirements, in its words, shortened: the service's state now (jobs on the board, torn, next id against reserved, opened or not); the mailbox depth under 32 workers, how many worker processes are alive, how many wait in `ask`; per update, time waiting on fsync against building the board; the last ten messages taken and what each came to; how many silent connections the listener counts against the acceptor's bound and whether it is paused; whether the service restarted, how often, with what report; where 392 MiB at 100k jobs go; which leases have run out unlooked-at and where a stuck one stands; why one update took 3 s to requeue 10,000 jobs.

## Related

- [[agent-native-runtime-features]]
- [[vm-first-vs-c-first]]
- [[d36-vm-first-runtime]]
- [[d40-structured-runtime-events]]
