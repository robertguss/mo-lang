# REPORT: ledger regenerated

Every function body in `examples/programs/ledger/` (fourteen modules, 3,148 lines of
signatures, contracts, `never`s, `invariant`s and tests) was written from the program's spec
(`mo-wiki/spec/programs/06-ledger.md`), the signatures and contracts left in the files, the
tests as written, `data/demo`, `data/session.txt` and the five `.expected` files. The tests
were not touched; no other program was touched.

## Done-when

- `mo check` green on all fourteen modules; `mo check --recipe Recipes.Store.Store store.mo`
  reports **11 signatures match** and the recipe's own eight tests pass.
- `mo test` green on all fourteen: 78 tests and one property (200 seeds), 0 failed, 0 skipped.
  Under `mo test --sim 100`, `journal.mo` (11 tests) and `server.mo` (2 tests) hold under
  faults, at 5% and at the `# sim: --faults 20 --until 0.5` the corpus gives `server.mo`;
  0 tests passed only without faults.
- Three of the journal's four `invariant`s are tripped by a message in a `test rejects`
  (a transfer whose second posting was not written, holds that keep more than the accounts
  have, a retry that landed twice, and the planted bug — a transfer written as two records,
  which trips the first). The fourth, *every live hold expires later than now, or an Expire
  for it is on its way*, is kept and no seed's message tripped it.
- All five `# run:` lines print their `.expected` file byte for byte with the right exit code:
  `check data/demo data/session.txt` (0), `compact data/compact` (0), `serve` (2),
  `serve data/nowhere` (1), `client 127.0.0.1 1 ada GET /health` (1).
- `mo fmt --check` green on all fourteen.
- `mo test --write --sim 100` has rewritten every `verified:` line and the `.mo.ids` sidecar.
- `data/demo` and `data/compact` are byte-identical to what they were before the runs.

## Wall-clock

**41 minutes 36 seconds**, 01:44:29 to 02:26:05 UTC on 16 Sep 2026, from reading
`examples/README.md` to the last green run.

## Loops to green, by cause

Nine loops. **Every first fix worked**; no failure needed a second edit.

| # | Command | Cause | First fix worked |
|---|---|---|---|
| 1 | `mo check index.mo` | `MO0101` expected `end` — a one-line anonymous function written without its `end` (`.filter(fn(a) a != "")`) | yes |
| 2 | `mo check index.mo` | `MO0403` `Time.fixture()` is a Time for tests — used in the test helper `t0()`, which is an ordinary function | yes |
| 3 | `mo test settle.mo` | 2 tests failed (`a day's statement opens…`, `a day is settled once…`): the fixture `busy()` held for exactly one hour and captured exactly one hour later, so the hold had expired at the capture | yes |
| 4 | `mo check teller.mo` | `MO0212` a one-field variant is matched by position — `SettleDay(day: _)` | yes |
| 5 | `mo test teller.mo` | `a settlement under a key…` failed: the module's `t0()` was 2026-01-01, so settling 2026-09-14 was a day that had not begun | yes |
| 6 | `mo check desk.mo` | `MO0307` `s` is bound but never used — a lambda parameter that should have been `_` | yes |
| 7 | `mo check journal.mo` | `MO0101` a case arm holds one expression after its `:` — an assignment written inline on an arm | yes |
| 8 | `mo test journal.mo` | `a retry with the same key…` failed: the test helper `call` used the key as the request a key is compared by, so a retry with a different body compared equal and was answered 201 instead of 409 | yes |
| 9 | `mo fmt --check` | 13 of 14 files unformatted (line wrapping, and the blank line the shape wants after a contract block) — fixed by `mo fmt` | yes |

By kind: **5 diagnostics** (`MO0101` ×2, `MO0403`, `MO0212`, `MO0307`), **3 failing tests**,
**1 formatting sweep**, **0 failing runs** — every one of the five `# run:` lines matched its
`.expected` file byte for byte on its first run.

Nine of the fourteen modules were green on the first `mo check` + `mo test`: `money`, `entry`,
`book`, `store`, `records`, `api`, `server`, `check`, `main`. The five that were not —
`index`, `settle`, `teller`, `desk`, `journal` — each took one fix.

One loop was not the toolchain's: the Python helper that pasted bodies into the files had an
infinite loop of its own, which cost two 120-second command timeouts. It is not counted above,
since no `mo` process failed.

## Decisions the spec did not cover

