# Step 34's numbers (16 Sep 2026, Robert's M3 Max: 14 cores, 10 performance and 4 efficiency)

Best of five unless marked. `run` is `mo run`; `bin` is a `mo build` binary. `A`
is part A's `mo` (placement with the starter, before part B). `14s` is 14 cores
with `MO_PLACE=spread`. Every `mo` process ran under `guard.py` or
`ledger_probe.py` (a watchdog at 4 GB).

## Network rows (`mo-bench --network`, ms, run / bin)

| row          | 1 core      | 4 cores     | 14 cores    | 14s         | A, 1 core   | A, 14 cores   |
| ------------ | ----------- | ----------- | ----------- | ----------- | ----------- | ------------- |
| `echo-1k`    | 24.4 / 27.2 | 33.6 / 36.3 | 35.0 / 37.9 | 29.6 / 35.4 | 20.4 / 26.7 | 83.6 / 84.9   |
| `kv-10k-get` | 428 / 212   | 434 / 256   | 441 / 257   | 444 / 258   | 396 / 212   | 1,249 / 1,043 |
| `http-1k`    | 57.6 / 55.1 | 60.2 / 58.6 | 63.3 / 59.2 | 63.6 / 60.4 | 64.3 / 57.0 | 70.2 / 67.1   |

## Services

The change 4 queue (`../mo-lang-erosion4-mo`, `jobq_measure.py`). The final
build is best of three; the other columns are best of five, measured before the
sweep fix.

| row                                              | 1 core      | 4 cores     | 14 cores    | 14s         |
| ------------------------------------------------ | ----------- | ----------- | ----------- | ----------- |
| creates a second, bin (final)                    | 8,367       | 7,254       | 6,278       | 6,066       |
| pairs a second at 32 workers, bin (final)        | 456         | 453         | 444         | 445         |
| pairs a second at 1 worker, bin (final)          | 734         | 709         | 696         | 689         |
| creates / pairs at 32, bin, before the sweep fix | 8,324 / 456 | 7,253 / 457 | 6,294 / 448 | 6,190 / 450 |
| creates / pairs at 32, run                       | 5,715 / 195 | 5,437 / 203 | 5,276 / 206 | 5,232 / 206 |
| creates / pairs at 32, bin A                     | 8,385 / 456 | 7,253 / 464 | 5,349 / 451 | 5,176 / 454 |

The ledger (`ledger_probe.py`: 100,000 transfers from 32 clients, transfers a
second, with peak memory).

| row                       | 1 core         | 4 cores        | 14 cores       | 14s            |
| ------------------------- | -------------- | -------------- | -------------- | -------------- |
| bin (final, best of 3)    | 4,819, 248 MiB | 4,814, 251 MiB | 4,347, 248 MiB | 4,321, 248 MiB |
| bin, before the sweep fix | 4,814          | 4,719          | 4,356          | 4,323          |
| run, before the sweep fix | 659, 591 MiB   | 651, 718 MiB   | 646, 797 MiB   | 640, 776 MiB   |

The ledger under `mo run` makes 650 transfers a second at 1 core with part A's
`mo` too (152.5 s against 153.6), and each tenth of the load costs more than the
one before: 9.3 s, then 10, then 11.5, and up to 20. A sample late in the run
finds `vm.Vm.compact` in 2,260 of the busy samples, most of them in
`copySlice`'s forwarding-table lookup, and the run allocates 114 GB. That is
step 33's carried compaction cost, not step 34's.

## Processes (ms unless marked, run / bin)

