---
title: "Effects and capabilities"
created: 2026-09-12
updated: 2026-09-12
type: deep-dive
tags: [effects, runtime]
sources: [raw/notion/design-journal-2026-09-12.md]
---

# Effects and capabilities

### Two ideas kept separate
- **Effect:** what a function does beyond computing (reads clock, writes ledger, sends to a process, calls network).
- **Capability:** the unforgeable permission value you must hold to perform it.
### Three ways to make effects visible
1. **Effect types (Koka).** Signature carries an effect row. Precise, handlers swap real I/O for stubs. Cost: a second type system, least familiar to models.
2. **Effects as returned data (Elm).** Pure functions return commands; runtime performs them; results arrive as messages. Cost: sequential I/O scatters across handlers and continuation-carrying message variants; the exact shape where agents drop error branches. Elm does this because JS is a single-threaded event loop, a platform constraint, not a virtue.
3. **Capabilities as parameters (Austral).** No effect types. Can't touch the filesystem without a `FileSystem` value in hand. Signature reveals effects through parameter types.
**Insight:** 2 + 3 make 1 unnecessary. If the only ways to cause an effect are holding a capability or (under the hood) issuing a command, the signature already tells the whole story with zero new type machinery.
### What command style buys, and how direct style earns it back
Command style gives: purity, interception, no blocking, visibility. **Erlang is direct-style and has all four**, because processes are cheap so blocking is free, and every effect goes through the runtime. TigerBeetle does the same in Zig with a swappable I/O interface for the simulator. Direct style loses nothing if:
- every effect is a call into the runtime, never a raw syscall (single interception point), and
- blocking is free via green threads (Go-style, no `async`, no coloring).
Under the hood `fs.read(path)` compiles to suspend / hand command to runtime / resume. Direct style is sugar over command style, as `await` is over promises, but with no keyword because every effectful call works this way. Koka's algebraic effects, Roc's `!`, Gleam's `use` are the same discovery.
| Property | How Mo gets it |
|---|---|
| Purity | No capability parameter = provably pure. Signature is the proof. |
| Interception | Runtime performs every command: capability check, replay log entry, simulator hook in one place. |
| No blocking | Green threads. 10k blocked processes cost 10k small stacks. |
| Visibility | Replay log = sequence of commands and results per process; spec altitude shows effects via capability params. |
### The cost and the law
A blocking call can block forever, breaking bounded-everything. So: **every effectful call carries a deadline**, e.g. `fs.read(path, within: 2.seconds)`. Timeout is an ordinary `Err`. Deadline and capability are the same kind of thing: a limit on authority (the "Lingering Authority" pairing).
### Result
No effect type system. No `async`. No callbacks. A function is pure unless it takes a capability; a capability call reads like Go, blocks like Erlang, records like Elm, and cannot hang.
Example:
```javascript
fn append_log(fs: FileSystem, line: Text) -> Result<Unit, IoError>
  let config = fs.read("app.toml", within: 1.second)?
  let path   = parse_log_path(config)?
  fs.append(path, line, within: 1.second)
```

## Related
- [[d15-effects-via-capabilities]]
- [[d16-direct-style-io]]
- [[d17-mandatory-deadlines]]
