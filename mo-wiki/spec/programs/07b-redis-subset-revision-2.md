---
title:
  "Program 7, revision 2: amendments to `mored`'s sealed spec before any build"
created: 2026-09-18
updated: 2026-09-18
type: spec
tags: [programs, runtime, security, audit]
sources: [spec/programs/07-redis-subset.md, decisions/decision-log.md]
status: sealed
---

# Program 7, revision 2: amendments to `mored`'s sealed spec before any build

[[07-redis-subset]] was sealed on 18 Sep 2026 at 3:50 AM ET and is not edited.
Two readings of it the same morning, the auditor's
(`audit/mo-audit-2026-09-18-program-7-spec-compliance.md`) and Fable's
(`audit/fable-reading-2026-09-18-program-7-spec.md`), agreed it was not ready to
build against. This page is the revision: **everything in [[07-redis-subset]]
holds unless a line below changes it**, and a maintainer is given both pages. No
build, hidden suite, or seed existed when it was written. No ratified threshold
of either stopping rule changes. Sealed by the `ready` record
`program-7-spec-ready-002` that names this page at its commit; a further change
is a row and a revision 3.

## 1. Persistence is not tested by Redis's suite (replaces three names in "The test suite")

`unit/aofrw.tcl`, `integration/aof.tcl`, and `integration/aof-multi-part.tcl`
are **removed from the list**. At tag 7.2.4 all three are tagged `external:skip`
and the two integration files start their own `redis-server` from a generated
configuration file, so against a server the runner did not start they run
nothing. Persistence is tested by the program's own tests ("Tests the reader
expects to see"), by `mored --check-aof`, and by the auditor's hidden suite, and
the reading says so: **Redis's tests say nothing about `mored`'s durability.**
The denominator for every remaining file is measured, not assumed: section 9.

## 2. A rewritten key keeps its expiry (adds to "Persistence")

In an AOF rewrite every key with an expiry is followed by
`PEXPIREAT <key> <absolute ms>`, whatever its type; strings may use
`SET ... PXAT` instead. A key already past its expiry at rewrite time is not
written. The never "expiry for expiry" covers every type across a rewrite, a
`DEBUG RELOAD`, and a restart.

## 3. One size rule (replaces the sentence on 512 MB and 64 MiB in "The protocol")

A single command, counted as the bytes of its whole multibulk or inline form, is
at most **64 MiB**, and a multibulk has at most **1,048,576** elements. A header
that announces more (a bulk length over 64 MiB, an element count over the cap,
or a running total past 64 MiB) is answered
`-ERR Protocol error: invalid bulk length` or `invalid multibulk length` as
Redis words them, **before the body is read**, and the connection is closed.
`INFO server` reports both caps. No test sends a body near the cap; a header is
enough.

## 4. The skip list is the lead's (replaces "The Mo maintainer writes the list")

Fable writes `examples/programs/mored/tests/skips.txt` **before either build**,
from the measured baseline of section 9 and the spec's deviations, one test name
per line with one of six reasons: an out-of-set command; an encoding assertion;
a Redis-internal `DEBUG` subcommand or `CONFIG` the set does not carry; RESP3;
client certificates or RSA test keys; a test Redis 7.2.4 itself cannot run
against an external server (section 9). **There is no "timing assumption"
reason.** Both maintainers get the same file with the spec. A maintainer who
believes a test is wrongly unskipped says so in its report's decisions list and
does not skip it; a skip added after the builds start is a row, counted as
"skipped late" against that build.

## 5. The core operation for RC2 is named

`redis-benchmark -t set,get -c 50 -n 1000000 -P 1 -d 64` against the plain port,
the **binary** (the Elixir release), on the Linux rig, three trials, the median:
**`GET`'s requests a second is RC2's throughput and `GET`'s p99 its latency**;
`SET`'s are reported beside them. Every other row of the spec's benchmark list
is recorded and decides nothing. Every measured number of the spec is taken from
the binary, never `mo run`, on Linux (where `fsync` is the full promise; the
decision-log row of 18 Sep on macOS).