| row                                      | 1 core              | 4 cores              | 14 cores            | 14s                 |
| ---------------------------------------- | ------------------- | -------------------- | ------------------- | ------------------- |
| 100k asks, one scheduler                 | 80 / 72             | 83 / 74              | 82 / 74             | 149 / 138           |
| 100k asks, two schedulers                | 80 / 72             | 153 / 139            | 151 / 140           | 152 / 140           |
| 8 crunchers (run 2M rounds, bin 20M)     | 1,307 / 511         | 344 / 141            | 179 / 85            | 181 / 85            |
| 200,000 short-lived processes, s and MiB | 8.65, 90 / 8.39, 16 | 1.79, 108 / 1.92, 16 | 3.13, 72 / 4.95, 16 | 3.37, 70 / 6.29, 16 |
| the same, bin A, s                       | 8.71                | 5.50                 | 5.46                | 6.92                |
| the same, step 33's `mo`, s and MiB      | 8.97, 90 / 8.81, 16 |                      | 5.84, 48 / 6.65, 16 |                     |

Before part B, 100,000 asks across two schedulers took 3.1 to 5.6 s under
`mo run` and 4.2 to 6.6 s as a binary.

## The deferred reply (10,000 asks, ms, reply / send)

| askers     | 1 core  | 4 cores | 14 cores | 14s      |
| ---------- | ------- | ------- | -------- | -------- |
| 8, run     | 29 / 30 | 31 / 46 | 41 / 61  | 42 / 61  |
| 8, bin     | 26 / 31 | 30 / 45 | 38 / 65  | 39 / 66  |
| 8, run A   | 29 / 29 | 70 / 70 | 90 / 135 | 91 / 135 |
| 128, run   | 64 / 38 | 43 / 32 | 62 / 65  | 62 / 65  |
| 128, bin   | 20 / 19 | 21 / 30 | 46 / 71  | 47 / 69  |
| 128, run A | 65 / 38 | 45 / 33 | 61 / 54  | 61 / 55  |

A parked fiber at rest (10,000 held asks against the send shape, peak resident,
1 core): about 24 KiB each under `mo run` (8,052 against 7,811 MiB) and 7.5 KiB
in a binary (376 against 303 MiB).

## `MO_STATS=1`, the queue at 14 cores (bin, final)

```
mo stats: scheduler 0 placed 5845 with_starter 0 live 1 asks_across 5844
mo stats: scheduler 1 placed 5829 with_starter 0 live 1 asks_across 0
mo stats: scheduler 2 placed 17518 with_starter 17517 live 4 asks_across 17517
mo stats: scheduler 3 placed 10555 with_starter 0 live 1 asks_across 10555
mo stats: scheduler 4 placed 10532 with_starter 0 live 1 asks_across 10532
mo stats: scheduler 5 placed 10488 with_starter 0 live 1 asks_across 10488
mo stats: scheduler 6 placed 10299 with_starter 0 live 1 asks_across 10299
mo stats: scheduler 7 placed 9823 with_starter 0 live 1 asks_across 9823
mo stats: scheduler 8 placed 8975 with_starter 0 live 1 asks_across 8975
mo stats: scheduler 9 placed 7853 with_starter 0 live 1 asks_across 7853
mo stats: scheduler 10 placed 6857 with_starter 0 live 1 asks_across 6857
mo stats: scheduler 11 placed 6263 with_starter 0 live 1 asks_across 6263
mo stats: scheduler 12 placed 5864 with_starter 0 live 1 asks_across 5864
mo stats: scheduler 13 placed 5853 with_starter 0 live 1 asks_across 5853
```

The queue (scheduler 1) asks nothing across. The acceptor (scheduler 2) keeps
17,517 of its workers. The other workers go where the fewest live, since the
share is one process a scheduler. Every worker asks the queue, which `main`
started, so every create crosses. With `MO_PLACE=spread`, no scheduler keeps any
worker (with_starter 0 on every line).

The same lines for kv at 14 cores (bin): the journal, the store, the gate and
the listener land on schedulers 0 to 3, and the worker lands with the listener
on 3, which asks across 10,001 times. For echo: the acceptor and its worker are
on scheduler 0, and the client is on scheduler 1, so the crossing is the socket.
