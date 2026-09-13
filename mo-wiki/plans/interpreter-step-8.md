---
title: "Step 8: the stdlib, brief for the worker"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [stdlib, runtime]
sources: [examples/GAPS.md, spec/design-v0/06-packages.md]
status: done
---

# Step 8: the stdlib, brief for the worker

Program 2 hit nine stdlib gaps and wrote insertion sort, digit tables, and fixed-point arithmetic by hand. Chapter 6 says the standard library is the big box, first-party, audited once. This step builds the part of the box the first three programs need, as built-ins in Zig with rows in `PRELUDE.md`, and writes `spec/design-v0/09-stdlib.md` as the table a reader checks against.

## Orientation

`examples/GAPS.md` (every line is a demand), `examples/programs/logstat/*.mo` (what the workarounds look like; each should become one call), `toolchain/PRELUDE.md`, `prelude.zig`, `vm.zig`, `spec/design-v0/03-semantics.md` (values, determinism: stable sort, defined map order).

## Write scope

`toolchain/`, `examples/`, and one new file `mo-wiki/spec/design-v0/09-stdlib.md` (the only wiki write a worker has ever had; nothing else in `mo-wiki/`). Branch `session-05`, one commit per part.

## The table (Part A writes `09-stdlib.md` first, then Parts B–F implement it)

- **Integers and floats:** `to_u8`…`to_u64`, `to_i64`, `to_f64` (named, checked: an out-of-range conversion is a crash, `checked_to_u32` returns `Option`); `Float64.round(places)`, `to_string(places)`; `String.to_u64 : Option(UInt64)`, `to_i64`, `to_f64`.
- **Strings:** `split(sep) : List(String)`, `lines`, `trim`, `starts_with?`, `ends_with?`, `contains?`, `index_of : Option(UInt64)`, `slice(from, to)` (grapheme indices, clamped), `replace(a, b)`, `to_upper`, `to_lower`, `pad_left(n, ch)`, `pad_right`, `repeat(n)`, `chars : List(String)`, `bytes`, `String.from_bytes : Option(String)` (invalid UTF-8 is `None`), `String.join(xs, sep)`.
- **Lists:** `get(i) : Option(T)`, `first`, `last`, `slice(from, to)`, `concat(other)`, `reverse`, `sort` (stable, by the element's natural order: integers, strings, tuples lexicographically), `sort_by(fn(x) key end)` (a key function, since function types cannot be named; the key is any orderable value), `any?`, `all?`, `find : Option(T)`, `count(fn)`, `sum` (integers), `min`, `max` (`Option`), `take(n)`, `drop(n)`, `zip`, `enumerate : List((UInt64, T))`, `flat_map`, `unique`, `group_by(fn(x) key end) : Map(K, List(T))`.
- **Maps and sets:** `Map(K, V)` and `Set(T)` as values with defined (insertion) order: `Map.new`, `get : Option(V)`, `set(k, v)` (returns the new map; in place on a unique `var`), `remove`, `has?`, `keys`, `values`, `entries`, `size`, `update(k, default, fn(v) ... end)`; `Set.new`, `add`, `remove`, `has?`, `to_list`. Literals: none in this step (record as a gap for Robert).
- **Time:** `Time.parse(iso8601) : Option(Time)`, `Time.from_parts(year, month, day, hour, minute, second)`, `to_iso8601`, `since(other) : Duration`, `Duration.minutes : Float64`, `ms`, `seconds`.
- **Fs:** `list(within:) : Result(List(String), FsError)` (names directly inside the scope, sorted), `read_lines(path, within:) : Result(List(String), FsError)`, `size(path, within:)`.
- **Out:** `write_line(s)`.
- **JSON:** `Json.encode(value)` for structs, enums, lists, maps, strings, numbers, bools; `Json.decode(text) : Result(Json, JsonError)` into a `Json` enum (`Object`, `Array`, `String`, `Number`, `Bool`, `Null`). Program 3 needs this; keep it small.

Every function is deterministic. Everything is a row in `09-stdlib.md` with its signature and one line; the corpus gets one file per group under `examples/stdlib/` with tests.

## Part G: `logstat` rewritten and a release `mo`

Also: make `zig build` install `mo` built ReleaseSafe by default (Mo's overflow checks are the VM's own; Zig's safety checks stay on), keep a `zig build -Ddebug` for a Debug binary, and record the `logstat` 200k-line wall time before and after (60 s in Debug today).

Replace each workaround in `examples/programs/logstat/` with the stdlib call; the program should lose about a third of its lines. Delete the settled lines from `GAPS.md`. `zig build test` green, corpus test green.

## Done when

`09-stdlib.md` written, every row implemented and tested, `logstat` rewritten and shorter, bench rows recorded, pushed. Then list every decision the brief did not cover.

## Related
- [[interpreter-step-7]]
- [[program-2]]
- [[d35-mo-is-an-ecosystem]]
