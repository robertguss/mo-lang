# Step 24's measurements

The tools behind step 24's numbers (`mo-wiki/plans/interpreter-step-24.md`), kept so they can be run
again. Every server and probe ran under a timeout and a 4 GB memory watchdog.

- `nums.py SP REPO ROUNDS ROW...`: before (the step's first commit, `195dd88`) and after, interleaved,
  best of ROUNDS: `kv` and `kv-c` (10,000 GETs over one socket to kv under `mo run` and as a binary),
  `http` and `http-c` (1,000 `GET /hello` to httpd, a connection each), `jobq` (lease-and-ack pairs a
  second with 32 workers against the binary, `bench/step23/jqload.c`, 50,000 jobs made first), and
  `agent` (five-step runs a second with 32 concurrent runs against the binary and its scripted model,
  `examples/programs/agent/measure/bench.py rate`). Its docstring says how the trees are laid out.
- `hold.mo`: a registry whose state holds 10,000 workers' handles: the live process count and the
  surface's memory row while it holds them, and the count once it drops them and a start from main
  sweeps. Run under `mo run`, and as a binary built with `--surface`.
- `lag.mo`: twenty 100 ms delayed sends in a row, each timed on `clock.now` by the update that takes
  it: the mean and worst lag past 100 ms, under `mo run` and as a binary.

## Numbers

Taken on 14 Sep 2026 on an Apple M-series machine. Before is `195dd88` and after is the tree part E was committed from, both measured with ReleaseSafe `mo` and native binaries, interleaved, best of five.

| row | before | after | change |
|---|---|---|---|
| `kv-10k-get` (mo run) | 425.6 ms | 429.1 ms | 0.8% slower |
| `kv-10k-get-c` (binary) | 214.8 ms | 217.2 ms | 1.1% slower |
| `http-1k` (mo run) | 68.3 ms | 67.7 ms | 0.9% faster |
| `http-1k-c` (binary) | 66.1 ms | 59.8 ms | 9.6% faster (noisy: rounds ran from 59.8 to 123 ms) |
| jobq, 32 workers (binary) | 4,450 pairs/s | 4,299 pairs/s | 3.4% slower, in every round (4,199–4,299 after, 4,256–4,450 before) |
| agent, 32 concurrent runs (binary) | 443.9 runs/s | 443.5 runs/s | 0.1% slower |

No row is more than 5 percent slower. jobq's is the largest: every turn of main's thread now also looks for delayed sends that are due, and every sweep reads the processes' states.

A registry holding 10,000 workers' handles in its state (`hold.mo`): 10,001 live processes. Under `mo run` the surface reports 26.5 MiB resident, with the regions holding 7.7 MiB, and 28.1 MiB at most. As a binary built with `--surface`, 53.0 MiB resident, with the regions holding 2.8 MiB, and 54.0 MiB at most. Once the registry drops its map and a start from main sweeps, 2 processes are live in both runtimes.

The delivery lag of a 100 ms delayed send, twenty in a row (`lag.mo`), measured on `clock.now` to the millisecond:

- `mo run`: 1 ms on average, 2 ms at worst.
- Binary: 1 ms on average, 3 ms at worst.
