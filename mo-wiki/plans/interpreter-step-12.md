---
title: "Step 12: the runtime under real programs, brief for the worker"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [runtime, performance, stdlib, tooling]
sources: [examples/programs/kv/TOOLCHAIN-BUGS.md, examples/GAPS.md]
status: in-progress
---

# Step 12: the runtime under real programs

Program 3 (`examples/programs/kv/`) runs and answers 15k GETs a second, but it found six toolchain bugs and eight gaps that make a long-running server impossible today: maps search linearly, a map in process state is copied on every write and never freed, a process keeps what every request cost it, and nothing writes a file. This step fixes all of it. The C backend waits until the runtime it would compile is honest.

## Orientation

`examples/programs/kv/TOOLCHAIN-BUGS.md` (six bugs with reproductions, read first), the last eight lines of `examples/GAPS.md`, `toolchain/src/corpus.zig`, `stdlib.zig`, `vm.zig` (regions, memoization, process values), `sim.zig`, `server.zig`, `fmt.zig`, `spec/design-v0/09-stdlib.md`.

## Write scope

`toolchain/`, `examples/`, rows appended to `mo-wiki/spec/design-v0/09-stdlib.md`. Branch `session-05`, one commit per part, push after every commit. `zig build test` must be green at the end of Part A and stay green.

## Part A: the corpus test discovers programs (bug 1)

No hard-coded program list or counts anywhere in `corpus.zig`: every `programs/<name>.mo` and `programs/<name>/main.mo` is a program; every `# run:` line is a run; process-test counts are computed. `kv` passes in the real `zig build test`.

## Part B: maps and process state (bugs 2, 3, 6)

`Map` and `Set` get a hash index beside the insertion-ordered entries (order semantics unchanged: `09-stdlib.md` rules hold). `Map.set`, `remove`, `Set.add` on a value held in process `state` (or any unique `var`) work in place; the old value is freed. A program that declares a process still frees: the region cleanup runs at safe points in `main` and in every `update`, and mailbox values are roots. Measure: 2,000 overwrites at 20k keys must stay under 50 MB; building 10k keys under 50 ms.

## Part C: a process keeps nothing per request (bug 4)

After each `update`, everything allocated during it that is not reachable from the new state, the outgoing messages, or a reply is freed. Measure with `kv serve`: 200k requests must stay under 100 MB resident. Record bytes per key at 100k keys, and the 1M-line replay time inside `kv serve`.

## Part D: files are written (gaps)

`09-stdlib.md` and the prelude gain `Fs.write(path, text, within:)`, `Fs.append(path, text, within:)` (durable: `fsync` before returning `Ok`), `Fs.remove(path, within:)`, `Fs.rename(from, to, within:)`; all refused at check time on a `read_only` scope (`MO0404`), all under fault injection in `Mo.Sim` with an in-memory file system that keeps what was written. `kv`'s log becomes real: changes survive a restart; the replay test in the spec passes. `Out.flush`, and `Out.fixture()` whose writes a test can read back with `out.fixture_text`? No new API shape: `Out.fixture()` returns an `Out` and a test reads `out.written` (a `List(String)`).

## Part E: three language decisions, implemented

Fable decided (grammar updated by Fable): a function may omit its return type when it returns nothing (`fn turn_away(conn: Conn)`), exactly like `main`; a negative integer literal is a pattern (`Ok(-5)`); `String.byte_size` is a row (`bytes.size` builds the whole list). Implement all three; the corpus gets one file for the first two.

## Part F: `mo fmt` and the diagnostics (bug 5 and the misleading four)

`mo fmt` must never crash: fix the anonymous-function-with-parenthesis case and add a fuzz test that formats every corpus file after each of ten random whitespace mutations. Reword: `MO0101` at a missing return type says "a function that returns a value names its type after `:`; one that returns nothing leaves it off"; `MO0102` for a bare `return` says "`return` takes a value; a function that returns nothing ends its body instead"; `MO0104` accepts negative literals now; `MO0403` for `Time.fixture` outside a test names `Time` not "a capability".

## Part G: numbers

`zig build bench` gains `kv-10k-get` (10k GETs over a real socket from one client) and `map-100k` (100k sets then 100k gets). Record all rows. Update `TOOLCHAIN-BUGS.md` with the fixing commit per bug and delete the settled `GAPS.md` lines.

## Done when

`zig build test` green with `kv` in the corpus from discovery, the memory numbers met, files written and replayed, the three decisions in, `mo fmt` fuzz-clean, bench rows recorded, pushed, decisions listed.

## Related
- [[program-3]]
- [[interpreter-step-11]]
- [[interpreter-step-13]]
- [[decision-log]]
