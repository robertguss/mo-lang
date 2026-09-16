# REPORT-jobq: every body of `examples/programs/jobq/` written again from its spec

Worktree `mo-lang-cache-B`, branch `cache-B`. The ten modules kept their intent, types, processes,
signatures with their contracts, and their tests; all 210 function bodies were gone. The spec read
was `mo-wiki/spec/programs/01-job-queue.md`, plus `examples/README.md`, `examples/GAPS.md`, and
`mo-wiki/spec/design-v0/09-stdlib.md` for the rows that exist. `notes`'s `Notes.Store` was copied by
hand for `Jobq.Store`, which is what the spec's package story asks for.

## Done-when

- `mo check` is green on all ten modules. `store.mo` carries `# recipe: Recipes.Store.Store`, so its
  check also reports `recipe Recipes.Store.Store: 11 signatures match` with the recipe's tests
  passing.
- `mo test` is green on all ten modules: 55 tests, 0 failed, 0 skipped, four properties at 200 seeds.
- `queue.mo` holds under `--sim 200`; `server.mo` holds under `--sim 400 --faults 20 --until 0.5`,
  the flags its own `# sim:` line names.
- Every `# run:` line of `main.mo` prints its `.expected` file byte for byte and exits as its
  `# exit:` line says:

  | run | arguments | exit | stdout |
  |---|---|---|---|
  | 1 | `check data/demo data/session.txt` | 0 | matches `jobq.expected` |
  | 2 | `compact data/compact` | 0 | matches `jobq-2.expected` |
  | 3 | `serve` | 2 | matches `jobq-3.expected` (empty) |
  | 4 | `serve data/nowhere` | 1 | matches `jobq-4.expected` (empty) |
  | 5 | `client 127.0.0.1 1 ada GET /jobs` | 1 | matches `jobq-5.expected` (empty) |

- `mo test --write --sim 100` rewrote every `verified:` line and the `examples/programs/.mo.ids`
  sidecar; the sidecar diff touches jobq's nine changed files and nothing else.
- Nothing outside `examples/programs/jobq/*.mo` and `examples/programs/.mo.ids` changed. `data/demo`,
  `data/compact`, and `data/session.txt` are as they were found: `check` removes its
  `jobq.check.log` before and after, and `compact` rewrites `data/compact/jobq.log` to the bytes it
  already held.
- Every `mo` process ran under `timeout 120` with a watchdog killing it past 4 GB RSS. The watchdog
  never fired; the slowest call was `mo test --sim 400` on `server.mo`.

Every module's `verified:` line as written:

```
job.mo      types, contracts, tests (14), property (200 seeds), sim (not run)
store.mo    types, contracts, tests (6),  property (200 seeds), sim (not run)
journal.mo  types, contracts, tests (3),  property (0 seeds),   sim (not run)
board.mo    types, contracts, tests (4),  property (0 seeds),   sim (not run)
books.mo    types, contracts, tests (3),  property (0 seeds),   sim (not run)
moves.mo    types, contracts, tests (8),  property (200 seeds), sim (not run)
queue.mo    types, contracts, tests (3),  property (0 seeds),   sim (100 runs)
api.mo      types, contracts, tests (7),  property (200 seeds), sim (not run)
server.mo   types, contracts, tests (2),  property (0 seeds),   sim (100 runs)
main.mo     types, contracts, tests (5),  property (0 seeds),   sim (not run)
```

## Wall-clock

25 minutes, 01:15 to 01:40 UTC on 16 Sep 2026, reading through commit.

## Loops to green, by cause

Four rounds failed. Each was fixed by the next edit: 4 of 4 first fixes worked. Order of work was
bottom-up: `job`, `store`, `journal`, `board`, `books`, `moves`, `queue`, `api`, `server`, `main`.
Six of the ten modules went green on their first run.

