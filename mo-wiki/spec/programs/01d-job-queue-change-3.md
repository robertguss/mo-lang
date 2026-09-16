# Program 1, change 3: the store restarts itself, with a budget and a chaos switch

The third change to `jobq`, the erosion round's generation three (direction 43, measurement 3). Written by Claude (Fable) on 16 Sep 2026 from what P6 found on the four generation-two programs: killed or crashed under load, the Elixir service came back on its own in under a second, and the Mo service answered `503` to every request from then on until an operator restarted it; Go and Python have no part to kill and were not probed. Everything in `01-job-queue.md`, `01b-job-queue-change.md`, and `01c-job-queue-change-2.md` still holds unless a line below changes it. The shape is an operations ticket after a night on call: the service must come back by itself, it must stop trying when coming back does not help, and the people running it must be able to rehearse the failure in staging.

## What changes, in one screen

1. **The store restarts itself.** When the part of the service that holds the board fails in a way that is not one request's failure (a rule inside the service broken, an unexpected error while a batch is being applied, the process or thread that holds the board dying), the service rebuilds the board from the log and goes on serving, without an operator. While it is rebuilding, requests are answered `503`; after it, requests are answered normally, and every write that was on disk before the failure is on the board.
2. **A restart budget.** More than `max_restarts` restarts inside `restart_window` seconds (defaults 5 and 60, set on the command line) and the service stops instead of restarting again: it exits 70 with the log whole, and the folder opens cleanly afterwards. Coming back must not become a loop.
3. **A chaos switch.** `jobq serve <dir> --crash-every N` makes the board fail on purpose on every N-th write it applies, as the failure in 1 would, so the restart path can be rehearsed in staging under real load. `N` is 0 by default, which never fails.
4. **`/health` counts restarts**: `"restarts": n` since the process started.

## What a restart means

The board after a restart is the board the log holds: every record a `2xx` response reported is present with the state that response reported; a write that reached the disk but whose response was lost to the failure is present too. So a client that received a `503` during a restart must read the job to learn what happened, as it must after a kill; change 2's rule that "a `503` never leaves a job changed" holds for every `503` except the ones the failure itself caused, and this page is the one that says so. Leases held before the failure are still held after it, with their `lease_until`; a lease that ran out during the restart is put back at the next look as always. Ids continue; nothing is handed out twice. Connections open at the failure may be closed; the port stays bound, and a client that reconnects is served.

The restart takes what replaying the log takes. The hidden suite will hold the service to answering `200` on `/health` within one second of a failure on a log of the size its load creates, and to every acknowledged write being present on the board after the restart and again after `serve` is stopped and started on the folder.

## The budget

`--max-restarts K` and `--restart-window S` (defaults 5 and 60). The K-th restart inside any window of S seconds is the last: on the next failure inside the window the service exits 70 after writing nothing more, and `jobq verify` on the folder exits 0. A failure after the window has passed starts a fresh count. `/health` reports `restarts` as the count since the process started, not since the window began. The count is not persisted: a stopped and started service begins at 0.

## The chaos switch

`--crash-every N`, default 0. With `N` above 0 the N-th, 2N-th, 3N-th write the board applies fails after its record is on disk and before its response is sent, exactly as an unexpected failure at that point would: the client gets a `503` or a closed connection, the record is on the board after the restart, `restarts` goes up by one. The switch counts writes the board applies (creates, leases, acks, fails, retries, deletes, and the moves a look makes), not requests. It is a serving option only; `compact`, `verify`, `check`, and `client` do not take it. A service with the switch on and a budget of 5 in 60 seconds under load exits 70 in short order, which is the point: the switch is for staging.

## Usage

```
jobq serve <dir> [--port N] [--max-restarts K] [--restart-window S] [--crash-every N]
jobq compact <dir>
jobq verify <dir>
jobq client <host> <port> <token> <method> <path> [<json>]
jobq check <dir> <script>
```

## Nevers

- A write a `2xx` response reported is never missing after a restart.
- A restart never hands out a job number twice.
- The service never restarts more than `max_restarts` times inside `restart_window` seconds: it exits 70 instead.
- The service never exits 70 with a torn log it cannot itself reopen.
- Everything in the earlier lists still holds.

## Contracts and tests the reader expects to see

The restart as a test: a failure injected inside the board (the chaos switch or the implementation's own hook), then a read showing the board equal to the log's; the budget as a test: failures faster than the window allows, the exit code, the folder reopened; the chaos switch under the program's own load test with every response `2xx`, `4xx`, or `503` and every `2xx` job present after; `/health`'s `restarts` before and after; the `--sim` or equivalent fault run with the failure injected at random writes; the program-level check script extended with `restarts`.

## Measured, for the round

The round's page says what is measured. For the maintainer nothing is asked beyond the report: loops to green by cause, wall-clock, files changed, and the numbered list of decisions this page did not cover.
