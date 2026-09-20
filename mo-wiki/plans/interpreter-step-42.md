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

Worker stress sweeps and benchmark measurements require an explicit exclusive
lead-issued slot after sibling builds/runtime checks drain. The unfiltered
suite and its best-of-five timing remain lead-owned; the worker's slot does
not authorize them or replace independent integrated acceptance. Record
exact before/after commits and commands, all five samples (not only the best),
load averages, guards, real exits and any failed or invalid samples. Do not
change implementation during a measured series; corrections require a new
checkpoint and a clearly separated series. No Linux or machine runs in the
Darwin slot. Siblings resume checks only after explicit lead release.

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

## Lead review of `be64e8a5` (19 Sep, evening)

Not accepted. Preserve all worker RED/GREEN evidence and the final report;
these findings require a fresh corrective session, not a resumed conversation.

1. **Completion is not last access.** In `blocking.zig:118-121,246-250`,
   `done.store(true)` precedes reading `job.write_fd` and signaling it. The
   caller may observe done, close the fd and unwind its stack first. Fix the
   ownership/notification handoff in both pool and standalone paths, including
   scheduler-wait errors; copying the descriptor alone does not prevent close
   and fd reuse. The helper-only 20ms test does not exercise `run` or this race:
   replace it with a deterministic production-path control and mutation that
   fails when early completion/early error return is restored.
2. **ASan must know the fiber stacks.** `mo_rt.c:7378,7508` switches custom
   stacks with no sanitizer start/finish notifications. LLVM's public
   [fiber interface](https://github.com/llvm/llvm-project/blob/main/compiler-rt/include/sanitizer/common_interface_defs.h)
   requires them. Implement correct ASan-only first-entry, switch, resume,
   reuse/destruction and scheduler-stack bookkeeping. Remove the warning
   stripping in `e537abfe` and its normalization-only test. Preserve raw
   diagnostics; expected-crash corpus cases must compare without suppression,
   and the 45-byte stale-answer mutant must still produce a real ASan error.
   Do not globally disable ASan checks or fake-stack protection.
3. **Finish Part D, not just pending answers.** Zig `Entry`, `Outgoing`,
   `Later`, `Answered` and corresponding native/scheduler/log holders still
   pair raw values with independent parcel pointers. Carry the distinct owned
   representation across every retaining boundary identified by the audit;
   migrate all callers. Explicitly distinguish no-packs/test-only values and
   traced process-state roots instead of wrapping roots as owned parcels.
   Compile-failing bare-value mutations must cover more than pending answers;
   runtime controls must cover transfer, drop, timeout, crash and cleanup.
4. **Do not erase an effect to avoid retaining its value.** The new
   `if (sim.packs) return` in `Sim.emit` drops interpreter server events; native
   behavior alone is not permission to remove existing interpreter behavior.
   Preserve emitted values safely through the existing event lifecycle,
   without inventing a new external sink. Replace the test that merely
   asserts the list is empty with retention/compaction and simulator controls.
5. **Keep ASan opt-in.** The existing large-answer regression now unconditionally
   builds through Clang/ASan. Restore ordinary-runtime coverage there and select
   sanitizer builds explicitly; document the host Clang requirement for that
   mode. Retain both ordinary and sanitizer mutant proofs. Do not silently
   sample or omit the exhaustive stress sweep.
6. **Finish honest measurements.** Echo minima rose 12.90%/8.60%, with substantial
   variance and changing load; this establishes neither a zero-cost switch nor
   a reliable regression magnitude. Inspect the new normal-mode hot-path
   loads/checks, prepare controlled interleaved before/after measurements and
   request a serialized slot. Fix a demonstrated avoidable cost, not noise.
   Three corpus runtime benchmarks means three executable workloads in both
   runtimes; `jobq` build timing alone is not the third runtime benchmark.
   Preserve all samples and failures. Full-suite timings stay lead-owned.

Corrective write scope remains the original scope, plus
`toolchain/bench/step38/measure.py` strictly for complete per-sample reporting
and the measurement controls above. The prior worker changed that helper
outside its named scope; the lead reviewed the diff and now explicitly owns
this bounded scope extension. Keep benchmark corpus inputs unchanged between
trees, and do not break existing output-path callers. Report which prior
results no longer apply after corrective code changes.

## Current safety evidence continuation

20 Sep 2026. Fresh OMP/GPT Sol/high worker `step42-safety-sol`; lead Astra
remains in w4:p1. Worktree `toolchain-step42-safety-evidence`, branch
`toolchain/step42-safety-evidence`, exact base
`65b3dd37c4b2acc74bbdc425a723a163b69e50f8`. The previous corrective worker is
no longer registered. Preserve its worktree and untracked review evidence
unchanged; no conversation resume, fork or import.

**Static preparation only while Step44 owns runtime verification.** Read the
lead inventory at
`audit/evidence/2026-09-19/omp-resumption/step42-review-obligations-inventory.txt`
in the main checkout. Its seven remaining obligations are not waived:

1. Exhaustive normal stress sweep at the current runtime checkpoint.
2. Exhaustive ASan corpus sweep with raw stderr; no warning suppression.
3. Actual ASan use-after-poison from a current-representation stale-answer
   mutant at n=10, the 45-byte boundary; print the actual input.
4. The same stale boundary caught by ordinary interpreter and native
   `-DMO_STRESS`, separately from ASan.
5. Real packs=true retaining-boundary transfer, drop, absent/timed-out waiter,
   update crash, process restart/end and committed-event cleanup outcomes.
6. Normal-mode hot-path analysis grounded in current source and the existing
   correction-only measurements; no zero-cost claim.
7. Before/after unfiltered suite timing remains lead-owned, not waived;
   Linux remains deferred.

For this static stage, write only
`toolchain/bench/step42/safety-evidence/**`: executable probe/test drafts,
unapplied mutation or focused-test patches, and a command/coverage manifest.
Existing runtime, source tests, build files, guards, corpus, measurement
driver and final report stay frozen. Use existing harness conventions; do not
invent public hooks, instrumentation or a second runner. If a production or
test hook is necessary, name the exact prerequisite rather than applying it.
The manifest must map every outcome to its existing or drafted control and
exact command, expected diagnostic/count, guard, restoration and cleanup.
Account for current ParcelValue holders and custom-fiber sanitizer hooks.
Never read an auditor's hidden suite or operate the lead's audit inbox.

No build, test, runtime/probe execution, py_compile, formatter, linter,
benchmark, debugger, machine/Linux operation, push or merge in this stage.
No nested delegation. Preserve historical evidence and the measured
65b3dd37 runtime/driver checkpoint. The completed 60-sample comparison is
against prior **unaccepted** be64e8a5, not whole-step overhead; do not rerun or
rewrite it, including its documented load-heading error.

Done for this stage: bounded static drafts and concrete remaining command/
coverage manifest, source-based hot-path notes, exact prerequisites and
changed paths reported to the lead, explicitly unexecuted; then HOLD for
review and a serialized runtime grant. Do not write the final report yet.

## Related

- [[toolchain-raw-memory-report]]
- [[interpreter-step-41]]
- [[mo-harness-in-mo]]
