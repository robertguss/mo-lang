# Step 23's measurements

The tools behind step 23's numbers (the runtime surface), kept so they can be run again. Each takes
the scratch folder it may write in and the repository root as its first two arguments.

- `jqload.c`: jobq load over HTTP, one connection per request: makes N jobs, then W workers lease
  and ack for S seconds, optionally holding C silent connections; `leaseonly` leases for 100 ms and
  never acks. `zig cc -O2 -o jqload jqload.c`.
- `rate.py`: jobq's lease-and-ack pairs a second with 32 workers, two native binaries interleaved,
  best of three, each on a fresh copy of `data/demo` with 50,000 jobs made first.
- `ringmem.py`: kv's resident memory after 100,000 GETs with the event ring at 0, 4,096, and 65,536,
  under `mo run --events N` and a binary with `MO_EVENTS=N`.
- `many.py`: `GET /processes` on the surface with 10,000 live processes: `hold.mo` reads each idle
  connection into a process of its own (put it at `<scratch>/hold/main.mo`; run under `ulimit -n 65536`).
- `kvab.py`: kv's 10,000 GETs to native binaries interleaved, best of N, for a before and after.
- `nine.py`: program 1's nine questions asked of jobq's surface under load.