## 6. R2, R4, R5, R7, RC1, and R6, pinned

- **R2's window.** The fault rig kills the keyspace process (Mo: through the
  runtime surface's kill; Elixir: `Process.exit(pid, :kill)` on the process the
  maintainer's report names as the keyspace owner) at a random moment under a
  steady load of `SET` from 50 clients, twenty times. **Recovery is the time
  from the kill to the first `+OK` any client gets**; MTTR is the mean of
  twenty. The `--faults 0.05 --until 0.5` line of the spec describes Mo's
  simulator run in "Tests the reader expects to see" and is not the R2 rig,
  since the BEAM has no equivalent. A program whose keyspace process cannot be
  killed without ending the server has an MTTR of its restart time under its own
  supervisor or, if it does not come back, fails R2.
- **R4's hundred edits** are the first hundred commits or saved edits of the Mo
  maintainer's session, read from its transcript by the auditor; fewer than a
  hundred is reported as the number there were.
- **R5 means the runtime's replay**: a crashed `mored` process replayed from its
  snapshot and message log on the same seed under `mo test --sim`, 100 of 100
  byte-identical states. It is Mo-absolute; Elixir has no counterpart and none
  is scored. The AOF reload is the spec's never and the hidden suite's business,
  not R5.
- **R7's cold boot** is with an empty `<dir>`, from `exec` to the first `+PONG`.
- **RC1's clock** runs from the maintainer's first prompt to its final report
  ("every check green, the Redis suite's counts printed"); the hidden suite is
  run afterwards by the lead and is not on the clock.
- **R6's session** gets the runtime surface and the crash store only: `INFO`,
  `/metrics`, the AOF, and stderr are withheld. The binary under test is built
  with `--surface`, and it is the same binary that is benchmarked.

## 7. P4 has something to update (replaces the last sentence of "Metrics" and one line of "The Elixir counterpart")

The Elixir build **serves `/metrics` through a hex package** for the exposition
format and the registry (the maintainer's choice among maintained ones; named in
its report, pinned in `mix.lock`), not through hand-written text. The auditor
names the package version pair and the equivalent functional change for P4 in
its sealing session. Argon2 stays a package; `:ssl` stays OTP's.

## 8. Small corrections

Elixir **1.18** on OTP 27, as the rig has. RC3's million keys are strings with
64-byte values and 16-byte keys, no expiry. Dev-time tools (`tclsh`, the Redis
clone, the certificate generator) are counted in the tools column for both
builds and never in the dependency count. The capability-abuse suite's seam is a
recipe's body: each of the four recipes declares its `needs`, and an abusive
body is one that reaches for authority its `needs` line does not grant. Each
recipe meets the rule's full gate: three exports, five contracts, fifty
implementation lines.

## 9. The baseline is measured, not assumed

Against a server the runner did not start, even Redis itself does not run
every test in these files: Fable's first run of Redis 7.2.4's runner in
`--host` mode against a `redis-server` 7.2.4 (18 Sep 2026, partial, eight
files: `audit/evidence/2026-09-18/program-7-spec-r2/`) saw `unit/type/set`
end in an exception after 107 tests and `unit/type/stream` hang in a test
that starts its own server. **The ceiling per file is what Redis 7.2.4
itself passes in this mode on the Linux rig**, measured by the lead before
the skip list is written and filed in that bundle; `mored`'s "tests passed
of tests not skipped" is read against it, and a test Redis itself cannot run
in this mode is on the skip list with the reason "cannot run against an
external server", section 4's sixth reason. The numbers live
in the bundle, not on this page.

## Related

- [[07-redis-subset]]
- [[decision-log]]
- [[the-audit-workflow]]
- [[interpreter-step-38]]
