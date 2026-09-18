---
subject: step 38's brief (a full-duplex `Conn`, `TCP_NODELAY`, the handshake abuse rows), read as a plan before its result
author: Fable (the lead)
date: 2026-09-18, about 10:25 AM ET
filed_against: the brief as on main at 504add8; the worker was started on it at 9:26 AM ET, before this reading and before the auditor's was announced
read_before_auditor: yes. Fable had not opened the auditor's reading, its checks, its evidence folder, or its `audit/state.md` lines on this subject when this was written; the receiver announced pointers only (kind, id, commit, path, the PR number). Robert said only that the PRs exist.
evidence: mo-wiki/plans/interpreter-step-38.md; toolchain/bench/step37/RESULTS.md ("What the runs found outside the brick"); the decision-log rows of 18 Sep on step 38 and on the server crash
---

# Fable's reading: step 38's brief

Fable wrote the brief at about 4 AM ET and started a worker on it at 9:26 AM
ET today, so anything below that the brief lacks is a follow-up to the
running step, not a change to it.

## What the brief gets right

It comes from measurements (a 58.5 s stall; 8.98 s against 0.39 s by window
size), it names both runtimes and both transports for every part, it keeps
the spec's `Busy` rule, and part C turns step 37's second defect into a table
with an expected answer per cell rather than "run the abuse script".

## What it lacks

1. **Part A changes how the TLS engine is driven, and the brief does not
   re-run the brick's audit items.** Step 37's differential run and fuzz hour
   were taken on an engine driven by one fiber. If part A adds a guard inside
   `tls.zig`, or reorders when the runtimes call `flush` and `feed`, items 3
   and 4 describe code that has changed. The brief should have asked for the
   1,000-session differential run again after part A, and for the diff of
   `tls.zig` to be stated in the report (ideally empty).
2. **"Guarded so they never interleave" is a claim about a data race, and the
   brief asks for no test that could see one.** In the binary runtime a
   reader and a writer on one `Conn` may be on different schedulers, so this
   is two threads on one engine, not two fibers taking turns. The one test
   (1,600 lines echoed in under a second) is a liveness test. Missing: a
   stress with a KeyUpdate arriving while a large write is blocked, at
   `MO_CORES` of 1 and of the machine's count, for minutes, with every byte
   checked; and a ThreadSanitizer build of the C runtime, if one can be made.
3. **No threshold for part B.** "Measured before and after" with no number
   that would make the change a failure. The implied one is the 16-line
   window falling from 8.98 s to near the 256-line window's 0.39 s.
4. **Before and after on which machine?** Step 37's numbers are the VM's;
   this step runs on the Mac. The brief says before and after, so both will
   be the Mac's, but then the "before" is a new measurement nobody has seen,
   taken by the party whose "after" it flatters, on a machine that is running
   three other sessions this morning.
5. **The write's deadline under duplex** is stated ("still holds") and has no
   test: a write blocked on a peer that reads nothing must still time out
   while the same `Conn`'s reader keeps delivering.
6. **Part C's 32 cells include "nothing until the deadline" in eight of
   them**, so the table's run time is dominated by deadlines; fine, but the
   brief gives no deadline to use, so the worker will pick a short one and
   the cell then tests a different constant from program 7's 10 seconds.
7. **What program 7 actually needs is not quite what part A tests.** A Redis
   server's hard case is a subscriber or a blocked client: a process other
   than the connection's reader writes to the `Conn` (a published message, a
   woken `BLPOP`) while the reader is parked in `read_line`. The brief's test
   writes from `main` while `lines` reads, which is the client's shape. The
   server's shape (writer and reader are different processes, several
   would-be writers, `Busy` on the second) deserves its own test, since it
   decides how `mored` must be structured.

## Reading

A sound step aimed at real findings, under-specified on exactly the part
that is hardest to get right (concurrency on the engine). Acceptance should
not rest on the brief's Done-when alone: Fable's own probes at acceptance
should include items 1, 2, 5, and 7 above, and whatever they find is a fix
session or a step 38b before program 7's build.
