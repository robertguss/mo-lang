# Step 41 (`Exec`), lead verification (3:33 PM ET)

Branch `lead/verify-step41` at `cdb36196` (`main`, the worker's
`toolchain/step-41-exec` at `ba7fa7ac`, base `853a27df`), pushed at `0b0f494b`
before the follow-up. One merge conflict, `toolchain/src/root.zig`: both import
lines kept (step 43's `number`, step 41's `exec_controls`).

- Darwin, at `0b0f494b`: `zig build` exit 0; `-Dtest-filter="step 41"` 6 of 6,
  exit 0; the full suite detached under `guard.py 2400` with another worker on
  the host: `Build Summary: 5/5 steps succeeded; 268/268 tests passed`, `run
  test 268 pass (268 total) 23m MaxRSS:450M`, exit 0 (`darwin-full-suite.log`,
  `darwin-exits.txt`). After the follow-up (`cdb36196`, a test and the report
  only): the focused tests again 6 of 6, exit 0
  (`darwin-focused-after-followup.log`). No orphaned test binary.
- Lead probes the brief did not name (`probe.mo.txt`, outputs identical under
  `mo run` and as a binary): a child that closes its pipes and sleeps past the
  deadline is `Timeout`; one argument of 256 KiB arrives whole and one of 3 MiB
  is `Failed("the arguments and environment are too long")`; an environment key
  holding `=` or empty is `Refused`; a leader that exits with a grandchild left
  behind answers `Exited(0)` at once and nothing survives; ten runs leave the
  child's descriptor count unchanged; 1 MiB of stdin to a child that never
  reads does not hang; `within: 0.ms` is `Timeout`.
- Linux, one run before Robert deferred Linux (VM, `0b0f494b`): build exit 0,
  focused tests 5 of 6 (`linux-focused-first-run.log`). The failure was the
  control's own predicate (`took > 0.ms`; a sub-millisecond run is `0.ms`), in
  the binary only; the other 41 lines, the fork child's included, were right
  in both runtimes. Fixed in `ba7fa7ac`. **The Linux rerun and full suite are
  owed** (decision log, 19 Sep, "Linux checks deferred").
