# jobq change 3: the report

The change is `mo-wiki/spec/programs/01d-job-queue-change-3.md`. After a failure
the service now restarts itself and rebuilds its board from the log. It has a
restart budget, `--max-restarts` and `--restart-window`, that ends it with exit
70, and a chaos switch, `--crash-every N`, for rehearsing the failure. `/health`
now reports `"restarts": n`.

## Wall-clock

About 23 minutes from reading the spec to commit. The clock read 21 min 48 s
when the final checks passed.

## Checks, all green

- **`mo test --sim 100` on all seven modules:**
  - job: 27 tests
  - store: 13
  - board: 17
  - api: 9
  - queue: 14 (2 of them hold only without faults: one existing, one new)
  - server: 8
  - main: 10
- **Test binaries:** each file's binary (`mo build --tests`) prints exactly what
  `mo test` prints.
- **The seven `# run:` lines:** they match their `.expected` files under
  `mo run` and as the built binary. `jobq.expected` changed only on its two
  `/health` lines, which now end with `, "restarts": 0`.
- **`restarts.py`** passes under `mo run` (6.7 s) and against the binary (6.1
  s). It runs a real socket and a real crash, and checks the following:
  - With the switch at every 7th write under a 4-thread load, every answer is
    2xx, 4xx, or 503, and there are 77 to 79 restarts.
  - The longest `/health` outage was 0.052 to 0.065 s.
  - Every 201 job and every 200 ack is on the board after the restarts, and
    again after a stop and a start.
  - No id is handed out twice, and a restarted service counts from 0.
  - A budget of 2 with the switch at every write exits 70 after 3 writes.
    `verify` then exits 0, and the folder serves those 3 jobs.
  - Failures further apart than a 1-second window never exit, and `restarts`
    reaches 3. Two failures within the window exit 70.
- **`mo fmt --check`:** queue.mo and store.mo are clean. board, api, server, and
  main have exactly as many formatter differences as at HEAD; all of those were
  already there. job.mo was not format-clean at HEAD either.

## Loops, by cause

Each loop is one check, build, or test that failed.

**Checker diagnostics (5 loops):**

1. `mo check` gave two diagnostics:
   - MO0301: Queue's `update` was 90 lines, over the 70-line limit.
   - MO0309: a `_` arm on an `Option`.

   The first fix worked for both. The queue's state moved into a `Desk` struct
   with small functions, and the flag parser uses `or` instead of the arm.

2. MO0102: a `return` inside a one-line case arm in `settled`. The first fix
   worked.
3. MO0105: a helper function placed after the tests. The first fix worked.
4. MO0214: `return` inside an update arm. This was my second attempt at loop 7's
   problem, and it failed.
5. MO0310: an arm can't both keep `reply_to` and answer by value. This was the
   third attempt, and it failed too. The fix that worked is decision 5 below:
   the queue keeps those askers and answers them 503 when `Begin` comes.

**Runtime behaviour found by the tests (3 loops):**

6. Two new plain tests failed. In the test harness, any process crash fails a
   plain test, and a probe showed that a `test rejects` checks nothing after its
   trip. The first fix worked: the rebuild path is now tested without a crash
   (decision 14).
7. Two more failures:
   - A test expected id 501 after the rebuild but got 1001. The log's id
     reservation is the floor, so the test was wrong. The first fix worked.
   - A `Want` sent to a queue that hadn't begun timed out instead of getting
     503: an answer given in the same update that kept the reply was not sent.
     The first two fixes failed (loops 4 and 5); the third worked.
8. **Found in load testing, not fixed in the program.** Each restart leaks
   memory in proportion to the board. It is recorded as `TOOLCHAIN-BUGS.md` §5.

**Formatting (1 loop):**

9. `mo fmt --check` showed new differences in my code. The first fix worked.

**My own probe-script slips (2, not checks):** I ran a probe binary from the
wrong path, and a load probe's create lacked `max_tries`.

**Total: 9 loops.** The first fix worked in 7 of them. Loop 7's second failure
took three attempts, and loop 8 was recorded rather than fixed.

## Files changed

- `examples/programs/jobq/queue.mo`:
  - new: `Policy`, `Warden`, `Desk`, `Settled`, and the functions `guarded`,
    `kept_by`, `settled`, `spent?`, `due?`, `with_restarts`, and `refusals`
  - the queue is now `restart: :always` and rebuilds its board on `Begin`
  - 6 new tests
- `examples/programs/jobq/store.mo`: `reopened`, which opens `jobq.log` and then
  replays the log a `check` table writes to; 1 new test.
- `examples/programs/jobq/board.mo`: `Counts.restarts`.
- `examples/programs/jobq/api.mo`: `"restarts"` in the health JSON.
- `examples/programs/jobq/server.mo`: `serving` takes the policy; `started_by`;
  2 new tests.
- `examples/programs/jobq/main.mo`:
  - `serve` takes `--port`, `--max-restarts`, `--restart-window`, and
    `--crash-every`, in any order
  - `Place.rules`, the usage line
  - 1 new test
