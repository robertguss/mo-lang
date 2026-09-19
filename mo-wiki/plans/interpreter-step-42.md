---
title: "Step 42: runtime memory safety, a stale region value fails loudly"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [runtime, verification, tooling, processes]
sources: [plans/toolchain-raw-memory-report.md, plans/interpreter-step-41.md]
status: in-progress
---

# Step 42: runtime memory safety

## Orientation

On 19 Sep 2026 both runtimes handed an asker freed memory: an `answer` to a
kept ask held a bare region value across a frame return, the frame compacted,
and the value was overwritten (`toolchain/STEP-RAW-MEMORY-REPORT.md`; read it
first). Robert asked how the whole class is prevented, not the one case. This
step makes the class fail loudly in the suite, then audits for its other
members. Two terms, used below. A **region value** is a `Value` pointing into a
process's region, valid only until the next compaction. A **parcel** is a
packed, owned copy that outlives compaction (what `send` makes). Worker: a
fresh clean OMP session using GPT Sol at high reasoning, own worktree and
Herdr tab. The lead owns the wiki, audit and acceptance.
No new syntax; no change to Mo's semantics.

**Resumption authorized, 19 Sep, evening:** continue from `0a4dffcd` on
`toolchain/step-42-memory` (original base `2f669902`). Read `WIP.md` and branch
history, preserve the Opus worker's part E RED/GREEN evidence, then finish A–D
and verify E's remaining limits. Do not treat the WIP's implementation ideas
as accepted designs. Benchmarks and full-suite timing need lead scheduling;
focused builds/tests remain in this worktree, never the server worker's.

## Write scope

`toolchain/src/**`, `toolchain/runtime/**`, `toolchain/build.zig`,
`toolchain/bench/step36/guard.py`, `toolchain/bench/step42/**`,
`toolchain/STEP-42-REPORT.md`, `toolchain/WIP.md`, `toolchain/README.md` (the runtime
paragraphs only), `toolchain/PRELUDE.md` if the prelude changes, new corpus files
under `examples/` with sidecars and `verified:` lines (real tools only).
No `examples/programs/workspace-server/**`, no harness code, no wiki, no `audit/`, no
`HANDOFF.md`. No machine, Docker, `/opt`. No push. Never use `tr`; `ls` is
aliased, use `/bin/ls`. The Linux VM is the lead's; you run on this Mac only.
You are not alone on this host: preserve others' edits, no nested delegation.

## Parts

### A. Stress mode for the whole corpus, both runtimes (RED first)

Today `-DMO_STRESS` (`mo_rt.h:240`, budgets 0) is used by one test, and the
interpreter's `frame_budget`, `loop_budget`, `walk_budget` (`vm.zig:167`) are
settable only from Zig unit tests (`vm.zig:2337`). Give both a supported
switch (an environment variable such as `MO_STRESS=1` read by `mo run`, `mo
test` and by built binaries, or a build flag for C if a runtime read costs the
hot path: measure, then choose, and say which). Then a standing test runs every
corpus program that has expected output under stress in both runtimes and
demands the same output as the normal run. Commit its first output before any
fix: whatever it finds is this step's RED. Keep its wall time in the report; if
it more than doubles the suite, propose a sampled default with the full sweep
behind a flag, do not silently sample.

### B. Poison what compaction frees

In stress mode, fill every byte a compaction releases with a fixed pattern
(say `0xA5`) in both runtimes, so a stale read yields a recognisable wrong
value or a trap instead of plausible old bytes. For the C runtime add an
ASan build of the stress sweep with manual region poisoning
(`ASAN_POISON_MEMORY_REGION` on release, unpoison on reuse); it may be a
separate, slower test step. Prove each with a mutant: reintroduce the raw
`PendingAnswer` value behind a test-only switch or a patch in the report, and
show stress plus poison catches it at the 45-byte size.

### C. The audit

List everything either runtime holds outside the stack across a frame return
or a safe point, with file and line, and for each say region value or parcel
and why it is safe: pending answers (fixed), timers and `send_later`, mailboxes,
kept replies, the runtime surface's snapshots, bricks' buffers, the blocking
pool's requests and results (step 41's `Exec` included), supervisors' restart
state, the simulator's queues, and the no-`packs` modes the raw-memory report
left unchanged; and `blocking.run` (step 30's pool), which steps 40 and 41 both
reported still returns if `block` errors while its job is on the pool, leaving
the job with a dead stack (`blocking.alone` has the guard). Fix what is unsafe, each with a failing test first. The list
goes in the report as a table.

### D. The type split

In Zig, make a long-lived struct unable to hold a region value by accident: a
distinct `Parcel` (owned) type already exists in effect; give the fields found
in C a type that only `pack` produces, so storing a bare `Value` there is a
compile error. In C, the same by a distinct struct type and a comment at each
holder. State plainly in the report what the types do not prevent.

### E. The guard kills the group

`toolchain/bench/step36/guard.py` kills only its direct child (`p.kill()`), and
an orphaned test binary later deleted the shared `zig-out`. Start the child in
its own session or process group and kill the group on timeout, on the memory
limit, and on a forwarded TERM or INT; the exit status and messages stay as
they are. Test it with a child that spawns a grandchild that ignores TERM.

## Numbers

Best of five, both runtimes, load average beside them: the suite's wall time
before and after; the stress sweep's wall time; three corpus benchmarks of
your choice in normal mode before and after, to show the switch costs nothing
when off.

## Done when

Every process under `guard.py`; after any kill, check for orphaned test
binaries (`ps` for `.zig-cache/o/*/test`). `zig build` exit 0; focused tests
by `-Dtest-filter` with real summary lines and exit codes; **the unfiltered
full suite is the lead's** (Linux is deferred). Tee every run your report quotes
into a filed log with an exit file beside it, under `toolchain/bench/step42/`. RED output committed before GREEN.
Small commits as yourself with a `Co-Authored-By` line naming your model. Not
in scope: compaction points as a dimension the simulator varies by seed (say
in the report what it would take). **Write your final report to
`toolchain/STEP-42-REPORT.md` and commit it.** While anything runs, wait in the
foreground so your tab does not look finished.

## Related

- [[toolchain-raw-memory-report]]
- [[interpreter-step-41]]
- [[mo-harness-in-mo]]
