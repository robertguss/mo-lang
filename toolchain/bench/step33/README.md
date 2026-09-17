# Step 33's measurements

The tools behind step 33's numbers (`mo-wiki/plans/interpreter-step-33.md`), kept so they can be run
again. Every server ran under a timeout and a 4 GB memory watchdog (`guard.py SECONDS -- cmd`, or the
watchdog inside each script). The program is the change 3 jobq of the Mo maintainer
(`../mo-lang-erosion3-mo/examples/programs/jobq`, copied with its `mo.root` and `.mo.ids` so this
repo's `mo` builds it).

- `restartmem.py run|bin N ROUNDS`: a log of N jobs, `serve --crash-every 1 --max-restarts 1000`, then
  ROUNDS times a create (which fails the queue) and `/health` until `restarts` goes up: resident memory
  before, after the first restart, and after the last, the growth per restart, the time of one restart
  (from the create to the `/health` that counts it, the report written to a file included), and the
  bytes of stderr. `VMMAP=1` prints `vmmap --summary` at the end (how part A found macOS's
  `MALLOC_LARGE (empty)` holding the freed reports).
- `reopen.py MO SECONDS`: eight clients create for SECONDS on a plain folder, the service is stopped
  and started again: part B's abort without the RAM disk (about 8,000 jobs were enough).
- `kvrss.py MO KV_MAIN`: kv's resident KiB after 50,000 SETs, the bench's `kv-50k-set-rss-kib` row alone.

## Numbers

Taken on 16 Sep 2026 on an Apple M-series Mac. Before is `mo` built at `42323b3` (part B, so the
interpreter can open the logs; part A not yet) and the change 3 binary built by it; after is `a7d42a4`.
Best of five, interleaved.

| | before | after |
|---|---|---|
| growth a restart, 20,000 jobs, 30 restarts, binary | 46.1 MiB | 0.27 MiB |
| growth a restart, 20,000 jobs, 30 restarts, `mo run` | 27.95 MiB | 0.00 MiB |
| resident after 30 restarts, 20,000 jobs, binary / `mo run` | 1,412 / 902 MiB | 37 / 64 MiB |
| growth a restart, 100,000 jobs, 5 restarts, binary / `mo run` (the first restart included) | 270.5 / 162.7 MiB | 10.3 / 4.6 MiB |
| resident after the 1st and after 15 restarts, 100,000 jobs, binary | | 163 / 165 MiB |
| resident after the 1st and after 15 restarts, 100,000 jobs, `mo run` | | 224 / 240 MiB, flat from the 9th |
| one restart, 20,000 jobs, binary / `mo run` | 0.261 / 0.905 s | 0.266 / 0.905 s |
| one restart, 100,000 jobs, binary / `mo run` | 1.408 / 4.94 s | 1.447 / 4.91 s |
| stderr a crash, 20,000 / 100,000 jobs | 26.8 / 140 MiB | the same |
| P6, four `"bad queue"` creates through the surface, `/memory` resident after, binary / `mo run` | 111.5 / 108.7 MiB | 45.5 / 92.7 MiB |
| `kv-50k-set-rss-kib`, `mo run`, three runs each | 340,560 KiB | 340,576 KiB |

At 100,000 jobs what stays past the first restart is the queue's region settling (it alternates between
two sizes from one restart to the next and stops growing by the ninth), not the reports. The restart
time is the queue's replay of its log plus writing its report, which is the state twice: the invariant's
value is the state after the batch and the report's snapshot the state before it, two values.

## Part C's runs

On the change 3 program with `a7d42a4`'s `mo`, under `mo run` and as the binary it built:

| suite | `mo run` | binary |
|---|---|---|
| `defects2.py --only unwritable` (the RAM disk filled and freed, then a stop and start) | 8 of 8 (the abort gone) | 8 of 8 |
| `defects3.py --only restart` | 14 of 14 | 14 of 14 |
| `defects3.py --only budget` | 9 of 9 | 9 of 9 |
| P6, four kills at 2.0, 3.5, 5.0, 6.5 s, `/health` 200 again after each | 444, 839, 986, 1,166 ms | 109, 185, 255, 328 ms |
| P6, acknowledged writes lost after the stop and start | 0 of 14,994 | 0 of 26,863 |
