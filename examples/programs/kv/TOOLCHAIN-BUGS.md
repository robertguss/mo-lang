# Toolchain bugs found while writing kv

Recorded while writing program 3 (`mo-wiki/spec/programs/03-kv-store.md`, brief `mo-wiki/plans/program-3.md`), whose write scope was `examples/`. None is fixed here. Each has a minimal reproduction, what it cost kv, and the workaround kv uses. Timings are `toolchain/zig-out/bin/mo` (ReleaseSafe, built from `12b7a88`) on an Apple M-series machine with 14 cores and 96 GiB, every probe under a 4 GiB resident-memory cap.

## 1. The corpus test names every program and counts every process test, so a new program fails it

`toolchain/src/corpus.zig`, the corpus test, holds the list of programs and the tallies of the corpus as it was at step 11:

```zig
const want = [_][]const u8{ "count-lines", "echo", "exit-code", "hello", "lines-per-file", "logstat" };
try std.testing.expectEqual(want.len, programs.items.len);
...
try std.testing.expectEqual(@as(u32, 10), tally.process_files);
try std.testing.expectEqual(@as(u32, 11), tally.held_under_faults);
```

Any program added to `examples/programs/`, and any file whose tests start a process, fails `zig build test` on these lines, whatever the program does. kv adds a program and three files with process tests.

Workaround: kv is in `examples/programs/kv/` as the brief asks. It was verified by a scratch copy of the toolchain, never committed, whose only change is these numbers and the name `kv` in the list (see the foot of this file for the run).

## 2. `Map` is a list searched from the front: `get`, `has?`, `set`, and `remove` take time in the number of keys

`toolchain/src/stdlib.zig`: `Map.get` is `indexOf(a[0].map, 2, a[1])`, a scan comparing every key in order, and `set` scans before it appends. A map of n keys costs O(n) a lookup, and building one costs O(n²).

```
module Probe.MapGet

intent "probe"

fn filled(n: UInt64) : Map(String, String)
  var m = Map.new()
  for i in 0..n
    m = m.set("key#{i}", "v")
  end
  m
end

fn main(platform: Platform)
  n = (platform.args.first or "1000").to_u64 or 1000
  m = filled(n)
  platform.stdout.write_line("#{m.size}")
end
```

Building 1_000 keys takes 18 ms, 10_000 take 3.1 s, and 100_000 did not finish in 200 s. With the map built, 10_000 `has?` calls take 19 ms at 1_000 keys and 168 ms at 10_000 (1.9 µs and 16.8 µs each).

## 3. `set` on an existing key of a map held in process state copies the whole map, and the copy is never freed

A `set` writes in place only on a `var` that owns its buffer (`stdlib.zig`, `put`; `vm.zig`, `owned`), and ownership is lost the moment anything reads the var. A state field is not a var, and `var m = state.m` reads it, so every `set` of a key the map already holds duplicates the whole map in the process's region. A process's region is not compacted between messages (bug 4), so each copy stays.

```
module Probe.MapRw
expose Store, Stores

intent "probe"

process Store()
  state
    data: Map(String, String)
  end

  message Put(key: String, value: String) : Bool

  fn update(state, message)
    case message
      Put(key: key, value: value):
        state.data = state.data.set(key, value)
        true
    end
  end
end

supervisor Stores
  child Store, restart: :always
end

fn fill(store: Handle(Store), n: UInt64) : UInt64
  var ok = 0
  for i in 0..n
    if store.ask(Put(key: "key#{i}", value: "v"), within: 600_000.ms) is Ok(true)
      ok += 1
    end
  end
  ok
end

fn main(platform: Platform)
  store = Store.start()
  filled = fill(store, 20_000)
  again = fill(store, 2_000)
  platform.stdout.write_line("#{filled} #{again}")
end
```

Filling 20_000 new keys takes 800 ms; setting 2_000 of them again takes 1_208 ms and the run peaks at 3.6 GiB resident. With 100_000 keys the run passed 4 GiB and was killed. A key-value store at 100_000 keys would grow by about 6.4 MiB on every overwrite.

Workaround: kv's table (`Kv.Log.Table`) is a map of 256 small maps, so an overwrite copies the outer map of 256 entries and one inner map of about n / 256 keys, about 41 KiB at 100_000 keys instead of 6.4 MiB. The table is still leaked on every change, only in smaller pieces.

## 4. A process under `mo run` keeps what every message cost it

A frame, a `for` iteration, and a step of `map`, `filter`, or `reduce` free what they allocated and did not keep (step 7). An `update` that returns does not: its region grows with every message a process takes, even one whose update allocates nothing it keeps.

```
module Probe.GarbageConst
expose Store, Stores

intent "probe"

process Store()
  state
    asked: UInt64
  end

  message Fetch(key: String) : String

  fn update(state, message)
    case message
      Fetch(key):
        state.asked += 1
        key
    end
  end
end

supervisor Stores
  child Store, restart: :always
end

fn fetch(store: Handle(Store), n: UInt64) : UInt64
  var ok = 0
  for i in 0..n
    if store.ask(Fetch(key: "key#{i % 1_000}"), within: 600_000.ms) is Ok(_)
      ok += 1
    end
  end
  ok
end

fn main(platform: Platform)
  platform.stdout.write_line("#{fetch(Store.start(), 100_000)}")
end
```

100_000 asks peak at 117 MiB resident (about 1.1 KiB a message). The same loop calling a pure function instead of asking a process peaks at 7 MiB. When the update also builds a 320-byte string, 100_000 asks peak at 239 MiB.

What it costs kv: the store and the journal are processes that take one message per request, so `kv serve` grows by at least a kilobyte a request for as long as it runs, and more for every byte list its contracts build (`value?` counts a value's bytes as a `List(UInt8)`, 32 bytes a byte, three times on each SET: in the parser, in `put`'s `requires`, and in the journal's byte count). The worker processes do not leak: each serves its connection in one long `update` whose `for` iterations free as they go. No workaround in the program; the measurements say how far a run got.

## 5. `mo fmt` crashes on an anonymous function whose body starts with a parenthesis

```
module P.Fmt

intent "probe"

fn hashed(n: UInt64) : UInt64
  [n].reduce(0, fn(acc, x) (acc + x) % 7 end)
end
```

`mo check` accepts the file. `mo fmt --check` panics:

```
thread 7463229 panic: fmt: expected kw_end at byte 97, found percent
toolchain/src/fmt.zig:453:28: in tk (mo)
```

With a call inside the parentheses (`fn(hash, b) (hash * 31 + b.to_u64) % 256 end`, kv's first `bucket_of`) the panic is `expected dot at byte 109, found ident`. `fn(acc, x) acc + (x % 7) end` formats. The formatter's one-line attempt (`anonFn`, `flatBody`) reads the group as the start of a call or field chain.

Workaround: `Kv.Log.bucket_of` calls a named function, `mixed`, whose body is the parenthesised expression.
