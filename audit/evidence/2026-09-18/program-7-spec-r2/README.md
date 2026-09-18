# Evidence: program 7's spec, revision 2: what Redis's own suite does against Redis itself (partial)

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
