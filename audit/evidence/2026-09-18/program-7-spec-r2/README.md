# Evidence: program 7's spec, revision 2: Redis against its own suite

## Mac baseline (partial, historical)

Raw pointers, in the charter's form. The revision: mo-wiki/spec/programs/07b-redis-subset-revision-2.md; the sealed page it amends: mo-wiki/spec/programs/07-redis-subset.md.

- The script: redis-baseline.sh (Redis at tag 7.2.4 built from source, its runner in --host mode against that redis-server on port 7399, one spec-named file at a time, Tcl 9.0.4 from Homebrew, Robert's Mac, 18 Sep 2026, 12:02 to 12:18 PM ET).
- The logs, colour codes stripped: logs/rb-<file>.log, for the eight files that ran. (When the lead stopped the run and shut the server down, the script raced through the other 17 files against no server; those logs measured nothing and are not kept.)
- **The run is partial.** Eight of the 25 files ran. The lead stopped it at 12:18 PM ET: unit/type/stream had sat for fourteen minutes in a test that starts its own server with an append-only file ("Empty stream can be rewritten into AOF correctly", stream.tcl line 906), which is the same external-mode problem revision 2 section 1 is about, met in a file the spec keeps. The remaining 17 files, and these eight again, are to be run on the Linux rig before the skip list is written; this bundle is updated then with an evidence-updated record.

| file | [ok] | [err] | [ignore] | exception |
|---|---|---|---|---|
| unit/type/string | 81 | 0 | 0 | no |
| unit/type/incr | 32 | 0 | 0 | no |
| unit/type/hash | 72 | 0 | 0 | no |
| unit/type/list | 273 | 0 | 6 | no |
| unit/type/list-2 | 2 | 0 | 0 | no |
| unit/type/list-3 | 11 | 0 | 0 | no |
| unit/type/set | 107 | 0 | 0 | yes |
| unit/type/stream | 71 before it hung; stopped by the lead | 0 | 0 | the interrupt's |

Two things the partial run already shows, as raw facts: unit/type/set ends in an exception after 107 passing tests, and unit/type/stream does not finish, both against Redis 7.2.4 itself in --host mode. So "the suite's counts" for a server the runner did not start are below the files' test counts even for Redis, and the ceiling per file has to be measured, not assumed.

Not opened by this bundle: any hidden suite (none exists yet).

## Linux baseline, 18 Sep 2026

Recorded by Codex (GPT-6), the lead, at 3:40 PM ET. The existing run finished
at **3:34:59 PM ET**, having started its measured files at **3:02:59 PM ET**.
All 22 files retained by revision 2 were attempted. This is Linux in OrbStack
on Robert's Mac, **not the destination cloud VM**: Debian 12, Linux
7.0.14-orbstack-00380-ga7e0a2dc9535 aarch64, Tcl 8.6.13, Redis 7.2.4
(`d2c8a4b91e8c0e6aefd1f5bc0bf582cddbe046b7`).

- Script, unchanged from the run: `redis-baseline-linux.sh`.
- Raw summary: `linux/baseline.txt`; full per-file output: `linux/rb-*.log`;
  build output: `linux/make.log`. The pane printed `make exit=0` and
  `BASELINE-LINUX-DONE`.
- Counts as printed: **909 ok, 5 err, 22 ignored, 3 exceptions**; three
  files timed out at 600 seconds. Six files exited 1, three exited 124,
  thirteen exited 0. The first eight files had **650** ok, not the Mac's
  649 (`unit/type/string` is 82 on Linux and 81 on the Mac).

| file | exit | seconds | ok | err | ignored | exception |
|---|---:|---:|---:|---:|---:|---:|
| unit/type/string | 0 | 7 | 82 | 0 | 0 | 0 |
| unit/type/incr | 0 | 0 | 32 | 0 | 0 | 0 |
| unit/type/hash | 0 | 1 | 72 | 0 | 0 | 0 |
| unit/type/list | 0 | 11 | 273 | 0 | 6 | 0 |
| unit/type/list-2 | 0 | 4 | 2 | 0 | 0 | 0 |
| unit/type/list-3 | 0 | 39 | 11 | 0 | 0 | 0 |
| unit/type/set | 1 | 3 | 107 | 0 | 0 | 1 |
| unit/type/stream | 124 | 600 | 71 | 0 | 0 | 0 |
| unit/expire | 124 | 600 | 36 | 0 | 1 | 0 |
| unit/keyspace | 1 | 1 | 54 | 1 | 0 | 0 |
| unit/scan | 1 | 4 | 19 | 2 | 0 | 0 |
| unit/multi | 124 | 600 | 34 | 0 | 0 | 0 |
| unit/pubsub | 0 | 0 | 34 | 0 | 0 | 0 |
| unit/auth | 0 | 0 | 0 | 0 | 3 | 0 |
| unit/acl | 0 | 0 | 0 | 0 | 8 | 0 |
| unit/acl-v2 | 0 | 1 | 0 | 0 | 2 | 0 |
| unit/info | 0 | 0 | 0 | 0 | 1 | 0 |
| unit/introspection | 1 | 0 | 6 | 0 | 0 | 1 |
| unit/introspection-2 | 1 | 7 | 44 | 2 | 0 | 0 |
| unit/other | 1 | 40 | 7 | 0 | 1 | 1 |
| unit/protocol | 0 | 1 | 25 | 0 | 0 | 0 |
| unit/tls | 0 | 0 | 0 | 0 | 0 | 0 |

### Limits of this evidence

The script reuses one Redis server, flushes its keys between files, and restarts
it only if `PING` fails. It does not reset its configuration or wait for all
background work to finish after a timed-out file. `unit/introspection` and
`unit/other` both end with “Another child process is active (AOF?)”. These
failures therefore cannot yet justify permanent external-server skips; rerun
them with a fresh server per file on the destination rig first.

`unit/type/set` ends with the missing `pid` dictionary key. `stream`, `expire`,
and `multi` time out; their ok counts are partial. `auth`, `acl`, `acl-v2`, and
`info` print only ignored tests; `tls` prints no executed tests. A zero exit
with zero tests is no TLS, auth, ACL, or INFO coverage. The five assertion
failures and every timeout remain visible in the raw logs.

The lead's skip-list page and executable skip file remain **unwritten**; this
run is preserved for handoff, not presented as a finalized denominator.
No hidden suite or auditor reading was opened for this update.