- `examples/programs/jobq/jobq.expected`: `restarts` on the two `/health` lines.
- `examples/programs/jobq/restarts.py` (new): the end-to-end restart checks.
- `examples/programs/jobq/TOOLCHAIN-BUGS.md`: §5, a crash keeps its rendered
  state for good.
- `examples/programs/.mo.ids`: the `verified:` records.
- `examples/README.md`: the jobq entry.

## Decisions the spec did not cover

1. **How the restart works.** The queue's child line now says
   `restart: :always`. The runtime re-runs its state initializers, and the first
   of them sends a new `Warden` process `Born`. The warden treats every `Born`
   after the first as a restart and answers it with `Begin`. The queue replays
   the log in that `Begin` update. On the first start, `main` passes the board
   it already opened inside `Begin`, so the log is not replayed twice.
2. **Where the budget lives.** The runtime's `max_restarts` takes only a
   literal, so the program keeps the budget itself: the warden holds the restart
   times. Once the budget is spent, the warden trips its invariant. The warden's
   line is `max_restarts: 0`, so the runtime gives up at once, `main` crashes,
   and the process exits 70, both under `mo run` and as a binary. The queue's
   own line allows 1,000,000 restarts a minute, so the runtime never gives up
   before the warden. Any other crash of the warden also exits 70.
3. **What the budget counts.**
   - A restart counts as inside the window when it happened less than S seconds
     before the failure.
   - With K restarts already inside the window, the next failure exits;
     `--max-restarts 0` exits at the first failure.
   - A restart's time is when the restarted queue announces itself.
4. **Flag ranges.**
   - `--max-restarts` is 0 to 1,000.
   - `--restart-window` is 1 to 86,400 seconds.
   - `--crash-every` is 0 to 1,000,000,000.
   - Flags come in any order, each at most once, and `--port` goes through the
     same parser. `check`, `compact`, and `verify` reject the flags as usage
     errors.
5. **What "503 while rebuilding" means.** A restarted queue gets its board only
   when `Begin` arrives, and until then it writes nothing.
   - A `Serve` is answered 503 at once.
   - A `Want` is kept and answered 503 when `Begin` arrives. An arm can't both
     keep a reply and answer by value, and an answer given in the same update is
     not sent.
   - Requests that arrive while the rebuild update is running wait in the
     mailbox and are answered normally after it, not with 503.
6. **What the chaos switch counts.**
   - Every record in a batch the log took counts as a write, including the `ids`
     reservation and the moves a look makes; a refused batch counts nothing.
   - A batch that passes two multiples of N fails once.
   - The count continues across restarts: before failing, the queue asks the
     warden to keep the count, since the failure discards the queue's state.
7. **How the chaos failure happens.** It is an invariant trip ("the board is
   whole…") after the batch is on disk and before any answer is sent. So every
   caller in that batch gets `Down` and answers 503, not only the caller of the
   N-th write.
8. **A rebuild that fails.** If the log can't be read or holds a record that
   isn't a job, the rebuild trips the same invariant: the queue fails again and
   the budget decides. Because of this, the sim test of the rebuild holds only
   without faults.
9. **A log cut short at a restart.** It is not rewritten during the rebuild,
   because nothing is written before the warden decides. It is marked torn
   instead, and the next batch writes it whole.
10. **`uptime_ms`** counts from the process's start, not from the last restart.
11. **Where `restarts` goes in `/health`:** it is the last field, after
    `uptime_ms`.
12. **Restarts under `jobq check`.** A restart replays `jobq.log` and then
    `jobq.check.log`. If the check log was rewritten whole after a torn write,
    jobs deleted during the check would come back. `check` doesn't take the
    chaos switch, so this is only a limit on paper.
13. **Ids jump by 1,000 per restart.** The first create after a rebuild reserves
    a new thousand. Nothing is handed out twice. This was already how a stop and
    start behaved.
14. **How the restart is tested.** A plain test fails if any process crashes,
    and a `test rejects` checks nothing after its trip, so:
    - the rebuild path is tested without a crash: a second queue started under
      the same warden counts as a restart, and the watched queue is begun again
      with no board
    - the chaos switch is tested with `test rejects`: once in isolation, once in
      the workers' rounds under faults, and once over the wire under load
    - the real crash, the restart, the budget, and exit 70 are tested by
      `restarts.py` against `mo run` and the binary
15. **The 503 reason for `Down`** is now "the queue failed and is rebuilding its
    board from the log".
16. **Restart time grows with the log**, as measured on the binary:

    | jobs in the log | startup | `/health` 200 again after a failure |
    | --------------- | ------- | ----------------------------------- |
    | 20,000          | 0.22 s  | 0.27 s                              |
    | 50,000          | 0.54 s  | 0.71 s                              |
    | 100,000         | 1.07 s  | 1.38 s                              |

    A log of 100,000 jobs misses the spec's one-second bar. The load in
    `restarts.py` restarts in about 0.05 s.

17. **Memory leaks with each restart.** Each crash report renders the whole
    board and is never freed: about 44 MB per restart on 20,000 jobs. This is
    recorded in `TOOLCHAIN-BUGS.md` §5 and not worked around. The default budget
    of 5 in 60 seconds bounds the rate.
