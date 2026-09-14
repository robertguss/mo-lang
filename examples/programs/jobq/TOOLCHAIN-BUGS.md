# jobq: toolchain bugs

What writing `jobq` (program 1, round 7 of the control run) found in the toolchain. Nothing in `toolchain/` was changed; each bug has a reproduction and the workaround the program uses.

## 1. Changing a map's existing entry, or removing one, copies the whole map

`Map.set` on a key the map already holds, and `Map.remove`, take time in proportion to the map's size, even on a `var` nothing else holds, so a loop of them over a large map is quadratic. Inside a process's `update` they cost ten to twenty times more again. `Map.set` of a new key stays constant. Step 21 set out to make map `put` and `delete` run in place where the value is uniquely held; the new-key case does, the others do not.

The reproduction, built with `mo build` and run on the exe.dev VM (4 cores), times 2,000 calls after the map was filled with `n` entries in an earlier update:

```
struct Rec
  name: String
  payload: String
  at: UInt64
end

struct Maps
  a: Map(UInt64, Rec)
  b: Map(UInt64, UInt64)
end

fn stepped(maps: Maps, kind: String, i: UInt64, n: UInt64) : Maps
  var m = maps
  case kind
    "set_new": m.b = m.b.set(n + i, i)
    "overwrite": m.a = m.a.set(i, Rec(name: "q", payload: "again", at: i))
    "remove": m.b = m.b.remove(i)
    _: m.b = m.b.set(n + i, i)
  end
  m
end

process Keeper(n: UInt64)
  state
    maps: Maps = Maps(a: Map.new(), b: Map.new())
  end

  message Grow : UInt64
  message Step(kind: String, i: UInt64) : UInt64

  fn update(state, message)
    case message
      Grow:
        state.maps = grown(state.maps, n)
        state.maps.a.size
      Step(kind: kind, i: i):
        state.maps = stepped(state.maps, kind, i, n)
        state.maps.b.size
    end
  end
end
```

(`grown` fills both maps with `n` entries in a `for`; `main` asks `Grow` once, then `Step` 2,000 times and prints the milliseconds.)

| 2,000 calls | n = 10,000 | n = 80,000 |
|---|---|---|
| `set` of a new key, in an update | 2 ms | 3 ms |
| `set` of an existing key, in an update | 682 ms | 22,715 ms |
| `remove`, in an update | 703 ms | 21,739 ms |
| `remove` of a tuple key, in an update | 951 ms | 25,111 ms |
| `set` of a new key in an update that also builds a few lists (`[1, 2, 3].concat([4]).push(5)...`) | 106 ms | 3,889 ms |
| `set` of an existing key, a `var` in `main` | 127 ms | 1,176 ms |
| `remove`, a `var` in `main` | 257 ms | 2,674 ms |

The last case of the update rows suggests a second shape of the same bug: a new-key `set` copies too once the update has grown enough other buffers in between (the runtime's `push_list` keeps growth records for the last 16 buffers only, `runtime/mo_rt.c`).

Found by the load run: with 32 clients, jobq made jobs at 2,400 a second at first and 520 a second by 47,000 jobs, since every create, lease, ack, and fail set an existing entry of the map of every job (and, before that, of the store's map of every record). Workaround: every map that grows with the jobs is kept in pages of 256, a `Map` of small maps (`Jobq.Board`'s jobs, leases, and fresh positions; `Jobq.Store`'s records over 256 buckets, as notes did before step 21), so a change copies one page of at most 256 entries and sets one entry in a map of at most one page per 256 jobs.

## Not a bug: the fixture clock is frozen

A test's `Clock.fixture()` does not move while a fixture call waits, so a lease never runs out on a running queue in a test. Grammar §8 says the fixture clock is frozen, so it is recorded in `GAPS.md` as a gap. The reproduction: `clock = Clock.fixture()`, `before = clock.now`, `Fs.fixture(delay: 200.ms).list(within: 1.minute)`, an `ask` of a process, then `clock.now - before` is `0.ms`, under `mo test` and `mo test --sim 5`.
