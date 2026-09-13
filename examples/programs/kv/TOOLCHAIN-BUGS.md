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

A process that serves a connection in one long `update` keeps what its `for` iterations allocated as well, so it is not only the messages: kv's worker, whose loop never returns to its mailbox, keeps about 3.8 KiB of every line it answers.

What it costs kv, measured on a running `kv serve` with 20_000 requests of one kind on one connection (resident memory before and after, divided by 20_000):

| request | kept a request | who handles it |
|---|---|---|
| `nonsense` | 3.8 KiB | the worker alone (ERR malformed) |
| `STATS` | 10.9 KiB | the worker and the store |
| `GET nokey` | 15.7 KiB | the worker and the store |
| `GET one` | 14.9 KiB | the worker and the store |
| `SET one 0123456789`, the same key each time | 26.7 KiB | the worker, the store, and the journal |

So `kv serve` grows by 4 to 27 KiB a request for as long as it runs: 10_000 SETs of new keys take it from 7 MiB to 616 MiB, and it passes 4 GiB after about 200_000 requests. Every byte list the contracts build is part of it (`value?` counts a value's bytes as a `List(UInt8)`, 32 bytes a byte, on each SET in the parser, in `put`'s `requires`, and again in the journal's byte count). No workaround in the program: a store that must not leak cannot be written in Mo processes today. The measurements in the final report say how far each run got.

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

## 6. A program that declares a process frees nothing, not even in `main`'s loops

Probably the cause of bug 4. The same pure loop, in a file with a process declared and never started, keeps everything it allocates:

```
module Probe.KvProcess
expose Idle, Idles

intent "probe"

process Idle()
  state
    n: UInt64
  end

  message Poke

  fn update(state, message)
    case message
      Poke:
        state.n += 1
    end
  end
end

supervisor Idles
  child Idle, restart: :always
end

struct Table
  buckets: Map(UInt64, Map(String, String))
  size: UInt64
end

fn mixed(hash: UInt64, b: UInt8) : UInt64
  (hash * 31 + b.to_u64) % 256
end

fn put(table: Table, key: String, value: String) : Table
  at = key.bytes.reduce(0, fn(hash, b) mixed(hash, b) end)
  bucket = table.buckets.get(at) or Map.new()
  Table(buckets: table.buckets.set(at, bucket.set(key, value)), size: table.size + 1)
end

fn filled(n: UInt64) : Table
  var table = Table(buckets: Map.new(), size: 0)
  for i in 0..n
    table = put(table, "key#{i}", "#{i}")
  end
  table
end

fn main(platform: Platform)
  platform.stdout.write_line("#{filled(20_000).size}")
end
```

With the process and supervisor: 608 MiB resident, 0.31 s. Without them, the same file: 9.9 MiB, 0.60 s. Splitting the table into its own module, adding a `never`, or adding contracts changes neither number; only the declared process does. Twice as fast and sixty times the memory reads as the vm's region never being compacted.

What it costs kv: every module of kv is loaded with `Kv.Log`, which declares the journal, so `kv serve`'s replay keeps about 70 KiB a log line before it listens. A log of 10_000 lines replays in 0.27 s to 453 MiB, 25_000 in 0.71 s to 1.33 GiB, 50_000 in 1.64 s to 3.33 GiB, and 100_000 lines over 1_000 keys in 2.07 s to 3.57 GiB; a 1_000_000-line log passed 4 GiB after 2.4 s and was killed, so the spec's replay of a million lines cannot be run in kv today. No workaround in the program: kv needs its processes.

## How kv was verified against bug 1

A scratch copy of `toolchain/` at `12b7a88`, never committed, with `examples/` and `mo-wiki/` linked beside it, and three changes to `src/corpus.zig`: `"kv"` in the program list, `13` process files (the ten before, and `kv/log.mo`, `kv/store.mo`, `kv/server.mo`), and `20` tests held under faults (the eleven before, and kv's one journal test, three store tests, and five server tests). `zig build test` on that copy: 121 of 121 tests passed, the corpus test among them, so every kv file passes every stage, holds under `--sim 100` with faults, is formatted, and every `# run:` line of `kv/main.mo` matches its expected file and exit code through `mo run`. As a control, the same copy with the process-file count put back to `10` fails with `expected 10, found 13`.

## Step 12 measurements

Taken on the same machine as above, every probe under a 4 GiB resident-memory cap, `mo` ReleaseSafe.

After part C (the runtime frees under processes, and a process keeps nothing of an update past what its new state reaches), with kv as it was, whose journal still keeps every line appended in memory:

| run | result |
|---|---|
| `kv serve`, 200,000 requests over 8 connections, half SET and half GET over 1,000 keys | 86.9 MiB resident at the end (16.9 MiB before), 22,515 requests a second |
| `kv serve`, 200,000 GETs of one key on one connection, then 200,000 malformed lines | 14.0 MiB, then 15.3 MiB: flat |
| `kv serve`, 100,000 SETs of distinct keys | 129.5 MiB from 8.8 MiB: 1.24 KiB a key, the journal's copy of every line included |
| `kv serve` replaying a log of 1,000,000 SET lines over 100,000 keys (27 MiB) | listening after 22.3 s, 127 MiB resident |

What the replay first cost, and what took it down: 104 s with the index built again on every copy of a bucket; the same after the index copied a table that held exactly its keys; 39 s once a copy stopped filling each buffer with 0xAA before writing it (a safe build's `Allocator.alloc` does); 22.3 s once a compaction copied a clean index instead of hashing every key again.
