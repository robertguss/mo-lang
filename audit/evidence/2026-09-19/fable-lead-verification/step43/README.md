# Step 43, lead verification (1:59 PM ET)

Branch `lead/verify-step43` at `4ad89c1a` (`main` plus the worker's
`toolchain/step-43-numbers` at `7e29e119`, base `d85154cf`), pushed.

- Darwin (M3 Max), in its own worktree, detached under `guard.py 2400`, load
  average about 12 (two other workers on the host): `zig build` exit 0;
  `zig build test --summary all`: `Build Summary: 5/5 steps succeeded; 263/263
  tests passed`, `run test 263 pass (263 total) 11m MaxRSS:460M`, exit 0
  (`darwin-full-suite.log`, `darwin-exits.txt`). No orphaned test binary of
  this worktree afterwards.
- Linux x86_64 on Robert's VM, clone `~/Projects/mo-lang-lead-verify` at
  `4ad89c1a`: build exit 0; `zig build test -Dtest-filter=number:`:
  `5/5 steps succeeded; 15/15 tests passed`, exit 0 (`linux-focused-tests.log`).
  The Linux full suite was still running at acceptance (about 35 minutes on
  that machine); its result is added below when it ends.
- Lead probes the brief did not name (`*.mo`, `results.json`; `check`, `run`,
  `build` and the native binary, each under the guard): an out-of-range literal
  inside a typed list, as an argument, in a `case` arm, `Int64` one past,
  `106751991168.days`: all `MO0217`, exit 1, in every mode. Controls:
  `Int64`'s largest and its negation, `106751991167.days`, a list of
  `[0, 255, 0_0_7]` run the same in both runtimes; `200 + 100` as `UInt8`
  exits 70 with the overflow message in both. `hex.mo` and `exp-float.mo` are
  parse errors: Mo has no such literals.
- The lead read the whole diff of `check.zig` and `number.zig`.

## The Linux full suite (2:07 PM ET)

On the VM at `4ad89c1a`, detached under `guard.py 3600`: `Build Summary: 5/5 steps
succeeded; 263/263 tests passed`, `run test 263 pass (263 total) 18m
MaxRSS:455M`, exit 0 (`linux-full-suite.log`, `linux-exits.txt`). No test binary
left running.
