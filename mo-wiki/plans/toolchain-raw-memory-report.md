---
title: "Toolchain: a large application report prints raw memory"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [compiler, runtime, security]
sources: [plans/mo-harness-in-mo.md]
status: in-progress
---

# Toolchain defect: raw memory in a large report

## Orientation

Found by the application workspace rebuild worker, 19 Sep 2026; its note is
`examples/programs/agent/tests/application-workspace-v1/evidence/toolchain-defect-01.md`
with a probe saved beside it as `sizes_probe.py.txt`. Rendering an application
report over about 0.35 MB made the **native binary print raw process memory to
stdout** (which could expose a capability token); over about 0.8 MB the
**interpreter panics**, `access of union field 'string' while field 'none' is
active` at `vm.zig:1531`. The same reply through `coding-fixture` mode is
correct in both runtimes; the worker narrowed the interpreter panic to
`application_report` reached from the Application process's `Poll` arm by a
delayed self-send, and did not find the cause. The slice now caps reports at
256 KiB as mitigation. This is a memory-safety defect in the runtimes, so it
matters beyond the harness. Worker: a fresh Claude Opus session, bypass
permissions, own worktree and Herdr tab. The lead owns wiki, audit, acceptance.

## Write scope

`toolchain/src/**`, the C or Zig runtime sources the native binary links, and
new corpus tests under `examples/` that reproduce the defect small. Regenerated
`.mo.ids` records and `verified:` lines only through the real tools. Not the
agent program's source (the cap stays until the lead lifts it), not
`mo-wiki/`, `audit/`, `HANDOFF.md`. No machine, Docker or `/opt`. No push. Never
use `tr`. No new syntax.

## Parts

1. **Reproduce** at the uncapped source: worker commit `5caec127` on branch
   `harness/application-workspace-v2` (use a scratch copy outside `examples/`,
   not a checkout of that commit in your tree). Both runtimes, sizes 250,000 to
   851,700.
2. **Reduce** to the smallest Mo program that shows each failure, with no
   agent code: likely a process that receives a delayed self-send and builds or
   returns a large String through a deferred `Reply`. A reduction that fails is
   the step's most valuable output even if the fix does not land.
3. **Find the cause and fix it** in each runtime. Suspects, unverified: a
   String or Json value freed or moved while a deferred reply or a timer
   message still references it; an arena reset between a process's updates; a
   size threshold where a small-buffer path becomes a heap path. Say what it
   was, with the source lines.
4. **Tests.** The reductions become corpus tests that fail before the fix and
   pass after, in `mo run` and in a `mo build` binary. Add a native-runtime
   check that would catch the class, if one is cheap (for example running the
   reductions under the allocator's safety mode or an address sanitizer build);
   report what you tried.

## Numbers and done when

Every process under `toolchain/bench/step36/guard.py` with a timeout and the
4 GB watchdog: this defect involves large buffers and a runaway is possible.
`zig build` exit 0; focused tests with `-Dtest-filter`; **the full
`zig build test` is the lead's, do not run it**. Report real summary lines and
exit codes. If you cannot find the cause in the time it takes to do the rest,
stop and report the reduction and what you ruled out. **Write your final report
to `toolchain/STEP-RAW-MEMORY-REPORT.md` and commit it.**

## Related

- [[mo-application-workspace-v1]]
- [[mo-harness-in-mo]]
