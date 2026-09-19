---
title: "Step 41: Exec, a child process narrowed to fixed commands"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [stdlib, security, runtime, processes]
sources: [plans/mo-capabilities-for-the-harness.md, spec/design-v0/09-stdlib.md]
status: done
---

# Step 41: `Exec`

## Orientation

Robert decided on 19 Sep 2026 that Mo gains a scoped child-process capability,
so that the harness's executor can be written in Mo. The design is section 3 of
[[mo-capabilities-for-the-harness]]; read it first, with its reasons. The shape:
`platform.exec` exists only in `main`; it makes a `Program` (one absolute path),
which makes a `Command` (a fixed argument list of `Fixed(text)` and `Hole`);
only a `Command` runs or travels. No shell, no `PATH`, no interpolation, empty
environment by default, own process group killed at the deadline, bounded
output. No new syntax. Worker: a fresh Claude Opus session, bypass permissions,
own worktree and Herdr tab, based on the branch that holds step 40. The lead
owns the wiki (except the spec rows listed), audit and acceptance.

## Write scope

`toolchain/src/**`, `toolchain/runtime/**`, `toolchain/PRELUDE.md`, new corpus
files under `examples/` with their sidecars and `verified:` lines (real tools
only), and in `mo-wiki/spec/design-v0/09-stdlib.md` a new section for `Exec`.
No harness code, no other wiki, no `audit/`, `HANDOFF.md`. No machine, Docker,
`/opt`. No push. Never use `tr`; `ls` is aliased, use `/bin/ls`. The Linux VM
is the lead's; you run on this Mac only.

## Parts

### A. RED first

Corpus tests, `mo run` and a `mo build` binary, against small helper programs
the Zig test writes into a temporary folder (shell scripts are fine as
*children*; Mo never invokes a shell): exit codes 0, 1 and 255; death by
signal; a child that ignores `SIGTERM` and sleeps past `within:` (killed,
`Timeout`, and gone afterwards); a grandchild in the group (gone afterwards);
output past the bound on stdout and on stderr (`truncated: true`, the child not
blocked forever on a full pipe); a hole holding spaces, quotes, `$(...)`, a
leading `-`, and a newline, arriving as exactly one argument, byte for byte; a
hole holding a NUL (`Refused`); wrong hole count (`Refused`); a missing program
(`Missing`); a relative program path (refused when the `Program` is made); the
environment empty by default and exactly the map when given; the working
folder inside an `Fs` scope, and a scope that is a link refused as step 40
refuses it; `stdin` delivered and closed; no descriptor but 0, 1, 2 open in the
child (check from the child).

### B. The capability

As the design page's table: `Platform.exec`, `Exec.program`, `Program.command`,
`Command.env`, `Command.in`, `Command.output`, `Command.run`, `Exec.fixture`,
the `Arg`, `Done`, `Exit` and `ExecError` types. `Exec` and `Program` obey
`MO0407` as `Platform` does (not stored, sent, returned or captured);
`Command` travels like an `Fs`. `run` waits on the blocking pool so the
scheduler is never blocked; both runtimes. Spawn with `posix_spawn` or
`fork`/`exec` with every descriptor closed on exec; `setpgid` so the child
leads its own group; at the deadline `kill(-pgid, SIGKILL)`, then reap, and
only then answer `Timeout`. Output is drained while the child runs, so a child
writing more than a pipe holds never deadlocks; bytes past the bound are
dropped and `truncated` set. Use std's per-target wrappers and `posix.errno`,
never a raw syscall's return value (step 40's Linux lesson:
`toolchain/STEP-40-REPORT.md`, "Linux follow-up").

### C. The simulator and the checker

`Exec.fixture(fn)` answers every run in tests; `mo test --sim` schedules a run
like any wait and injects `Timeout` and `Failed` at its fault rate. The
capability checks (`caps.zig`) treat `Exec`/`Program`/`Command` as capabilities:
a function that receives none cannot run anything, and `flows` output names
them.

## Numbers

Best of five, both runtimes, load average beside them: the cost of one `run`
of `/usr/bin/true`, and of a child writing 1 MiB, against the same from a C
`posix_spawn` loop as the floor.

## Done when

Every process under `toolchain/bench/step36/guard.py`; after any kill, check
for orphaned test binaries. `zig build` exit 0; focused tests by
`-Dtest-filter` with real summary lines and exit codes; you may run the two big
corpus tests by filter; **the unfiltered full suite and Linux are the lead's**.
RED output committed before GREEN. Small commits as yourself with a
`Co-Authored-By` line naming your model. **Write your final report to
`toolchain/STEP-41-REPORT.md` and commit it.** While anything runs, wait in the
foreground so your tab does not look finished.

## Result

Accepted on macOS 3:33 PM ET, 19 Sep 2026, merged to `main` through
`lead/verify-step41` (`cdb36196`). Worker: Claude Opus 5, report
`toolchain/STEP-41-REPORT.md`. `Exec`, `Program` and `Command` exist in both
runtimes with the fixture and `--sim` faults; `MO0407` keeps `Exec` and
`Program` in `main`; a `Command` travels like an `Fs`. Darwin full suite 268
of 268; lead probes green in both runtimes. Cost of one run of
`/usr/bin/true`: 1.2 ms (`mo run`) and 1.1 ms (binary) against 0.93 ms for a C
`posix_spawn` loop; a child writing 1 MiB costs 3.9 and 2.3 times the floor,
because the bytes become a `List(UInt8)`. Darwin spawns with one
`posix_spawn`; Linux forks, and **that path is owed its Linux run** (one run
before the deferral: 41 of 42 control lines right, the one failure a test
predicate since fixed). Three differences from the design, ratified on the
decision log: the row is `in_folder` (`in` is a keyword), an argument is
`Fixed(text: "rm")`, and a module's own variant hides a stdlib struct of its
name (the new `Done` collided with the agent's). Evidence:
`audit/evidence/2026-09-19/fable-lead-verification/step41/`.

## Related

- [[mo-capabilities-for-the-harness]]
- [[interpreter-step-40]]
- [[mo-harness-in-mo]]