| # | module | cause | diagnostic or failing test | next edit fixed it |
|---|---|---|---|---|
| 1 | `board.mo` | `counted` wrote `Queued: after.queued = moved(...)` — an assignment after a case arm's `:` | `MO0101 a case arm holds one expression after its :; an assignment is a statement, and a statement goes on its own lines below the arm` | yes |
| 2 | `books.mo` | `opened` read a `var table` inside `flat_map`'s function | `MO0314 table is a var and cannot be captured by the anonymous function; bind a plain name first` | yes |
| 3 | `server.mo` | under `--faults 20 --until 0.5`, a snapshot the service refused read back as an empty job list, so a lease answered 503 was compared against `[]` and reported a change the run never made | `seed 12319818738039409595: assert turn(http, service, port, n) == "" failed; left = "a 503 changed the jobs"` | yes |
| 4 | `main.mo` | one `mo check` carrying three: `net.connect` was called as `connect(host, port: port, ...)`, and the crowd's `for i in 0..wanted` never read `i` | `MO0209 connect takes no argument named port:` / `MO0207 net.connect takes 2 arguments, found 1` / `MO0307 i is bound but never used` | yes, all three |

Two more slips were caught before any `mo` run, by reading the bodies back: a call to a helper
(`try_whole`) I had not declared, and `health` reading `health_counts` where its parameter is
`counts`. Neither reached the toolchain, so neither is a loop.

Not a loop, but worth recording: `mo check` is green on a module whose function bodies are all
empty, and `mo test` on that module does not report a diagnostic — it panics in the interpreter
(`toolchain/src/vm.zig:780: access of union field 'bool' while field 'none' is active`, through
`runner.run`). A body that returns nothing where a return type is declared should be a checker
diagnostic, not a VM abort. Reproduced on the stripped `job.mo` before any body was written.

One round was lost to my own harness, not the program: `zsh` does not word-split an unquoted
variable, so `mo run main.mo -- $args` passed the whole argument string as one argument and runs 2
to 5 came back as `unknown command ...`. Re-run with the arguments passed one by one, all five
matched.

## Decisions the spec did not cover

1. **Three signatures had lost their continuation line.** The strip took the second line of
   `Jobq.Board.with_number`'s return type, of `Jobq.Journal.put_all`'s, and of `Jobq.Main.ran`'s,
   because each was the first line under the `fn` line. Restored as
   `Map(K, Set(UInt64)))`, `StoreError)`, and `Problem)`. The strip also took `put_all`'s contract
   with it; `test rejects "a put of many with a key holding a space"` has to trip something, so it
   was restored as `requires pairs.all?(fn(pair) key?(pair.0) and value?(pair.1) end)`.