1. **What each kind of entry carries in its JSON.** The spec lists an entry's fields but not
   which kinds carry which. A transfer is written with `amount` and no `account`; a settlement
   with neither; a hold, capture, release and refund with both. `expires_at`, `hold`,
   `capture`, `reason` and `day` trail after `at`, in that order, each only when it is there.
   Recovered from `entry.mo`'s tests and `ledger.expected`.
2. **Two shapes of error body.** A rule's refusal is
   `{"error": …, "rule": …, "by": n}`; a 401, a 405, a 404 on a route or a look, a 400 from the
   API, and the idempotency 409 are a plain `{"error": …}`. `ledger.expected` shows both, so a
   refusal that comes from `Ledger.Book` carries its rule and a refusal that comes from
   `Ledger.Api` or the teller's own look does not.
3. **The rules' names**: `no_account`, `same_account`, `currency`, `insufficient`, `no_hold`,
   `closed`, `over_hold`, `no_capture`, `over_capture`, `settled`, `future_day`. Only
   `insufficient`, `currency`, `no_account`, `closed`, `over_hold`, `over_capture`, `settled`
   and `future_day` are pinned by a test or an `.expected` file; `same_account`, `no_hold` and
   `no_capture` are mine.
4. **`by` is the shortfall**: how much an amount missed by, and 0 for a refusal that is not
   about an amount. `same_account` and `currency` are 422 with `by: 0`; a transfer to an
   account that is not there is 404 *with* a rule name, while `GET /accounts/{id}` for one
   that is not there is a plain 404.
5. **The clearing account.** `clearing:<CUR>`, one per currency, credited by a capture and
   debited by a refund. It is not an `Account`: it has no record in the store, no name, and no
   overdraft, so `covered?` counts only the accounts the book opened as what the accounts have
   before the holds. It does appear as a line in a statement, with an empty name.
6. **Which look releases which expired hold.** The spec says "any request on the account, a
   capture, a release, health". I made a per-account command look only at that account's holds
   and made `health` *and* `settle` look at every hold, since a settlement reads every account.
7. **The batch's wire form.** `BEGIN n` followed by n `SET` lines; a replay holds the lines of
   an open batch and applies them only at its last, so a log that ends inside a batch leaves
   the whole batch out and is `cut`. The spec asked for "replays whole or not at all" and
   named no form.
8. **A key's store name.** `i_` and the key's bytes in hex, so a key of any bytes is a store
   key — the store's own `key?` forbids spaces and control characters, which an idempotency
   key allows.
9. **What a key's row keeps.** The request it is compared by (`METHOD path\nbody`), the status,
   what it made (`e_5`, `a_3` or `""`), and the body **only** for a refusal and for a
   settlement. An account's or an entry's body is shown again from the book, so a retry reads
   the entry as the book now has it; a settlement's is kept, since an account opened later
   would change a statement recomputed.
10. **The batch boundary is a collect, not a call.** A call is staged against the book with
    every call before it and its answer waits; the append happens when an asker collects, so
    one write covers every call staged since the last. The spec said only "durable before it
    is answered". This is what makes the `Sent` never (`changed and !durable`) meaningful.
11. **When an `Expire` is armed.** As soon as a hold is *staged*, not once it is durable — so
    a hold that is staged and never collected is still covered when its expiry passes. After a
    flush the log refused, an `Expire` is sent again for every live hold with none on its way.
    An `Expire` that finds its hold not yet expired re-arms instead of releasing.
12. **What a refused batch does.** Every call in it is answered 503 and the book goes back to
    the one the log holds; when the append may have left part of the batch on disk, the log is
    rewritten whole from that book at once, so the 503 changed nothing. `Unwritten` (the log is
    as long as before) needs no rewrite; anything else does.
13. **The statement's order and membership.** Accounts by number, then the clearing accounts in
    byte order; an account the book opened appears even with no entries on the day; a clearing
    account appears when it moved in any entry the statement reads.
14. **A statement's `settlement` id** is the number the settlement entry will take, and the
    statement is computed over every entry numbered below it — which is what makes the same
    statement come back whenever it is asked for.
15. **The check transcript.** `at`, `created_at`, `expires_at` and `uptime_ms` are masked, and
    the clock's day is replaced by `<today>` after them (so a time is not half-masked twice).
    A `wait N` line sends a request to a listener of the check's own that nothing ever accepts
    and prints `waited N ms`.
16. **Small API defaults**: a release with no body, or with a body that names no reason, is
    `reason: "released"`; `overdraft` left out is 0; a 16-digit run in a name, a reason or an
    idempotency key is refused (400) before any other rule on that field.
