---
subject: program 7's sealed spec (`mored`), read against the two ratified stopping rules it is the test of
author: Fable (the lead)
date: 2026-09-18, between 9:30 and 9:50 AM ET, pushed at baf6683 (corrected 9:54 AM ET: the header first said "about 10:15" or "10:25", a time Fable guessed instead of reading the clock; nothing else in the file changed)
filed_against: 972c872 (the ready record program-7-spec-ready-001)
read_before_auditor: yes. Fable had not opened the auditor's reading, its checks, its evidence folder, or its `audit/state.md` lines on this subject when this was written; the receiver announced pointers only (kind, id, commit, path, the PR number). Robert said only that the PRs exist.
evidence: mo-wiki/spec/programs/07-redis-subset.md; audit/mo-audit-2026-09-17-stopping-rule-runtime.md; audit/mo-audit-2026-09-17-stopping-rule-capabilities.md; Redis at tag 7.2.4, tests/ (fetched 18 Sep, about 9:40 AM ET, to check the test files the spec names)
---

# Fable's reading: does program 7's spec let the two rules be read?

Fable wrote this spec at 3:50 AM ET. This is Fable reading it again six hours
later against the rules, row by row. It has one defect that must be fixed
before any build and several places where the spec does not pin what a rule
needs pinned. None can be fixed in place: each is a decision-log row and a
new `ready` record.

## The defect: the persistence tests the spec names do not run in the mode it prescribes

The spec says the suite runs in `--host` mode and names `unit/aofrw.tcl`,
`integration/aof.tcl`, and `integration/aof-multi-part.tcl`. At tag 7.2.4 all
three are tagged `external:skip` (`aof.tcl` line 11, `aofrw.tcl` lines 3 and
62), and the two integration files start their own server from a generated
`redis.conf` through `start_server_aof`, 19 and 23 times. Against an external
server Redis's runner skips them whole. **So, as sealed, Redis's own tests
contribute nothing on persistence**, which is the part of program 7 the
runtime claim cares most about (crash consistency, exact replay). Other named
files carry `external:skip` blocks too (`unit/other.tcl` 3, `unit/acl.tcl` 9),
and `unit/tls.tcl` is mostly `CONFIG SET tls-*` and client certificates,
which the spec's deviations already remove. Fable named these files from
memory of Redis's layout and did not open them. Options, for a row: (a)
persistence is tested by the program's own tests and the auditor's hidden
suite only, and the spec says so; (b) `run.sh` puts a `mored` shim where the
runner expects `src/redis-server`, which means `mored` must read a Redis
config file, a real enlargement of the program for both maintainers. Fable's
recommendation is (a), with the count of Redis tests that actually run stated
per file before the first commit by the lead, not by a maintainer.

## Row by row

| rule row | what the spec gives | gap |
|---|---|---|
| R1, hidden suite of 50 or more | a wide surface with durability, blocking, ACL, TLS | none in the spec; the suites are the auditor's |
| R2, MTTR under `--faults 0.05 --until 0.5` | named in Measured | **the spec mandates no process structure and no restart behaviour**, so "recovery" has no defined start or end; and the flags are Mo's simulator's: "the same fault rig at the same rate on the same actions" for Elixir is asserted, not designed. Nobody has said how a 5 percent `Fs`/`Net` fault rate is injected under the BEAM |
| R3, no unbounded wait | five blocking commands, a never on timeouts, `0` means forever but wakeable | good; the probe is the auditor's |
| R4, `verified:` drift across 100 sequential edits | "the drift budget across the maintainer's edits" | a build may not have 100 edits; the spec does not say how the count is reached or who counts |
| R5, 100 of 100 replays byte for byte on the same seed | "100 replays byte for byte" and a never on the keyspace after an AOF replay | **two different things share the word.** The rule is about a crashed process replayed from snapshot and message log on a seed; the spec's never is about an AOF reload. The spec does not say which the 100 are. Elixir has no seeded replay, so R5 is Mo-absolute; the spec should say so |
| R6, diagnosis from `platform.runtime` alone | named in Measured | the usage line has no surface port, so the binary under test is a different build (`--surface`) from the one benchmarked unless the spec says they are the same; `INFO` and `/metrics` are program-written diagnostics the outside session must be denied, unsaid |
| R7, one binary, 50 MB, 500 ms cold | "size and cold boot" | cold boot with what AOF? An empty `<dir>` should be stated |
| RC1, time "from empty repo to first passing hidden suite" | "maintainer time" | the maintainers never see the hidden suite, so the clock's end is undefined in the spec. Fable's row of 17 Sep gave a reading (the maintainer's own done); the spec does not repeat it |
| RC2, the core operation within 0.7×, p99 within 1.5× | seven commands × two pipeline depths × plain and TLS | **twenty-eight numbers and no named core operation**: whichever is picked after the fact will look picked. One should be named before a build |
| RC3, RSS at 1,000,000 keys | named | value size and type unsaid |
| RC4 and P1, zero dependencies | the brick and recipe list | fine; dev-time tools (`tclsh`, the Redis clone, a certificate generator) belong in the tools column for both |
| P2, recipes | four recipes, each with contracts and tests | fine |
| P3, capability abuse, 10 shapes | each recipe's `needs` line | the spec does not say where an abusive body attaches; presumably a recipe body. The auditor's to design, but the seam should be named |
| P4, a modification that is `hex update` in Elixir | the metrics endpoint | **the Elixir maintainer may hand-write the Prometheus text format and use no package**, in which case there is nothing to update and P4 compares two hand edits. Same for TLS (`:ssl` is OTP's). Only Argon2 forces a package. This is Fable's 17 Sep disagreement in concrete form |

## Things wrong that are not a rule row

1. **The Mo maintainer writes the skip list and the Elixir maintainer
   inherits it.** That puts the list-writing time on Mo's RC1 clock only,
   orders the builds, and lets the maintainer of the language under test
   choose which of Redis's tests count. The list should be written by the
   lead (or the auditor) before either build, from the rule already in the
   spec.
2. Elixir 1.17 in the spec; the erosion round and the Mac have 1.18 through
   `mise`. Trivial, but a sealed page should match the rig.
3. "The suite is the operation set's definition where the two disagree" and
   "anything else the suite wants is a failure, not a skip" are both good and
   will be expensive: the operation set is about 230 commands and
   subcommands. RC1's 2× is on top of a large absolute number for both.
4. The spec does not say which runtime (`mo run` or the binary) each measured
   number is taken under. The rules say binary for R7; the rest should be the
   binary too, said once.

## Reading

The spec is a fair and hard test of layer 1's surface and states its
deviations in advance. It is **not yet ready to build against**: the
persistence-test defect, the unnamed core operation (RC2), the undefined
recovery window and Elixir fault rig (R2), the two meanings of replay (R5),
and the skip list's author should each be settled by a row before a
maintainer starts, and the settled page re-published. None of these needs a
ratified threshold to change.
