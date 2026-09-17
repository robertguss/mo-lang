# Evidence pointers, 17 Sep 2026, afternoon and evening

Raw pointers for an audit session, in the charter's form: paths, branches,
commits, and outputs as the machines printed them. Fable's readings of these
subjects are in the decision log and on the plan pages named here; per the
charter the auditor reads the raw evidence first and Fable's reading after.

## What landed, by commit on `main`

| commit | what | raw evidence |
|---|---|---|
| `9dce71b` | the bricks page (the shelf boundary, the cost against Zig's `std`, five audit items, a cap per brick) | `mo-wiki/deep-dives/bricks-and-the-cost-of-zero-dependencies.md` |
| `3a13fca` | step 35's brief, sealed before the worker started | `mo-wiki/plans/interpreter-step-35.md` (the parts, numbers, and Done-when as written before the work) |
| `ead3f81`, `18c6457`, `9092565` | step 35 parts A, B, C by one Opus session on the VM, 15:50 to 17:56 UTC | `toolchain/src/bricks/crypto.zig` (the brick and its vectors), `toolchain/src/crypto_rows.zig`, `toolchain/runtime/mo_rt.c` (search `mo_crypto_`), `examples/basics/{hash,aead,sign}-vectors.mo`, `examples/effects/{password,random-fixture}.mo`, `toolchain/bench/step35/` (`diff.py`, `fuzz.py`, `measure.py`, `RESULTS.md` with the worker's raw tables) |
| `df39329`, `fed950f` | the lead's acceptance and its verification | `audit/evidence/2026-09-17/step35-fable-probe/`: `gen.py` (the inputs, seed 11, from python's `cryptography`), `run.out` and `bin.out` (the Mo program's 29 lines under `mo run` and as a binary), `expected.json`, `check.py` (the comparison; its output is in `run.log`), `zig-build-test.log`, `fuzz-hour.log` (seed 1701, 60 min) |
| `a8d3449`, `4f237d0` | step 36's brief (the TLS brick, part one), sealed before its worker started 19:27 UTC | `mo-wiki/plans/interpreter-step-36.md` |
| `854a815` | the probe naming the cause of generation four's speed loss | `audit/evidence/2026-09-17/gen4-speed-probe/`: `run.log` (`measure.py` at 30,000 jobs on both queues, contracts on and off, and `perf report` for each), `surface3.slowest` and `surface4.slowest` (the runtime surface's `/slowest` and `/memory` every 4 s during the run), the scripts that produced them; the program under test is branch `erosion4-mo`, file `examples/programs/jobq/board.mo`, function `sweep` (line 381 to 383) and `decide` (line 158 to 159), against branch `erosion3-mo`'s `sweep` (line 247 to 249) |

## How to reproduce on the VM

- Step 35's differential run: `cd toolchain/bench/step35 && uv run diff.py --n 1000 --seed 35` (the venv holds `cryptography` only). The fuzz: `uv run fuzz.py --minutes 10 --seed 35`.
- The lead's probe: `python3 gen.py <seed> <dir>` writes `probe.mo` and `expected.json`; `run.sh` runs it under both runtimes; `python3 check.py expected.json run.out`.
- The speed probe: `git worktree add ../mo-lang-erosion3-mo erosion3-mo` and the same for 4; `build.sh`; `run.sh` (perf at `/usr/lib/linux-tools-6.8.0-139/perf`); `surface.sh`.

## Where the two readings will meet

The rows of 17 Sep in `mo-wiki/decisions/decision-log.md` marked "for Robert": step 35's acceptance row, the row on generation four's cause (19:25 UTC), and step 36's two design rows. The auditor's file on any of these subjects goes beside this folder as `audit/mo-audit-2026-09-17-<subject>.md`; Fable's parallel reading, if one is asked for, as `audit/fable-reading-<date>-<subject>.md`.
