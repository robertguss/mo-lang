# Independent TLS audit execution notes

Target: `64982b23b1dfed0bd0af3430125589da43058ac0`. Checks ran in a separate clone; no production edits. Live tools: Zig 0.16.0 (uv `ziglang==0.16.0`), OpenSSL 3.0.13, Python cryptography 41.0.7. Correctness checks only; concurrent load is not controlled for performance claims.

Commands from repository root unless otherwise noted:

```sh
zig test toolchain/src/bricks/tls.zig -lc
zig build --build-file toolchain/build.zig
zig build --build-file toolchain/build.zig tls-tools
zig build-lib toolchain/src/bricks/tls.zig -dynamic -lc -O ReleaseSafe -femit-bin=/tmp/libmo-audit-tls.so
python audit/evidence/2026-09-18/recent-tls-auditor/chain-checks.py
python toolchain/bench/step36/abuse.py
./toolchain/zig-out/bin/mo build examples/effects/tls-client.mo
python audit/evidence/2026-09-18/step-37/fable-probe/alert-probe.py toolchain/zig-out/bin/mo zig-out/mo-build/tls-client/tls-client
python toolchain/bench/step37/diff.py --seed 91837 --sessions 32
python toolchain/bench/step37/fuzz.py --seed 91837 --minutes .1
./toolchain/zig-out/bin/mo test examples/effects/tls-client.mo
./toolchain/zig-out/bin/mo fmt --check examples/effects/tls-client.mo
python audit/evidence/2026-09-18/recent-tls-auditor/fuzz-accounting-check.py
python audit/evidence/2026-09-18/recent-tls-auditor/example-assertion-check.py
```

The shared-library path is intentionally local and temporary; rebuild it from the pinned code before running `chain-checks.py`. Generated private keys remain in process memory and are not persisted. Certificate files are temporary and removed after each OpenSSL control. The script performs real in-memory production-engine handshakes, not fixture or socket handshakes.

From `examples/effects`:

```sh
python ../../audit/evidence/2026-09-18/step-37/fable-probe/server-alert-probe.py ../../toolchain/zig-out/bin/mo ../../zig-out/mo-build/tls-echo/tls-echo
```

The echo binary had already been built by the live abuse script. Both probe scripts were inspected before execution. The larger `probe37.py` was inspected but not executed; its public internet requests were not needed.

Native suite, builds, abuse, focused scripts, example tests and format commands returned 0. Expected failed client connections return 1 from the example; `client-alert.log` preserves those per-case exits. Empty build/format stdout is not itself the proof; the tool's actual exit codes were observed. No empty log is offered as evidence of a full project-suite pass.

Full-suite blocker: an initial background `timeout 1800 zig build test --summary all` produced no usable project log. A later foreground command used `timeout 580` with a requested 600-second tool budget. The transport instead returned `timed out after 420.0s`; no project summary or exit marker was written and no matching test process remained on inspection. These attempts are NOT successful test runs, and the transport failure cannot identify a failing project test. Historical suite counts in the reading come only from named checked-in logs.

`example-assertion-check.py` is a labelled temporary mutation: unconditional Timeout in `tried()`, unchanged test bodies, no generated verification footer. Its first execution retaining that footer was correctly refused with MO0317, so the final check explicitly removes the metadata from the new temporary file. This is not an attempt to forge a `verified:` line or to claim that the production example was modified.

`fuzz-accounting-check.py` uses mocked exits to test Python accounting. Its fake date/load and outputs are explicitly marked MOCKED. They do not claim a real parser crash. `fuzz-91837.txt`, by contrast, is an actual short native fuzz run, not the historical CPU-hour.

`inherited-diff-check.json` results from parsing all JSON lines of `audit/evidence/2026-09-18/step-37/worker-raw/step37/diff-3737.log`, constructing `diff.Params(**row['params'])`, and applying `diff.compare(params,row['mo'],row['openssl'])` to every row. This verifies internal record/count/comparator consistency; it does not independently repeat those 1,000 network sessions.
