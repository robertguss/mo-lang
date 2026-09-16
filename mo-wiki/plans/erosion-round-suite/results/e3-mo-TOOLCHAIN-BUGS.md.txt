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

## 2. Resident memory grows with the requests served, far past what every process's region holds

A long-running server's resident memory grows with the work it has done, several times faster than the bytes its processes' regions hold, and the runtime surface's `MemoryInfo` accounts for none of the difference. Found while measuring jobq's resident memory at 100,000 jobs, as the spec asks.

Reproduction: `mo build --surface main.mo -o jobq-surface` in `examples/programs/jobq`, `MO_SURFACE=7952 jobq-surface serve <empty folder> --port 7951`, then 32 clients creating jobs over HTTP (a new connection per request; the load generator is Go's `net/http`), and `GET /memory` and `GET /processes` on port 7952 between phases:

| after | resident (`/proc` VmRSS and `/memory` resident_bytes) | `/memory` region_bytes, all processes | the Queue's region | Worker processes alive |
|---|---|---|---|---|
| start | under 1 MiB | under 1 MiB | under 1 MiB | 0 |
| 20,000 jobs | 82 MiB | 12 MiB | 12,479 KiB | 13 |
| 40,000 jobs | 120 MiB | 12 MiB | 11,653 KiB | 18 |
| 5 s more of lease-and-ack pairs, no new jobs (6,565 pairs, 13,130 requests) | 131 MiB | 24 MiB | 22,946 KiB | 0 |

Every job lives in the Queue's region (its board: the jobs, each queue's order, the leases), so the program's own data is 12 to 23 MiB at 40,000 jobs, and resident memory is five to ten times that and still climbing: about 1.9 KiB per request made while creating jobs, and about 0.8 KiB per request with no new job at all. A worker process per exchange ends once it has answered (none are left after the pairs), so the growth is not live processes. The same shape without the surface, 100,000 jobs: 299 MiB resident as a binary.

Not worked around: nothing in the program can reach memory outside its regions. jobq's own part was cut as far as it goes (bug 1's pages, and the store keeping no second copy of a job, 391 MiB to 299 MiB at 100,000 jobs), and the rest is reported as found.

## 3. A `reduce` whose accumulator is a tuple copies what the tuple holds on every step

`xs.reduce((value, list), fn(acc, x) (changed(acc.0, x), acc.1.push(x)) end)` copies `value` whole at every step, so a reduce over a batch of changes to a large table is quadratic, where the same reduce with `value` alone as its accumulator runs in place.

Reproduction: a process whose state holds a struct with a `Map(UInt64, UInt64)` of 50,000 entries, updated 2,000 times, eight new keys an update, as a binary:

| the update | 2,000 updates |
|---|---|
| `state.board = put(state.board, i)`, eight times through a function | 2 ms |
| `[0, 1, 2, 3, 4, 5, 6, 7].reduce(board, fn(b, k) put(b, i * 8 + k) end)` | 19 ms |
| `[0, 1, 2, 3, 4, 5, 6, 7].reduce((board, [0].take(0)), fn(acc, k) (put(acc.0, i * 8 + k), acc.1.push(k)) end).0` | 1,214 ms |

(`put` is `var next = board; next.jobs = next.jobs.set(i, i); next`.) Handing the board through a struct field (`Holder(board: state.board)`, `Dec(board: put(board, i), n: i)`) stays at 2 ms.

Found by the load run: `Jobq.Store.put_all` applied a batch of records with a `(Table, List(String))` accumulator, and jobq made about 690 jobs a second with every flush copying the table. Workaround: the lines to write are gathered by a reduce over small values only, and the table is changed by a second reduce whose accumulator is the table alone.

## Not a bug: the fixture clock is frozen

A test's `Clock.fixture()` does not move while a fixture call waits, so a lease never runs out on a running queue in a test. Grammar §8 says the fixture clock is frozen, so it is recorded in `GAPS.md` as a gap. The reproduction: `clock = Clock.fixture()`, `before = clock.now`, `Fs.fixture(delay: 200.ms).list(within: 1.minute)`, an `ask` of a process, then `clock.now - before` is `0.ms`, under `mo test` and `mo test --sim 5`.

## 4. An or-pattern too long for the column limit has nowhere to go

A `case` arm that names the rest of a wide enum is one or-pattern on one line: `|` at the start of
a continuation line is `MO0104 expected a pattern`, and a `_` arm in its place is `MO0309`, since no
catch-all is allowed on a closed enum. So an arm over the other nine variants of `Jobq.Board.Outcome`
is 101 characters at indent 4 and there is no way to write it that the formatter's 100-column limit
(FORMAT.md, L4) accepts.

Reproduction: add a tenth variant to `Outcome` and run `mo test` on `queue.mo`. Three of the five
arms that listed the rest of the enum went over the limit, and each had to be written another way:
`case x ... Found(_): false | rest: true` became `!(x is Found(_))`, and two others became
`if x is Found(held) ... end` with the rest of the enum falling through to the value below.

Not worked around in the toolchain: the shapes above are fine to read, and the finding is that a
wide enum's `case` arms are a cost the language charges again every time a variant is added.

## 5. A crash keeps its rendered state for good, so every restart of a large process costs its size

Change 3 restarts the queue after a failure. Each crash renders the crashed process's state, its
state before the last message, and its message log as text (`crashed` in `toolchain/runtime/mo_rt.c`;
the invariant's clause renders the state a third time), writes the report to stderr, and never frees
it: the report is not in the 16 the surface keeps, and `MO_EVENTS=64` changes nothing. The queue's
state is the whole board, so the cost is proportional to the jobs.

Measured with the built binary on this Mac, `--crash-every 1` and one create per restart:

| log | report on stderr per crash | RSS after the 1st restart | growth per restart |
|---|---|---|---|
| 5,000 jobs | about 5.5 MB | 42 MB | about 11 MB for the first 60, about 5 MB after |
| 20,000 jobs | about 22 MB | 117 MB | about 44 MB |

Reproduction: `python3` a log of 20,000 jobs into a folder, `jobq serve <dir> --crash-every 1
--max-restarts 1000`, then POST a job and GET /health 30 times; RSS goes from 117 MB to 1,380 MB and
stderr to 685 MB. Not worked around: the report is the runtime's, the restart itself is 0.15 s on
that log, and the restart budget (5 in 60 seconds by default) bounds how fast it grows.
