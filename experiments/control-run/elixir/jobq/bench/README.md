# bench

The speed budget of change 6 is measured by `jobq bench <dir>` (`Jobq.Bench`,
`lib/jobq/bench.ex`), not by this script: see the README. What follows is the
older bench, kept for its other measurements.

    mix run bench/bench.exs           # everything
    mix run bench/bench.exs throughput expiry
    mix run bench/bench.exs --jobs 20000 throughput

The bench is a client, not a harness: it talks to a real service on a real
local socket, one keep-alive connection per worker, the same HTTP the escript
serves. What it reports is what the spec's *Measured* section asks for.

  throughput  leases and acks per second with 1 worker and with 32
  expiry      the lag between a lease running out and the job being handed
              out again, under a steady stream of lease requests
  backoff     the same lag for a `run_at` that has passed, on a job put back
              with a backoff
  silent      what 1,200 connections that say nothing cost, and what a
              producer's request costs while they hold
  memory      resident memory and the BEAM's own total at 100k jobs
  replay      the time to replay a 1M-record log
  restart     the time to start again on a store with 10,000 leased jobs
  chaos       creates with the chaos switch failing every 500th write: the
              answers, the restarts, any 201 missing from the log, and the
              longest `/health` was not 200
