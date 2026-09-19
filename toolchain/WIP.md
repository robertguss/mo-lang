# Step 42 WIP (paused by the lead, 19 Sep 2026)

Branch `toolchain/step-42-memory`, base `2f669902`. Worker: Claude Opus 5.

## Done

- `zig build` exit 0 at base (43 s, load average about 17).
- **Part E, the guard.** RED committed first (`c961cc7f`):
  `bench/step42/guard_test.py` runs a child that starts a grandchild ignoring
  TERM and INT. Before the fix the grandchild survived the timeout, the
  forwarded TERM and the forwarded INT (`bench/step42/guard-red.log`, exit 1).
  GREEN is in this WIP commit: `bench/step36/guard.py` now starts the child with
  `start_new_session=True`. It kills the whole group (`killpg`) on timeout or
  the memory limit and forwards TERM and INT to the group. After a forwarded
  signal it SIGKILLs what is left of the group once the child ends. Exit
  statuses and messages are unchanged. `bench/step42/guard-green.log` shows all
  three cases hold, exit 0. Two decisions to record in the report: the RSS limit
  still reads the direct child only, and a normal exit does not kill leftovers.

## Not started (Parts A to D)

The plan, from reading the code:

- **A, the C switch.** In `mo_rt.h:244`, replace the `MO_*_BUDGET` macros with
  globals (`mo_frame_budget`, `mo_loop_budget`, `mo_walk_budget`) that default
  to 0 under `-DMO_STRESS`. `mo_program_start` (`mo_rt.c` about 12351) sets them
  from `getenv("MO_STRESS")` before the threads start. Then measure the hot-path
  cost. Align `fold_step` (`mo_rt.c:2024`): with a budget of 0, C still uses
  `old/4`, but Zig uses 0 (`vm.zig:778`).
- **A, the Zig switch.** Add `pub var stress` to `region.zig`, set by `main.zig`
  from `MO_STRESS` for `mo run` and `mo test`. `Vm.useRegions` (`vm.zig:206`)
  sets the three budgets to 0 when it is on, and `sim.compactRegion`
  (`sim.zig:1200`) uses 0 for `full_budget`. Tests do not compact in either
  runtime (no regions; `mo_compacts` false), so stress does nothing under
  `mo test`. Say so in the report.
- **A, the sweep.** Add a new corpus.zig test named to be filterable, e.g.
  `corpus: step 42, every program under MO_STRESS ...`. For each `isRunnable`
  file (34 of them), `mo run` and the `mo build` binary run with `MO_STRESS=1`,
  and their stdout and exit must equal the `.expected` files. Commit its first
  output as RED.
- **B, poison.** In `vm.zig` compact (about line 846) and `mo_rt.c` `mo_compact`
  (line 804): when stress is on, fill `[new top, old_top)` and the scratch
  region's used range with `0xA5`. `releasePast` maps fresh zero pages; under
  poison, make it a no-op so the poison stays. Add an ASan variant with
  `ASAN_POISON_MEMORY_REGION`. For the mutant, restore the raw `PendingAnswer`
  value (`sim.zig:452` `answerReply`, `mo_rt.c` about 5857 `mo_answer`) behind a
  switch and show that it is caught at n = 10.
- **C, the audit table, and `blocking.run`.** For `blocking.run` (step 30's
  pool), guard it as `blocking.alone` does: wait for the job if `block` errors
  (`src/blocking.zig`).
- **D, the Parcel-only field types.**

## Exact next command

    cd toolchain && python3 bench/step36/guard.py 1200 -- zig build

Then start Part A's C switch in `runtime/mo_rt.h:244`.

## Surprising

- A survivor keeps any pipe it inherited open, so `cmd | tee` under the old
  guard hung after the kill. The first RED run hung for this reason: the
  orphaned grandchild held tee's pipe. The test now sends the guard's stderr to
  a file.
- `-DMO_STRESS` in C does not make `fold_step` compact at every step, as noted
  above.
