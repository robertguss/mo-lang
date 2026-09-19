---
title: "Step 40: a scope that holds, and Fs.replace"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [stdlib, security, runtime, compiler]
sources: [plans/mo-capabilities-for-the-harness.md, spec/design-v0/09-stdlib.md]
status: in-progress
---

# Step 40: a scope that holds, and `Fs.replace`

## Orientation

The first toolchain step of [[mo-harness-in-mo]]; the design is sections 1 and 2
of [[mo-capabilities-for-the-harness]], which the worker reads first. Chapter 09
says of a narrowed `Fs` that "nothing outside the scope is reachable". Today the
check is on the path's text only (`toolchain/src/stdlib.zig`, `pathIn` and
`climbsOut`), so a symlink inside `fs.scoped("work")` reaches whatever it points
at. This step makes the sentence true in both runtimes and adds an atomic write.
`Exec` is the next step, not this one. Worker: a fresh Claude Opus session,
bypass permissions, own worktree and Herdr tab. The lead owns the wiki (except
the spec lines listed), audit and acceptance.

## Write scope

`toolchain/src/**`, `toolchain/runtime/**`, `toolchain/PRELUDE.md`, new corpus
files under `examples/` with their `.mo.ids` sidecars and `verified:` lines
(through the real tools only), and in `mo-wiki/spec/design-v0/09-stdlib.md` only
the Files section's rows and sentences this step changes. No new syntax. No
harness code, no `mo-wiki/` otherwise, no `audit/`, `HANDOFF.md`. No machine,
Docker, `/opt`. No push. Never use `tr`; `ls` is aliased, use `/bin/ls`.

## Parts

### A. Sweep, then RED

1. Search `examples/` and `toolchain/` tests for anything that reads or lists
   through a symlink on purpose. Report what you find before changing behaviour;
   none is expected.
2. Corpus tests that fail today, in `mo run` and in a `mo build` binary, each
   building its hostile tree in a temporary folder from the Zig test (Mo cannot
   make a link): a file symlink inside the scope pointing outside; a folder
   symlink as a middle component; a link pointing inside the scope (still
   refused: the rule is about links, not destinations); a link as the target of
   `write`, `append`, `remove`, `rename` (both ends) and `mkdir`; a FIFO and a
   device as a read target; a scope folder that is itself reached through a link
   (allowed: that path is the operator's). Take the cases from
   `toolchain/harness/executor/test_workspace.py`'s hostile entries so the two
   stay comparable. Commit the failing run's output before any fix.

### B. The scope holds

Every `Fs` row resolves its path one component at a time from the scope's folder
without following links (`openat` with `O_NOFOLLOW` and `O_DIRECTORY` for
folders, or the platform's equivalent; say what Darwin and Linux each need), in
the interpreter and in the native runtime. A refused path is `Missing(path)`
with the path as the program wrote it. Reads and writes take regular files only.
The window between resolve and use must not reopen the hole: operate on the
descriptor you resolved, not on the path again. `list_kinds` reports a link as
`Link`, a new `EntryKind` variant; `list` still names it. `fs.kind_of(path)`
returns an `Entry` extended with `links: UInt64` and `setuid: Bool`.
`Fs.fixture()` behaviour is unchanged. Update `PRELUDE.md` and chapter 09's
rows; the checker's exhaustiveness on `EntryKind` will flag corpus programs that
match on it: fix those matches and list them.

### C. `Fs.replace`

As the design page's row: temporary name in the same folder (unpredictable,
created exclusively, mode 0600), written, synced, renamed over `path`, the
folder synced. A failure leaves the old file whole and no temporary file behind.
A read-only `Fs` refuses it as it refuses `write` (`MO0404`). On a fixture it
behaves as `write`. Control: a child killed between the write and the rename
leaves the old bytes; a reader looping during 1,000 replaces never sees a
partial file. On macOS use the sync `write` already uses; do not claim
`F_FULLFSYNC`, which step 39 owes.

## Numbers

Best of five, both runtimes, load average beside them, before and after: the
corpus's file benchmarks that exist today (`read`, `write`, `append`,
`fold_lines` on a large file, `list` on a large folder), since per-component
opens cost system calls. Report the cost per path component. A regression past
10% on any row is a finding for the lead, not a blocker.

## Done when

Every process under `toolchain/bench/step36/guard.py`. `zig build` exit 0 and
focused tests by `-Dtest-filter` with real summary lines and exit codes; **the
full `zig build test` is the lead's**. RED output committed before GREEN. Linux
is checked by the lead on the machine's trusted toolchain; say what you could
not check on Darwin. Small commits as yourself with a `Co-Authored-By` line
naming your model. **Write your final report to `toolchain/STEP-40-REPORT.md`
and commit it**: commits, decisions the brief did not cover, corpus programs
touched, numbers, what the lead must rerun.

## Related

- [[mo-capabilities-for-the-harness]]
- [[mo-harness-in-mo]]
- [[interpreter-step-39]]
