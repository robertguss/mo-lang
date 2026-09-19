# Lead probes for the 19 Sep repository reading

Run by the Fable lead on Darwin (M3 Max), `main` at `2f61e839ce2d307f9d84d9026402f55e34e7c64d`, `mo` from
`toolchain/zig-out/bin/mo` (built 11:10 AM ET from the tree that holds step 40),
every process under `toolchain/bench/step36/guard.py 120`, load average 5.5
(two Opus workers on the host). `probe.py` runs `check`, `run`, `build` and
the native binary for each program; `results.json` is its output as printed.
Four programs are the auditor's own raw probes, copied unchanged from
`origin/audit/2026-09-19-repo` at `c64fec29` into a scratch folder
(`leading-zero`, `oversized`, `neg-duration`, `mailbox-overflow`); the six
here are the lead's. The lead's reading: `audit/fable-reading-2026-09-19-repo.md`
(open after your own).
