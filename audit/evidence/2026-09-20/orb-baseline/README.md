# Fresh x86_64 Linux baseline

Lead ran the unchanged compiler/runtime from arrival9111bb70 with the accepted
guard integrated, in `/tmp/mo-lead-orb-baseline`. Exact verification revision:
05285b52247d8afc3cee5811cd336f66eedbab58 (`revision.txt`). Code matches main's
accepted guard merge70c07d32; verification merge history differs. No recovered
server or Step42 A–D code is in this baseline.

Zig0.16.0, x86_64 Linux orb,16 visible CPUs,31GiB RAM. Build jobs capped at4; no
MO_CORES override. Initial load0.03/0.03/0.00. Commands from `toolchain/`:

```
/usr/bin/time -p python3 bench/step36/guard.py 600 -- zig build -j4 --summary all
/usr/bin/time -p python3 bench/step36/guard.py 2400 -- zig build test-corpus -j4 --summary all
```

Output was captured through `tee` with `pipefail`; each adjacent `.exit` records
the timed command's actual status via PIPESTATUS. Build:5/5 steps,exit0,
real114.90s. Full native-enabled suite:276/276 tests,5/5 steps,exit0,
real567.78s. These are single readiness runs, not best-of-five benchmarks.

The raw suite output includes expected fault/kill diagnostics and a
`failed command:` line before Zig's successful final summary. Both the actual
process status and final276/276 summary are preserved; no output was suppressed
or rewritten. Platform coverage includes the suite's Linux Exec and filesystem
controls, not the historical OrbStack machine or Darwin full-sync obligation.

The verification worktree remained clean. A post-run process-name scan showed no
live mo/zig/test/guard processes (dbus-daemon was a substring match only). No
Docker daemon, machine service, provider login or CI was started.
