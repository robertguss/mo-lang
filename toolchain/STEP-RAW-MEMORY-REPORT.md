# Toolchain defect: raw memory in a large report — worker report

Brief: `mo-wiki/plans/toolchain-raw-memory-report.md`. Branch
`toolchain/raw-memory-report`, based on `31ad3ba9`. Worker: Claude Opus session,
19 Sep 2026. No subagents. Every mo, build and test process ran under
`toolchain/bench/step36/guard.py` with a timeout. I did not run the full
`zig build test`.

## Result

**Cause found and fixed in both runtimes.** An `answer` to an ask that a process
kept was held until the update committed as the bare `Value`. That value points
into the process's region. When the update's frame returned after allocating
more than `frame_budget` (1 MiB), the frame compacted its region, keeping only
its return value (state and reply). The held answer was not a root, so its
memory was freed and then overwritten before the commit packed it for the asker.
`send` never had this problem because it packs its message when `send` runs. The
fix packs an answer when `answer` runs, in the same way.

The size threshold follows from this. The Application's `Poll` arm had to
allocate more than 1 MiB before its returning frame compacted. In the agent the
report is built from a transcript that holds the model's text at least twice
(see the log line lengths below), so a 0.35 MB reply was enough in native and
about 0.8 MB in the interpreter. The two runtimes lay out the region
differently, which moves the point where the freed bytes get overwritten.

## Part 1: reproduction at `5caec127`

This is a scratch copy (`git archive 5caec127 examples toolchain`, outside the
worktree), with `matrix.py` and `fake_bridge.py` taken from `53bd184e`, since
`5caec127` has no `matrix.py`. `sizes_probe.py.txt` was run with its scratch-log
copy line removed, and `MO_BIN` pointed at this worktree's `mo`. The native
binary is `mo build examples/programs/agent/main.mo -o application-agent`. Each
tuple below is the probe's (exit, bridge requests, model requests, last stdout
line).

Before the fix (`mo` built from `31ad3ba9`):

| N       | native                                                                                             | interpreter                                                                             |
| ------- | -------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| 250,000 | `(3, 1, 1, '{"schema": "mo-application-workspace-v1", ... "event": "terminal", ... "over_budget"'` | the same, correct                                                                       |
| 350,000 | `(3, 1, 1, '\t\x00\x00\x00...\x0e\x00...')`: raw memory                                            | not run                                                                                 |
| 500,000 | raw memory, same bytes                                                                             | not run                                                                                 |
| 800,000 | not run                                                                                            | `(134, 1, 1, '')`, `panic: access of union field 'string' while field 'none' is active` |
| 851,700 | raw memory                                                                                         | exit 134, same panic                                                                    |

The ReleaseSafe panic location `vm.zig:1531` is wrong: inlining misplaced it. A
Debug build (`zig build -Ddebug -p <scratch>`) puts it in **main**, at
`vm.zig:1606`, in `stdlib.writeOut` of `a[1].string`. That is where main writes
the `Output.text` it received from `worker.ask(Launched...)`. So the asker
received a corrupt answer. The report itself had been rendered correctly.

After the fix (`mo` from this branch, binary rebuilt):

| N                                               | native                                                                                                                                                                 | interpreter            |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- |
| 250,000 / 350,000 / 500,000 / 800,000 / 851,700 | `(3, 1, 1, '{"schema": "mo-application-workspace-v1", "run_id": "r_1", "event": "terminal", "step_number": 2, "payload": {"state": "over_budget", ...')` at every size | the same at every size |

Exit 3 is the run's own `over_budget` code, which is also the correct 250,000
row before the fix. The probe prints only the last stdout line. I did not diff
the whole report between the two runtimes.

## Part 2: reduction

The reductions stayed in scratch while I worked. Here is what they showed, all
before the fix:

- A plain deferred `Reply(String)`, answered from a delayed self-send with
  `"y".repeat(n)`, **works** at 2,000,000. This matches the rebuild worker's
  isolated probes.
