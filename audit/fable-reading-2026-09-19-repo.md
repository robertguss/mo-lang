---
subject: repo
author: Fable (Claude Fable 5.1, Claude Code, project lead)
date: 2026-09-19, 1:20 PM ET
filed_against: 2f61e839ce2d307f9d84d9026402f55e34e7c64d
read_before_auditor:
  yes; PR 15's reading (audit/mo-audit-2026-09-19-repo.md), its audit/state.md
  change and core/REPORT.md have not been opened
---

# Lead reading: repository validation and verification health, before opening PR 15

Robert pointed the lead at PR 15 at about 1:18 PM ET. `fable_poll.py check`
announced no record for it, so this reading answers the pull request itself.
Disclosed exposure: the PR's title ("compiler validation defects and
verification gaps"), its file list, and these raw files from its head
`c64fec29`: the probe programs and their `.json`/`.log` outputs under
`core/`, `environment.json`, `suite.json`, `build.json`, the filtered test
records, `tls-tests.log`, `cleanup.json`, `fuzz-controls.py` and `.json`,
`provider/local-controls.json`, and the tails of the two executor logs. So this
is not a cold discovery of the probes; it is an independent reproduction and a
source reading. The auditor's anchor is `8342cfe0`, this morning's `main`, on
x86_64 Linux; the lead's runs are current `main` on Darwin. Lead probes and
outputs: `audit/evidence/2026-09-19/fable-repo-reading/`.

## Reading

1. **The integer literal range check is unsound, and the lead concedes it
   whole.** `toolchain/src/check.zig` `checkLiteral` (line 672) copies at most
   32 digits and drops the rest silently, then maps a parse overflow to
   `maxInt(u64)`. Two holes follow, both reproduced on current `main` in
   `check`, `mo run` and a native binary, all exit 0:
   a `UInt8` function returning `00000000000000000000000000000000256` prints
   `256`; a `UInt64` function returning `18446744073709551616` prints that
   number. The lead's own probes make it worse: a 54-digit literal typed
   `UInt64` prints `170141183460469231731687303715884105727`, a number the
   source never held (`bytecode.zig:1709` and `emit_c.zig:1366` `parseInt`
   saturate an `i128`), and `Int8` with leading zeros prints `200`. The
   negative control holds (`UInt32` 4294967296 is `MO0217`), and an untyped
   oversized literal is caught because `Int64`'s bound is below the sentinel.
   This is a hole in a claim the language makes in its own words ("overflow is
   never implicit"). Values outside their type then flow into both runtimes;
   what arithmetic does with them was not probed.
2. **A mailbox bound is never validated, and the compiler panics.**
   `mailbox: 4294967296` passes `mo check` (exit 0), then `mo run` and
   `mo build` abort with "integer does not fit in destination type" (exit 134
   on Darwin; `@intCast` at `bytecode.zig:1318` and `emit_c.zig:950`). Lead
   probes: 4294967295 and 0 are accepted silently (what a mailbox of 0 means is
   unspecified and untested); a 26-digit bound panics the same way. A compiler
   panic on a user's program is a defect whatever the program.
3. **The negated-minimum-Duration probe shows nothing either way.** The
   program is refused by the checker (`MO0206`, unary minus on a Duration) in
   every mode, so no runtime behaviour was reached. Whether a minimum Duration
   can be negated by another route (subtraction from zero, `abs`) is open; the
   lead did not probe it.
4. **The full suite cannot be run inside a bounded outside window, and that is
   the lead's gap.** The auditor's `zig build test -j2` hit its 180 s limit
   (exit 124) with an empty log; that is a timeout, not a failure, and not a
   pass. On the lead's Mac the suite now takes more than ten minutes; its
   first x86_64 Linux full run was started today and had not finished when this
   was written. A reproducible CI gate, owed since 18 Sep, is still owed. The
   filtered runs (exit 0) and the TLS brick's 31 of 31 unit tests are what they
   say and no more: step 39 stays unaccepted, and the corpus test "a fatal
   alert where a hello belongs" still fails about 1 run in 5 alone on Darwin,
   unexplained.
5. **The auditor's suite run moved generated files** (`examples/zig-out`,
   `toolchain/.zig-cache` relocated, per `cleanup.json`). The suite writes into
   the source tree; the lead lost a run today to the same sharing (an orphaned
   test binary deleted `zig-out`). A suite that cannot run twice at once, or
   from a read-only tree, is a verification-health defect.
6. **The fuzz driver accepts a run of nothing as success.** The mocked
   controls show `--minutes 0`, `-1` and `nan` each exit 0 after "0 inputs in
   0 batches". The 18 Sep counting defect appears repaired in the mock (a
   failed batch now exits 1 and retains its inputs), but a zero-input run must
   not be a pass, and `nan` must be a usage error. Mocks show control flow, not
   TLS behaviour.
7. **Executor and provider offline controls pass as recorded** (22 and 16
   Python tests; 7 provider controls, no outbound traffic, a synthetic OAuth
   stub). They are at this morning's anchor: the executor has since had steps 1
   and 2 land (unit count now 110), so those logs do not describe current
   `main`. No live provider claim exists and none is made.

## What the lead will do

Findings 1 and 2 become one toolchain fix brief, RED first, with a sweep of
every other place the compiler parses a number from source (`parseInt` has at
least two copies; durations, `within:`, budgets, ports). Finding 6 joins the
instrument fixes. Findings 4 and 5 join the CI gate. Each is a decision-log row
once the auditor's reading has been compared.
