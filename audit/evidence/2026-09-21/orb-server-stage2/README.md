# Server part-A independent correctness checkpoint

Lead reading; open after your own. Recorded 21 Sep 2026, 12:22 AM ET.

These are lead-executed Linux checks, not copied worker verdicts. Stage2 ran in
`/tmp/mo-lead-orb-server` at the exact integration in `revision.txt`: worker
ef09dc3126275fe6ad57429c72fe1989038b4007, regenerated metadata and accepted main
wrapper infrastructure. The full-corpus run preceded that infrastructure merge;
the server/runtime source was unchanged. It printed 278/278, exit 0. Its elapsed
time is not an equivalent-suite performance comparison.

Commands: outer
`python3 toolchain/bench/step36/guard.py 600 -- python3 examples/programs/workspace-server/<script>.py`,
preserving existing internal guards. `verify.py --kind build` passed 3
executables. For each `--runtime run` and `--runtime binary`,
`unchanged_client_green.py` passed 5 tools/5 calls, `hostile_server.py` passed
14 and `hostile_fs.py` passed 14. `request_controls.py` passed 2 and
`eof_controls.py` passed 3 using either `--binary` or `--target` with the direct
guard, `mo run double.mo --`. `behaviour.py` passed the exact 11 groups printed
in each log, without half-close changes. `size_table.py` ran under a 30-second
outer guard and counted 15 modules. Every adjacent exit is 0.

Full command: from toolchain, guarded `zig build test-corpus --summary all`. The
log's expected negative diagnostics are retained. Actual final summary and exit,
not diagnostic substrings, determine the result. A post-run process listing
found no surviving matching server/build/control processes; this is not a
general proof of nested-guard safety.

Oracle found no production correctness blocker after these remaining checks.
Part-A remains unmerged pending its measurement protocol: benchmark startup can
escape cleanup, and nested guard groups can leave Mo alive after outer cleanup.
Source-only correction is assigned; no measurements authorized. Removing inner
guards also removes per-Mo RSS sampling, an unresolved execution constraint. F1
historical source remains unavailable. F3 is the explicit temporary whole-run Fs
trust exception, not capability isolation. Two inherited Python lifecycle
predicates remain excluded. Part B is not accepted.

Worker archive independently inspected: stage1-2-ef09dc31.tar.gz, SHA-256
a344e772557369c77a1df591fc5265963958b238deb9052d3db49e1f79f65425. Its unguarded
--help invocations executed scripts and are excluded from evidence.
