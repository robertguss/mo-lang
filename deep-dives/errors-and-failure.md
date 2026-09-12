---
title: "Errors and failure: rain vs broken roof"
created: 2026-09-12
updated: 2026-09-12
type: deep-dive
tags: [errors, processes]
sources: [raw/notion/design-journal-2026-09-12.md]
---

# Errors and failure: rain vs broken roof

**Rain vs broken roof.** Rain is expected (missing file, slow network, bad input): bring an umbrella, i.e. return `Err`. A broken roof is a bug (negative balance, impossible state): you cannot fix it with an umbrella. Continuing means acting on a world that doesn't exist, and every step spreads damage.
**Try-catch is grabbing a broken-roof problem and treating it as rain.** Agents do it more than humans because their job is to make the red go away. Remove it and the guarantee is structural.
**Erlang's move:** make dying cheap. Small processes + supervisor restart from known-good state = a reset, not a catastrophe.
|  | Expected failure | Bug |
|---|---|---|
| Looks like | `Err(FileNotFound)` returned | `requires` / `ensures` / invariant fails |
| Who handles | Caller, via exhaustive `match` or `?` | Nobody. Process dies. |
| Next | Program continues by design | Supervisor restarts process from clean state |
| Who learns | Whoever handled it | An agent: crash + seed + message log = fix task |
**Unlocks:** every crash is a real bug and vice versa, so the crash log is a noise-free agent work queue; contracts have teeth (tripwires that can't be disarmed); supervision is the only recovery story, so every program has one and failures stay contained.
**Costs:** design process boundaries with restart in mind (smaller processes, persist as messages arrive); untrusted input is rain and must be `Result`, discipline: "if it comes from outside the program, it's rain"; no log-and-continue for real bugs (restart-and-report beats limp-along-and-hide when agents fix bugs in minutes).
`?` is kept for upward propagation only, never for discarding.

## Related
- [[d18-two-kinds-of-failure]]
- [[d21-autonomous-crash-fixing]]