- The same shape answering a struct `Output(text, code)`, whose text is built in
  a helper (`[line, line].map(quoted)` joined, `replace`), **fails** from about
  n = 300,000. That is a 1.2 MB text. At 100,000 to 250,000 it works.
  Interpreter: the same panic, at `.string_byte_size` in main. Native:
  `got 0  Holder(waiting: [])`, meaning the asker read another value's bytes.
- The delay is **not needed**: a plain self-send fails too. A second process is
  **not needed**: building the text locally instead of asking a Store process
  fails too. The `for` loop over the kept replies is **not needed**: answering
  one `state.waiting.first` fails too.
- Answering **in the same arm that took the ask** (not deferred) **works**. That
  path returns the reply as the update's value, which the returning frame keeps
  as a root.

The minimal form is now the corpus program
`examples/programs/deferred-large.mo`, about 60 lines. It has one process that
keeps an ask, one self-send, and one arm that builds a two-line `Output` of n
doubled y's and answers the kept reply.

## Part 3: cause and fix, with source lines

Interpreter, before the fix:

- `toolchain/src/sim.zig` `answerReply` appended
  `.{ .seq = seq, .value = value }` to `p.answers`, with the raw value.
- At commit, `deliver` calls `routeAnswer(a.seq, a.value)`, which packs the
  value there (`sim.outgoing`). That is after the update's frame has returned.
- `toolchain/src/vm.zig:551` (`.ret`):
  `if (r.top -| frame > vm.frame_budget) try vm.compact(frame, vm.stack.items[base..])`.
  Its roots are only the returning frame's results. `p.answers` is not among
  them.
- By contrast, `Sim.send` and `Sim.sendLater` pack at the call
  (`sim.outgoing(message)`).

Native, before the fix, has the same shape:

- `toolchain/runtime/mo_rt.c` `mo_answer` stored `(PendingAnswer){seq, value}`.
- `deliver`'s commit called `route_answer(a.seq, true, a.value)`, which packs
  there.
- The frame compaction is `mo_rt.h:260`
  (`mo_heap.top - frame > MO_FRAME_BUDGET`, 1 MiB).
- `mo_send` (`mo_rt.c:5600`) packs at the call.

The fix is the same in both runtimes (+48 / −7 lines):

- `PendingAnswer` gains `parcel` (sim.zig:153, mo_rt.c:5097).
- `answerReply` (sim.zig:452) and `mo_answer` (mo_rt.c:5857) pack with
  `outgoing`/`pack(value)` when the run packs, and keep the parcel's value.
- A new `routePacked` (sim.zig:483) and `route_packed` (mo_rt.c:5829) route an
  already packed answer at commit. Its parcel is freed when nothing awaits it,
  and `Turns.answer` and `turns_answer` already free it when the asker has gone.
- The crash path frees any pending answer's parcels before clearing them.

Semantics do not change. Values are immutable, and an answer still commits with
its update and is dropped on a crash.

Two things I ruled out. The 256 KiB loop budget (`iterate`) is not the moving
compaction, because the loop-free variant fails too. Walks can also compact, but
the returning frame alone is enough.

One thing is unchanged. Without `packs` (a test under `mo test`, or a test
binary), answers, like sends, still hold raw values. In those modes the process
regions are not compacted mid-update (the interpreter has no per-process region
when `packs` is false; in C, `packs = turns_on && mo_compacts`). I did not find
a failing case there, and I did not change it.

## Part 4: tests

**The corpus program** is `examples/programs/deferred-large.mo`, with
`# run: 1000` and `# run: 400000`, and the files `deferred-large.expected`
(`answered 4005 bytes and code 3, whole: true`) and `deferred-large-2.expected`
(`answered 1600005 bytes and code 3, whole: true`). The full corpus test picks
it up under `mo run` and as a `mo build` binary. `mo fmt --check` exits 0. Its
`verified:` line and `.mo.ids` record come from `mo test --write`:
`0 passed, 0 failed, 0 skipped`, exit 0. The `.mo.ids` diff only adds lines.

