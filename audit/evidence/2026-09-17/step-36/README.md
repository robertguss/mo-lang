# Evidence, step 36: the TLS brick, part one (a TLS 1.3 server in both runtimes)

Raw pointers for an audit session, in the charter's form. The lead's verification is in
progress; this folder is committed as it fills so nothing waits on a single push.

- **Brief, sealed before the worker started (19:27 UTC / 3:27 PM ET):** `mo-wiki/plans/interpreter-step-36.md` at `a8d3449` (tag fix `4f237d0`).
- **Worker commits:** `9c753e1` (part A, the brick `toolchain/src/bricks/tls.zig`, 2,077 lines, with its in-memory tests), `dd2e385` (part B, the rows in both runtimes: `toolchain/src/tls_rows.zig` or wherever the diff of that commit puts them, `toolchain/runtime/mo_rt.c`, the spec's `## Tls`), `4cb0fc8` (part C, `examples/effects/tls-echo.mo`, `examples/effects/tls/*.pem`, `toolchain/bench/step36/`).
- **Worker's raw outputs** (copied unchanged from `toolchain/bench/step36/work/` after its run): `worker-raw/handshake.txt`, `bulk.txt`, `idle.txt`, `abuse.txt`, `done.txt`; `worker-raw/worker-report-pane.txt` is the worker's terminal as the lead saved it, including its "Decisions the brief did not cover".
- **Lead's probe:** `fable-probe/probe.py` (cases the brief did not name, driven by openssl s_client and Python's ssl against the example echo under both runtimes); its output `fable-probe/probe.log` and the suite log `fable-probe/zig-build-test.log` are added when the runs finish.
- **Load before the runs:** the machine was quiet (load average 0.38 at 6:48 PM ET, after the orphan of the afternoon was killed; see `../README.md`).
