# notes regenerated — report

Every function body in `examples/programs/notes/` was written again from the modules' intents,
types, signatures, contracts, and tests, and from `mo-wiki/spec/programs/04-web-backend.md`.
The tests were not touched.

## Wall clock

15 minutes 31 seconds, 00:43:37 to 00:59:08 UTC, 16 Sep 2026.

## Loop count by cause

**Zero failing loops.** No `mo check`, `mo test`, or `mo run` failed at any point, so no fix was
needed and the question of whether a first fix worked never arose.

| what was run | times | failures | diagnostic codes | failing tests |
| --- | --- | --- | --- | --- |
| `mo check` (7 modules, twice over) | 14 | 0 | — | — |
| `mo test` (7 modules) | 7 | 0 | — | — |
| `mo test --write` (7 modules) | 7 | 0 | — | — |
| `mo run` against a `.expected` (5 lines, twice over) | 10 | 0 | — | — |

Totals: 49 modules-worth of tests over the program (42 tests, 6 properties at 200 seeds each,
9 `test rejects`), and 5 program runs, all first-try green.

The one edit made after a module was already green was cosmetic: the two process `update`
bodies (`service.mo`, `server.mo`) were written two spaces too deep. `mo check` accepted both
before and after, so it is not counted as a loop.

Order of work: `store.mo`, `limits.mo`, `note.mo`, `api.mo`, `service.mo`, `server.mo`,
`main.mo` — each checked and tested before the next was started, so a module was never written
against a module that had not been proved.

## What was leaned on

`examples/README.md` row 70 and the program spec gave the shape. The store recipe's
implementation was written from `examples/programs/jobq/store.mo`, which the corpus records as
a hand copy of this very module (README row 77), less the `put_all`/`continued` jobq added and
with `replayed_from` back to two parameters and `compact` inlined, since `Notes.Store` declares
no `whole_text` or `rewritten`. `jobq`'s `api.mo`, `server.mo`, `queue.mo`, and `main.mo` were
read for idiom (response helpers, the `Routed` shape, the transcript masking), not for the
notes logic, which came from `notes.expected`, `data/demo/notes.log`, and the tests.

## Private helpers added

Beyond the declared signatures: `note.mo` `plain_char?`; `api.mo` `member_command`,
`object_of`; `service.mo` `touched`, `rewritten_log`, `held_ids`, `applied_change`,
`uncounted`; `server.mo` `first_id`, `let_go`, `looked_over`, `kept_of`, `why_of`;
`main.mo` `mended`.

## Decisions the spec did not cover

1. **How an id is never reused.** The spec says only that it must not be. The log keeps a
   reserved key `ids` holding the first id not yet reserved, and ids are reserved a hundred at a
   time: a create whose next id has reached `reserved` appends `SET ids <next + 100>` before its
   own line. `data/demo/notes.log` opening with `SET ids 101` and the first create in
   `notes.expected` coming back as `n_101` fixed both the key and the size of the reservation.
   Replay takes `next_id = max(highest note id + 1, ids, 1)`.

2. **A create's id is spent whether or not its line reached the log.** `issued` advances
   `next_id` on every path out of `written`, including the 503s, so no id is ever handed out
   twice even after a failed append. `Issued.floor` holds by construction.

3. **The store key layout.** `<token>/<id>`, with `ids` the one live key holding no slash. So
   `opening` counts only keys with a slash as notes, and `/health`'s `notes` is the sum of the
   per-client counts rather than `count(table)`, which would count the `ids` row.

4. **Listing order.** Byte order over the store's keys gives `n_1, n_10, n_2`. The service
   test's expected `["todo 0", "todo 2", … "todo 10"]` forced a sort by the number inside the
   id, then the first hundred.

5. **What `clients` counts.** A client whose last note is deleted is dropped from `owners`, so
   `/health`'s `clients` is the number of clients that hold at least one note, not the number
   ever seen.

6. **The order of the three refusals.** The method check comes before the token check, so a
   method a route does not have is 405 even with no token; the token check comes before the
   body check, so a malformed body from a client with no token is 401, not 400.
   `notes.expected` pins the 405-without-reaching-the-service case and no other, so the rest is
   a choice.

7. **Which paths are 405 and which 404.** `/notes` takes GET and POST, `/notes/{id}` takes GET,
   PUT, and DELETE; anything else under `/notes/…` (`/notes/`, `/notes/n_1/x`) is 404, not 405.

8. **The wording of every error the transcript did not pin.** `notes.expected` fixes four —
   `a request needs authorization: Bearer <token>`, `no route /nowhere`, `no such note`,
   `this route takes GET, PUT, DELETE`, `the body is not JSON`, `title is missing`,
   `title must be a string`, `title must be 1 to 200 bytes with no control characters`. The
   rest were written in the same voice: `the body must be a JSON object`,
   `body must be at most 60 KiB with no control characters but a newline`,
   `the log did not take the change` (503), `the service did not answer in time`,
   `the service holds a million notes already`.

9. **The order a change reaches the log.** A log a failed append may have torn is rewritten
   whole (`compact`) first, then the id reservation when the change hands one out, then the
   change's own line, and only then is the change applied to the table and answered. Each of
   the three steps keeps the books it produced, so a compaction that succeeded before a later
   step failed is not thrown away with its recorded size.

10. **A malformed body still costs a token.** `Refuse` is a call on the service, so the rate
    limiter takes a token before it is answered 400 — the module comment says so, the spec does
    not. A 405, a 404 route, and a 401 never reach the service and take none. `/health` takes
    none either.

11. **What `out` is for in `ran`, `serve`, and `served_on`.** `served_on` writes
    `notes: serving <dir> on 127.0.0.1:<port>` to `out` itself and gives back `""`, since
    serving never returns and the line belongs on stdout before the first request rather than in
    a value `main` writes afterwards.

12. **Which command compacts.** `notes serve` rewrites a log whose last line was cut short
    before it listens, so the next change starts on a line of its own; `notes check` does not,
    since it only reads the folder's log and appends its own changes to `notes.check.log`.
    `notes compact` always rewrites.

13. **The store's own rules, which the recipe states but does not fix for notes.** The log is
    `notes.log`; a key is 1 to 256 bytes with no space and no control character; a value is at
    most 1 MiB with no line break; the table is spread over 256 small maps.

14. **The check script in `server.mo`.** `script()` is the one thing the spec leaves entirely
    open: make, look, read, rename, read, make, look, drop, read, look. Each move is checked
    against what the client should now hold and against what the service actually holds, a 503
    is accepted only when the service holds exactly what it held before, and a request the wire
    lost stops the check rather than failing it.

15. **How the client sends a query.** `notes client … GET /notes?prefix=to` puts the whole
    target in `Request.path` and leaves `query` empty; the runtime writes the target verbatim
    and the server splits it back into a path and a query. (`jobq`'s later client splits it
    itself; `Notes.Main` declares no `query_of` or `bare`, so it does not.)

16. **Three signatures the stripper cut in half.** `ran`, `serve`, and `check` in `main.mo` each
    ended at `: Result(String,` because the continuation line went with the body. All three were
    restored as `Result(String, Problem)`, which is the only type that fits their callers.

## Green

- `mo check` and `mo test`: 7 modules, 0 failed, 0 skipped.
- `mo test --write` has rewritten every `verified:` line; `examples/programs/.mo.ids` changed
  only in its seven `notes/` entries.
- Every `# run:` line matches its `.expected` byte for byte, with the exit codes the `# exit:`
  lines give (0, 0, 2, 1, 1). `data/` is byte-identical after the runs.