2. **Two private helpers the stripped file did not declare.** `Jobq.Books.unwritten` (a write the log
   did not take: the books as they were, torn when the log may end in part of it) and
   `Jobq.Server.swept_leases` (the acceptor's `Sweep` ask, 10 s, 0 when the service does not answer).
   The other 208 bodies fit the signatures as they stood.
3. **`Jobq.Job.released` had no comment and is not exposed.** It was made the shared move off a lease
   that `failed` and `ran_out` both call: dead when `attempts >= max_attempts` and queued otherwise,
   `worker` and `lease_until` cleared, `updated_at` stamped. `failed` adds its reason on top;
   `ran_out` keeps the one already there, as its comment asks.
4. **Ids are reserved a thousand at a time.** The spec says the log reserves ids; it does not say how
   many. When a create spends an id at or past the reserved floor, the same append writes
   `SET ids <next_id + 1000>` ahead of the job's record. This is what makes `data/demo`'s
   `SET ids 1000` hand out `j_1000` and then `j_1001`, which `jobq.expected` pins.
5. **The `ids` record lives beside the jobs in one store.** So `Jobq.Books.opened` takes live jobs
   from `keys(table, "j_")`, and refuses a `j_` record whose own `"id"` field is not its key —
   `books.mo`'s first test requires the refusal.
6. **Field order in `shown` for a job both leased and failed:** `worker`, `lease_until`, then
   `reason`. The spec lists the three as additions to the object without fixing their order; the
   module's test and `jobq.expected` pin this one.
7. **`job_of` ties `state` to the held fields.** A record whose state is `leased` with no `worker`
   and `lease_until` is refused (the module's test asks for it), and so is one that carries them
   under any other state. Without the second half a replay could put a job on the board that the
   never over `Job.all` would have to argue about.
8. **How the service's deadline is split among its file calls.** `Jobq.Journal` caps each call at a
   share of what remains of the ask: `at_most(600 s)` for a replay's `fold_lines`, `at_most(10 s)`
   for `list` and `size`, `at_most(5 s)` for an append and for the `size` that looks at a failed
   append again, `at_most(20 s)` for a compaction's write with the rename left on the bare deadline.
   Only the last two are named in the module's own comments.
9. **`within:` count.** 29 `within:` in program code (the rest of the 57 in the tree are in tests).
   Seven are `Deadline.at_most(<literal>)` — derived from the asker's `reply_by` and capped by a
   number chosen for that call — and one is a bare `by`, fully derived. The other 21 are literals
   chosen for their call: the worker's ask of the service 60 s and its `exchange.reply` 30 s, the
   acceptor's `Sweep` ask 10 s, `main`'s `Open` 21 minutes, `http.listen` 5 s, the client's `send`
   30 s, the script read and the two `jobq.check.log` calls 10 s, a crowd member's `connect` 5 s,
   and the store recipe's own seven, which keep literals because a recipe's signatures carry no
   deadline. Every `Deadline` in the program descends from a `reply_by`; no sum of literals is
   written anywhere.
10. **`idle:` is 5 seconds on both listeners.** The runtime counts connections that have sent no
    whole request against the acceptor's mailbox, which is 4,096, so 1,200 silent connections are
    far from the bound; 5 s is what closes them, and it is also how often the acceptor turns `Idle`
    into a `Sweep`, which bounds how long a lease that has run out can sit before a look frees it.
11. **`Sweep` answers with the number of steps its write made,** 0 when the write was refused.
    `Outcome` has no arm for a count, and the message's reply type is `UInt64`.
12. **The sim test's 503 check only fires when the snapshot before it was real.** A snapshot the
    service refuses is `None`, which reads as an empty job list; comparing a 503 against that
    reports a change nobody made (decision 3 in the loop table). The worker also leases for an hour,
    the spec's maximum, so no lease can run out between the two snapshots a turn takes.
13. **`jobq.check.log` is removed twice.** Once in `ran`, before the service opens, so the folder's
    own log replays alone; once in `check`, after the script, so the folder is left as it was found.
    A file that will not go is `Unopened`, exit 1.
14. **Error wording.** Eleven sentences the spec does not write. Those that appear in
    `jobq.expected` were read off it (`queue must be 1 to 64 letters, digits, - and _`;
    `max_attempts must be a whole number from 1 to 100`; `lease_ms must be a whole number from 100
    to 3600000`; `the body is not JSON`; `no such job`; `the job is leased`; `the caller does not
    hold a live lease on the job`; `no route <path>`; `this route takes GET, DELETE`; `a request
    needs authorization: Bearer <token>`; `state must be queued, leased, done, or dead`). The rest
    — the payload and reason rules, and `Jobq.Books.table_of`'s six lines for a log that will not
    open — were chosen to read like `notes`'s.
15. **`compact`'s line counts two different things.** `jobq-2.expected` reads `from 2 lines to 2`:
    the first is the lines the replay read, the second the live keys the rewrite wrote. They agree
    on `data/compact` and would not on a log with a key set twice.
16. **The crowd is a `var` list inside the loop that plays the script.** A function cannot return a
    `Conn` (MO0403), as `GAPS.md` already recorded, so the connections are opened one `for` inside
    another and held until the script ends. How many opened goes to stderr, since the descriptor
    limit decides it; stdout gets the one fixed line `jobq.expected` names. On this machine all
    1,200 opened.
17. **`Jobq.Store` is `Notes.Store` copied by hand,** with `whole_text`, `rewritten`, and a `name`
    argument on `replayed_from` added so `Jobq.Journal` can make the same calls on a caller's
    deadline. The copy came out byte-identical to what the strip removed: `store.mo` is the one
    module whose entry in `examples/programs/.mo.ids` did not change, and the sidecar hashes
    declarations by their bodies.
18. **`Jobq.Board.second_of` counts whole seconds from 2000-01-01,** so the due index's `Int64` key
    stays small and a later time never has a smaller second.
19. **`mo test --write --sim 100`, not a plain `--write`.** The corpus records `sim (100 runs)` for
    every file with a process test (`notes/server.mo`, `notes/service.mo`, `kv/store.mo`), and a
    plain `--write` would have written `sim (not run)` on `queue.mo` and `server.mo`, which is not
    what the corpus test verifies them at.
20. **`git add <paths>`, never `git add -A`.** The commit names the ten modules, the sidecar, and
    this report.
