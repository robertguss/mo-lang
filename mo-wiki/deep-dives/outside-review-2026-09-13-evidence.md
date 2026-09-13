---
title: "Outside review, 13 Sep 2026: evidence"
created: 2026-09-13
updated: 2026-09-13
type: deep-dive
tags: [meta, laws, processes, verification, runtime]
sources: [examples/programs/kv, toolchain/src/caps.zig, toolchain/src/sim.zig, toolchain/src/server.zig, plans/control-run-2.md]
confidence: high
---

# Outside review, 13 Sep 2026: evidence

Every probe below was run against `toolchain/zig-out/bin/mo` built from `main` on 13 Sep 2026 (`zig build test` green, 3m52s). The conclusions are in [[outside-review-2026-09-13]].

## P1. Recursion is unbounded and uncaught

```mo
fn forever(n: UInt64) : UInt64
  forever(n)
end
```

`mo check` exits 0. `mo run` prints a Zig stack trace ending in `start.zig:190` and exits 134. `spec/design-v0/02-laws.md` says "bounded everything"; `spec/design-v0/03-semantics.md` says recursion is "structural only, proved terminating; to be confirmed." Nothing enforces it, and the failure is not a Mo crash report but a runtime abort.

## P2. The `for`-only law produces fictional bounds

`examples/programs/kv/server.mo` L105–128: `talk` runs `for _ in 0..10_000` around `talk_awhile`, which runs `for _ in 0..10_000` around `exchange`. Comment: "a connection gets at most 100 million lines." The accept loop in the same file uses the same shape. The law asked for a bound; the program gave it a number that bounds nothing.

## P3. `invariant` polarity

```mo
invariant "count never exceeds 3"
  state.count <= 3
end
```

One `Bump` then `Read`:

```
FAIL  test "bump once": invariant "count never exceeds 3" tripped in Counter; state = Counter(count: 1)
```

The block must be true when the invariant is *broken* (`spec/grammar.md`). The natural reading fails on the first valid state.

## P4. Fault injection and vacuous assertions

`examples/programs/kv/log.mo` L309–321:

```mo
assert first is Ok(Ok(108)) or first is Ok(Error(_)) or first is Error(_)
```

`server.mo` L197–202, `heard_so_far?`: `Error(_): true`, and `Ok(lines)` passes for an empty list. Neither is a strict tautology (a wrong byte count still fails), but both pass with zero successful operations, so the test titles overclaim.

## P5. Exhaustiveness without grouping

`log.mo` L171–181, `applied`: six arms with the identical body `Error(BadLine(number: number))`. The no-catch-all law (MO0309) is right; the missing piece is `A | B | C: body`.

## P6. Handles are not capabilities

`toolchain/src/caps.zig` L140–159: `capIn` recognises `.cap` inside list/option/set/result/map/tuple, nothing else. `Handle(T)` is not `.cap`. `server.mo` `answer(store: Handle(Store), ...)` performs `store.ask(...)` with no capability parameter, so the premise's "no capability param ⇒ pure" is false for any function holding a handle.

## P7. Closures may capture and use a capability

```mo
fn shout(out: Out, xs: List(String)) : UInt64
  xs.map(fn(x) out.write_line(x) end)
  xs.size
end
```

Checks and runs (prints `a`, `b`, `2`). "Captures are read-only" is true; "captures are effect-free" is not. The discarded `map` result is not flagged either.

## P8. `update` is not a transaction across effects

`toolchain/src/sim.zig` L363–383: `ask` delivers to the target and runs its `update` before returning to the caller; a later crash in the caller cannot undo that. Comment on L366: "A Timeout's message still arrives." `toolchain/src/server.zig` L276–301: `fs.write` fsyncs, then checks lateness; the doc comment says "a write that took longer is `Timeout`, and is on disk all the same." Restart empties the mailbox (sim.zig L378 comment) and reruns init; `examples/programs/kv/store.mo` L95–99 sets `restart: :never` because a restarted store "would forget every change since."

## P9. The durability `never` checks self-reported witnesses

`store.mo` L9–13 checks `Step.all` for `s.after != s.before and !s.logged`. `Step` is built by the implementation at L208–209 with literal `logged: true` after a successful `Append`. An implementation that skips the journal and still writes `logged: true`, or never constructs a `Step`, passes. Useful instrumentation; not independent evidence.

## P10. Deadlines as literals

`kv/*.mo`: `within: 60_000.ms`, `within: 1.minute`, `within: 5_000.ms`, `within: 1_000.ms`, `within: 100.ms` across calls with no derivation from a request budget.

## P11. Control run, round 2 (repo's own numbers)

[[control-run-2]]: Mo 11.8 min, Go 8.2, Python 7.9; zero check-caught bugs in any language; Mo functions shortest (median 3 lines) under a law that makes short functions compulsory. The Quasar-style control (Go/Python subset plus Mo's checks) from [[case-against-new-languages]] has not been run.

## P12. Worker defaults now in the semantics

[[decision-log]]: zero-value `state` fields; order-sensitive equality for maps and sets; write-after-timeout behaviour; contracts-off default (overturned only at step-13 acceptance). Each was implemented first and ratified after.

## P13. Roc precedent for "the platform provides all I/O"

Librarian survey of `roc-lang/roc` and `roc-lang/examples`: two general-purpose platforms carry the ecosystem (`basic-cli`, `basic-webserver`); `docs/langref/platforms.md` still says there is no official platform-authoring guide; a host must supply `roc_alloc`/`roc_dealloc`/`roc_realloc`/`roc_dbg`/`roc_expect_failed`/`roc_crashed` and per-target link inputs; the `Task` effect type was removed in Jan 2025 in favour of direct-style `!` functions with purity inference. Application code has no FFI; every unsupported native library becomes platform work.

## What worked well in the probes

Diagnostics are the best part of the toolchain: multiple diagnostics per run, MO0301 (70 lines) and MO0309 (catch-all) both carry a correct "why", `--json` is clean, `mo fmt --stdout` is idempotent, named functions are first-class (`f = double`), `test rejects` trips a `requires` with a readable report, process crash reports name the process, seed, message history and prior state.

## Related

- [[outside-review-2026-09-13]]
- [[control-run-2]]
- [[decision-log]]