Before the fix, run 2 panics under `mo run` (exit 134, the same union-field
panic). As a binary it prints
`answered 0 bytes and code Holder(waiting: []), whole: false` with exit 0. After
the fix, both runtimes print the expected lines.

**The focused test** is in `toolchain/src/corpus.zig`:
`corpus: an answer of megabytes an arm made to an ask it kept arrives whole, under mo run, in a binary, and in one compacting at every safe point`.
It does three things:

1. `checkProgram`, the program's expected files under `mo run`.
2. `checkBuiltProgram`, the binary beside `mo run`, which must give 2 same and 0
   wrong.
3. **The native class check.** It `mo build`s a copy of the program, recompiles
   the emitted C with `zig cc ... -DMO_STRESS`, and runs it at n = 10 and n
   = 1000. `MO_STRESS` sets `MO_FRAME_BUDGET` to 0 (`mo_rt.h:243`), so a binary
   built this way compacts at every safe point and exposes any held region
   value, whatever its size. Before the fix, the stressed binary corrupts even
   the 45-byte answer
   (`answered 0 bytes and code Holder(waiting: []), whole: false`). After the
   fix it prints `whole: true`. This costs one extra `zig cc`, a few seconds. It
   uses `zig` from PATH through `/bin/sh` and globs the cached brick objects
   (`zig-out/mo-build/.bricks/*/*.o`).

Runs of `zig build test -Dtest-filter="an answer of megabytes" --summary all`:

- With the fix: `Build Summary: 5/5 steps succeeded; 2/2 tests passed`, and
  `run test 2 pass (2 total)`, exit 0.
- `sim.zig` and `mo_rt.c` restored from HEAD:
  `Build Summary: 3/5 steps succeeded (1 failed); 1/2 tests passed (1 failed)`,
  exit 1. It fails at `checkProgram`, where the interpreter panics.
- Only `mo_rt.c` restored from HEAD: again
  `3/5 steps succeeded (1 failed); 1/2 tests passed (1 failed)`, exit 1. Here
  `corpus: programs/deferred-large.mo run 2 differs from the interpreter`, and
  the C side printed
  `answered 0 bytes and code Holder(waiting: []), whole: false`.
- Both files were then restored to the fix (the diff is +48 / −7 again), `mo`
  rebuilt, and the test rerun green, as in the first bullet.

I did not add an interpreter class check. The interpreter's `frame_budget`,
`loop_budget` and `walk_budget` can be set to 0 only from Zig unit tests
(`vm.zig:2337`), not under `mo run`. A sim-level unit test with budget 0 around
a deferred answer would be the interpreter's equivalent. Wiring it through
`server.zig`'s machine looked larger than this step warranted.

Other focused checks:

- `zig build test -Dtest-filter="answers the ask it keeps"`:
  `Build Summary: 5/5 steps succeeded; 2/2 tests passed`, exit 0.
- `examples/processes/deferred-reply.mo`, `deadline.mo` and `timer.mo`:
  `mo test` passes with exit 0, and `mo test --sim 100` gives
  `... 100 simulated runs` with exit 0.
- `deferred-reply.mo` built with `--tests` exits 0. `mo run` and the built
  binary both print `answered 8` / `written 8`, exit 0.
- `zig build` exits 0.

## Not done / for the lead

- The agent's 256 KiB `report_cap` is still in place. It is the lead's decision
  to lift it. At uncapped `5caec127` the fixed toolchain renders all five sizes
  correctly in both runtimes.
- The README's "The runtime surface / processes" paragraph does not describe
  when an answer is packed. `toolchain/README.md` is outside my write scope as I
  read it (`toolchain/src/**` and the runtime sources), so I left it alone.
- The full `zig build test`, including the whole corpus with the new program, is
  the lead's to run.
