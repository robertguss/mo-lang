# Native toolchain baseline — 19 Sep 2026

Lead-controlled commands on the Mac before the terminal-auth code was
integrated. Mo/compiler source was unchanged from ff669fd; intervening commits
were documentation only. All test commands ran in owned Herdr panes under the
repository guard. No historical auditor or hidden suite was opened.

- `run.py`, `build.*`, `test.*`: `zig build -j2` passed. The first full suite
  hit the 300-second guard at 12:29 AM ET, exit 137, while compiling examples.
  The guard controls only its direct child. `test.process-group.json` and
  `test.cleanup.json` retain the lead's owned-descendant observation and cleanup;
  no remaining process was found afterward.
- `run-longer.py`, `test-longer.*`: separate 1200-second attempt, started
  12:32:41 AM and finished 12:39:21 AM ET, exit 0. It reported 5/5 build steps
  and 243/243 tests passed. Progress snapshots show example compilation. Both
  cleanup-before and cleanup-after lists were empty.

The two scripts and failed attempt are preserved. These are native baseline
checks, not Step 39 acceptance, Darwin full-sync evidence or an executor test.
Lead's later integrated auth result is in `../agent-terminal-auth/`; that
subsequent run initially failed and must not be conflated with this baseline.
