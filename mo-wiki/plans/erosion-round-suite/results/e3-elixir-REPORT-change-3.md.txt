# jobq, change 3: the store restarts itself, with a budget and a chaos switch

The Elixir program in `experiments/control-run/elixir/jobq/`, changed to
`spec/programs/01d-job-queue-change-3.md`. Elixir 1.18.5 on OTP 27 (erlang
27.3.4.17) through `mise`, on macOS.

## Status: green

| Check                                      | Result                                                                                                                                        |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `mix compile --warnings-as-errors --force` | clean                                                                                                                                         |
| `mix format --check-formatted`             | clean                                                                                                                                         |
| `mix credo --strict`                       | no issues                                                                                                                                     |
| `mix dialyzer`                             | 0 errors                                                                                                                                      |
| `mix test`                                 | 4 properties, 140 tests, 0 failures (3 runs in a row); 126 before the change                                                                  |
| `./check.sh`                               | ok, with the new section 5                                                                                                                    |
| `mix run bench/bench.exs chaos`            | 20,000 × 201, 3,335 × 503, 40 restarts, **0 answers of 201 missing from the log**, longest `/health` gap 117 ms on a log of about 20,200 jobs |

**Wall-clock:** about 10 minutes, from reading the spec to a green tree.

## What changed

- **The board (`Jobq.Board`, new).** The store and the queue now sit under their
  own supervisor, which restarts them together (`:one_for_all`).
  - The restart budget is the supervisor's own restart intensity: `max_restarts`
    inside `restart_window` seconds.
  - `Jobq.Server` changed from `:rest_for_one` to `:one_for_one`, with two
    children: the board and the listener. A board restart no longer touches the
    listener, so the port stays bound.
  - The board is the server's one _significant_ child
    (`auto_shutdown: :any_significant`). When the board runs out of budget, the
    service stops and `jobq serve` exits 70.
- **The queue registers its name only after it has replayed the log.** A request
  that arrives during a rebuild finds no queue and gets `503` at once.
  - A failure inside the _look_ now takes the board down, whether it comes from
    a request or from the sweep.
  - A failure inside the operation itself is still that one request's `503`.
  - `/health` gains `"restarts"`.
  - `uptime_ms` now counts from the service's start, so a board restart does not
    reset it.
- **The store:**
  - The chaos switch fires once a batch is on the disk and before its replies
    are sent.
  - Writes and restarts are counted in a `:counters` array the service owns, so
    the counts survive restarts.
  - A torn final line is cut when the store starts.
  - `format_status/1` keeps payloads and buffers out of crash reports; the
    queue's version does the same for its jobs.
- **The CLI:**
  - `serve` takes `--max-restarts`, `--restart-window` and `--crash-every` as
    well as `--port`, in any order.
  - A board past its budget gives exit 70 and a one-line message on stderr.
- **Tests:**
  - **`restart_test.exs` (new, 12 tests):**
    - the chaos switch, with the board compared to the log after each restart;
    - the queue killed, with the port still bound and the lease still held;
    - the store killed;
    - a broken rule found by a look;
    - `503` while the board is down;
    - uptime kept across a restart;
    - `/health` back to `200` within 1 s on a 100,000-record log;
    - the torn-line cut;
    - the budget: exit on the failure one past it, the folder reopening, and a
      fresh count once the window has passed;
    - a random-write fault run, the equivalent of `--sim`. Every write a 2xx
      answer reported is on the board, the board equals the log before and after
      a stop and start, and `Never.check` passes.
    - the chaos switch under 16 concurrent HTTP clients: every answer is 2xx,
      409 or 503 (or a closed connection), and every 201 job is present
      afterwards.
  - **`cli_test.exs`:** usage errors for the new flags, exit 70 followed by a
    clean `verify`, and the flags in any order.
- **Program-level check:**
  - `script/expected.txt` now shows `"restarts":0` in `/health`.
  - `check.sh` has a new section 5: a real
    `jobq serve --crash-every 2 --max-restarts 1`. The failed write answers
    `503`, the record is on the board afterwards, `restarts` goes to 1, the next
    failure gives exit 70, and `verify` exits 0 with 4 jobs.
- **Bench:** a new `chaos` measurement, described in `bench/README.md`.
- **README:** documents the board, the budget, the chaos switch and exit 70.

## Files changed

In `experiments/control-run/elixir/jobq/`:

- `lib/jobq/board.ex` (new)
- `lib/jobq/server.ex`
- `lib/jobq/store.ex`
- `lib/jobq/queue.ex`
- `lib/jobq/cli.ex`
- `test/jobq/restart_test.exs` (new)
- `test/jobq/cli_test.exs`
- `script/expected.txt`
- `check.sh`
- `bench/bench.exs`
- `bench/README.md`
- `README.md`

At the worktree root: `REPORT-change-3.md`.

## Loops to green, by cause

Six loops came from checks, builds or tests failing on the code (5 of them fixed
by the first edit), and two from the environment. In order:

