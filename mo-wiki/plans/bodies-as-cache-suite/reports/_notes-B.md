# Regenerating `examples/programs/notes/`

Every function body in the seven modules of program 4 was written from the modules' own
intents, comments, signatures, contracts and tests, plus the spec at
`mo-wiki/spec/programs/04-web-backend.md`. The tests were not touched: every `test`,
`test rejects` and `property` block is byte-identical to the stripped tree.

## Done-when

- `mo check` clean on `limits.mo`, `note.mo`, `store.mo`, `api.mo`, `service.mo`, `server.mo`,
  `main.mo`. `mo check` also matched both recipes: `Recipes.RateLimiter.RateLimiter`
  (3 signatures) on `limits.mo` and `Recipes.Store.Store` (11 signatures) on `store.mo`, and
  ran each recipe's own tests green on the implementation.
- `mo test` green on all seven: 42 passed, 0 failed, 0 skipped.
- `mo test --sim 100` green on all seven: 8 process tests under 100 seeds with 5% faults,
  8 held under faults, 0 passed only without faults; both `Service` invariants kept,
  0 tripped.
- All five `# run:` lines print their `.expected` file byte for byte and exit as declared:
  `check data/demo data/session.txt` (0), `compact data/compact` (0), `serve` (2),
  `serve data/nowhere` (1), `client 127.0.0.1 1 ada GET /notes` (1).
- `mo fmt --check` clean on all seven.
- `mo test --write --sim 100` rewrote every `verified:` line and the `programs/.mo.ids`
  sidecar. `data/demo` and `data/compact` are unchanged by the runs (compaction is
  idempotent on an already-compact log; a check writes only `notes.check.log`, removed
  before and after).

**Wall clock: 17 minutes** (00:43:41 UTC to 01:00:33 UTC, 16 September 2026).

## Loop count by cause

Three failures in all, every one a `mo check` grammar diagnostic in `server.mo`, and every one
fixed by the next edit.

| # | Command | Code | What | Next edit fixed it |
|---|---------|------|------|--------------------|
| 1 | `mo check server.mo` | MO0101 | `fn(kept: Note) ...` — an anonymous function's parameter may not carry a type annotation | yes |
| 2 | `mo check server.mo` | MO0101 | `Next(now): held = now` — a case arm holds one expression, and an assignment is a statement | yes |
| 3 | `mo check server.mo` | MO0102 | `Stopped: break` — same law, for `break` | yes |

- `mo check` failures: 3 (MO0101 ×2, MO0102 ×1). First fix worked every time.
- `mo test` failures: 0.
- Run failures: 0 — all five `# run:` lines matched their `.expected` on the first run.

Not counted as loops, since they are not `check`, `test` or a run: `mo fmt --check` reported
layout differences in four files (`limits.mo`, `service.mo`, `server.mo`, `main.mo`) — a
blank line after a contract block, case arms and list literals that fit on one line, and a
multi-line one-line `if` that wants block form. `mo fmt` fixed all four, and the `verified:`
lines were rewritten afterwards.

## Decisions the spec did not cover

1. **How an id is never reused.** The spec states the rule but not the mechanism. Ids are
   reserved in blocks of 100 under the store key `ids`: before the first create whose id is at
   or past the reserved floor, the service appends `SET ids <next_id + 100>`; on replay
   `next_id` is the larger of that floor and one past the highest id in the log. This is what
   `data/demo/notes.log`'s first line (`SET ids 101`) encodes, and why the check's first create
   is `n_101` and not `n_6`.
2. **`ids` is a store key but not a note.** `/health`'s `notes` is the sum of the per-client
   live-note counts and `clients` is the number of clients holding at least one live note; a
   client whose last note is deleted leaves the table. The reservation key is never counted,
   never listed, and never reachable through a route.
3. **The store key of a note is `<token>/<id>`.** A token cannot hold a slash (the rate
   limiter's token rule), so no client's keys fall under another's — that is what makes
   "a client never reads, changes, or deletes another client's note" checkable as a string
   property in the service's `never`.
4. **The wording of the 400s.** `notes.expected` fixed four of them (`the body is not JSON`,
   `title is missing`, `title must be a string`, `title must be 1 to 200 bytes with no control
   characters`). The two the corpus does not pin were written to match:
   `the body must be a JSON object` and
   `body must be at most 60 KiB with no control characters but newlines`.
5. **A malformed body still takes a token.** A body the Api cannot read becomes a `Refuse`
   call on the service rather than an immediate 400, so 401 still wins over 400 and a 400
   counts against the client's minute. The service answers it without touching the store.
6. **Route precedence.** The method is decided before the token, and an unknown route before
   both: `GET /nowhere` with no token is 404, `PATCH /notes/n_1` with no token is 405, and only
   a route-and-method the service has reaches the 401 check.
7. **"No control characters" read as C0, DEL and C1.** `note.mo`'s own test refuses
   U+0085, so the rule is: no U+0000–U+001F (a newline allowed in a body), no U+007F, and no
   U+0080–U+009F. Sizes are counted in bytes: a title is 1 to 200, a body at most 61,440.
8. **The two 503s.** A change the log did not take is
   `503 {"error": "the log did not take the change"}`; an ask the service does not answer in
   30 seconds is `503 {"error": "the service did not answer in time"}`. Thirty seconds is
   longer than the slowest change the store can make (a 20 s rewrite plus a 5 s rename plus a
   5 s append), so in practice the store decides every 503 and the store is unchanged by it —
   which is what `server.mo`'s wire test asserts.
9. **A full service.** The `state.notes.size <= 1_000_000` invariant is guarded, not tripped: a
   create at 1,000,000 keys is refused with 400
   `the service holds a million notes already`.
10. **`serve`'s banner.** `notes serve <dir>` writes
    `notes: serving <n> notes on 127.0.0.1:<port>` on stdout and then hands the loop to the
    runtime; a log whose last line was cut short is compacted first, so the next change starts
    on a line of its own. No `# run:` line exercises the success path.
11. **What a check writes.** `notes check` replays the folder's log, moves the store to
    `notes.check.log` beside it, and appends every change — the id reservation included — to
    that file only; it is removed before and after, so `data/demo/notes.log` is untouched. A
    file left over from an earlier check that cannot be removed is exit 1.
12. **What "steadied" masks.** Exactly four keys: `created_at` and `updated_at` become
    `"<key>"`, `uptime_ms` and `retry_after_ms` become `<key>`. Masking is per response line
    and repeats, so every note in a listing is steadied.
13. **A change the log refuses still spends its id.** `issued` bumps the counter before the
    log is asked, so a create answered 503 burns `n_k` rather than handing it out twice.
14. **`torn` is sticky.** A log that may end in part of a line is rewritten whole with the
    store's `compact` before the next change; if that rewrite itself fails, the flag stays set
    and the next change tries again. This is what lets work resume once faults stop, and it is
    what `service.mo`'s torn test and the 100-seed fault runs exercise.
15. **One private helper added.** `server.mo` grew `missed`, which reads a 404 as the right
    answer for a move on a note the client does not hold — needed because under injected faults
    a create can be answered 503 and the moves after it then carry no id. Nothing else was
    added beyond the declared signatures.