| #   | What failed                                                                                                                             | Cause                                                                         | Did the first fix work?                                  |
| --- | --------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | -------------------------------------------------------- |
| 1   | `mix test`: `CheckTest` transcript differed from `expected.txt`                                                                         | `/health` now carries `"restarts"`. This was expected.                        | Yes. Updated `expected.txt`.                             |
| 2   | `mix test`: `RestartTest` "the store killed", where `/health` answered `restarts: 0`                                                    | A race in the test: the old queue answered before the supervisor took it down | Yes. `kill/2` now waits for the queue's `DOWN`.          |
| 3   | `mix format --check-formatted`                                                                                                          | My regex edit left blank lines in `queue.ex`                                  | Yes. Ran `mix format`.                                   |
| 4   | `mix credo --strict`: 4 issues (2 nested module references in a test, 2 over-deep nestings in `Store.cut_torn` and the test's `finish`) | Style                                                                         | Partly. 3 of the 4 were fixed.                           |
| 5   | `mix credo --strict`: nesting still too deep in the test's `finish`                                                                     | Style                                                                         | Yes. Split the fail-or-ack choice into its own function. |
| 6   | `mix run bench/bench.exs chaos`: `MatchError` on `{:error, :store}`                                                                     | The bench's closing `/health` read landed inside a restart                    | Yes. The bench now waits for a `200` first.              |

After loop 6 I also made two changes that no failure forced:

- The bench's crash reports dumped whole buffers, payloads included, so I added
  `format_status/1`.
- Most of the bench's answers were 503 because the clients never waited out a
  restart, so they now retry after 5 ms.

Environment (not code):

- **E1.** `eval "$(mise env)"` in this worktree gave Elixir 1.20.4 on OTP 29
  (the global mise config; the worktree has none), and mix stopped on missing
  deps.
  - The fix worked first time: I ran every command through
    `mise exec elixir@1.18-otp-27 erlang@27.3.4.17 --`, then `mix deps.get`.
- **E2.** A wrong relative path to my wrapper script ("No such file or
  directory").
  - The fix worked first time: I switched to the absolute path.

## Decisions the spec did not cover

1. **What "the store" is.** The part that restarts is the store _and_ the queue,
   together, under `:one_for_all`.
   - Restarting only the queue would leave the old store holding commits the new
     queue never saw, so an id could be handed out twice.
   - Restarting only the store would leave the queue ahead of a log that lost
     its buffer.
   - The listener sits outside the board, so the port stays bound and open
     connections are answered `503` rather than closed.
2. **The budget is OTP's own restart intensity.**
   - `K` restarts inside `S` seconds are allowed; the next failure inside the
     window stops the board.
   - OTP measures the window in whole seconds.
   - `--restart-window 0` is a usage error (minimum 1). `--max-restarts 0` is
     allowed and means the first failure exits 70.
3. **Exit 70 whenever the tree gives up on its own.** If the server stops with
   reason `:shutdown`, `serve` exits 70.
   - That also covers the listener running out of its own default restart
     intensity (3 in 5 s). It is still "the service stopped instead of
     restarting again".
   - The message on stderr names the budget.
4. **What the chaos switch counts.**
   - It counts records the store has put on the disk: creates, leases, acks,
     fails, retries, tombstones and the moves a look makes.
   - The count survives restarts, and a batch counts only once it is on the
     disk.
   - A batch that crosses a multiple of N fails once, even if it crosses more
     than one.
   - Every waiter in that batch gets `503`, although all of their records are on
     the disk.
   - A batch the disk refused (change 2's epoch path) is not counted.
5. **A disk that refuses a write is still change 2's path.** The store moves to
   a new epoch and the queue reloads. It is not a restart and does not count
   against the budget.
6. **What "a rule inside the service broken" means.** It is a failure inside a
   _look_ (the lease and scheduled indexes disagreeing with the jobs), in a
   request or in the sweep. That takes the board down. A failure inside the
   operation proper is still that request's `503`, with the board left as it
   was.
7. **`503` during a rebuild comes at once.** The queue registers its name only
   after it has replayed the log, so a request during the replay is refused
   immediately rather than held until the replay ends.
8. **`uptime_ms` counts from the service's start** and is not reset by a board
   restart. Before this change, a queue restart did reset it.
9. **`"restarts"` is the last field of `/health`**, after `uptime_ms`.
10. **A torn final line is cut when the store starts** (truncated to the last
    `\n`, `fsync`ed, with a warning).
    - Without this, a service started again after a kill would append its first
      record to the torn line, and the log would then refuse to open.
    - `verify` still only reads; it does not cut.
11. **Crash reports are redacted.** The store's buffer and the queue's jobs,
    payloads included, are left out, and the commit message is reduced to a
    record count. A crash report on a large board would otherwise be megabytes
    of client data.
12. **CLI flags.** `serve`'s flags may come in any order, and the last of a name
    wins. The ranges are:
    - port: 0–65535
    - max-restarts: 0–1,000,000
    - restart-window: 1 s to 1 year
    - crash-every: 0–10⁹

    `compact`, `verify`, `check` and `client` refuse the flags as a usage error
    (exit 2).

13. **`jobq check` runs with the defaults** (budget 5 in 60 s, no chaos), so its
    transcript shows `"restarts":0`.
14. **The random-fault run.** The "`--sim` or equivalent" run is an ExUnit test
    using a test-only `:crash` option (a function of the write number). The
    chaos-under-load run is both an ExUnit test over HTTP and the bench's
    `chaos` measurement.
15. **Bench clients retry.** They retry a `503` after 5 ms, as a real client
    would. Some jobs whose response was lost to a failure then exist twice
    (about 20,200 jobs for 20,000 answers of 201), which is what the spec says a
    `503` caused by the failure may leave behind.
16. **Toolchain.** The worktree has no `mise` config, so every command ran under
    `mise exec elixir@1.18-otp-27 erlang@27.3.4.17`.
17. **README reflow.** An editor hook in this environment re-wrapped two README
    paragraphs I edited to 80 columns. Their wording is unchanged.
