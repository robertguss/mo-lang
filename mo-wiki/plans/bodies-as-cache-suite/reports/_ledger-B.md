# REPORT: `examples/programs/ledger/` regenerated from its spec

Every function body in the fourteen modules of program 6 was written again from
`mo-wiki/spec/programs/06-ledger.md`, the modules' own intents, signatures, contracts, `never`s,
`invariant`s and tests, and the `.expected` transcripts. The tests were not touched, and no other
program was touched.

## Done-when

- `mo check` is green on all fourteen modules (`store.mo`: *recipe Recipes.Store.Store: 11
  signatures match*).
- `mo test` is green on all fourteen: 78 tests, 0 failed, 0 skipped, plus one property at 200 seeds.
- `mo test --sim 100` is green on all fourteen; `journal.mo` reports *invariants (kept 4, tripped 3)*
  and `server.mo` holds under `--faults 20 --until 0.5`.
- All five `# run:` lines of `main.mo` print their `.expected` file byte for byte and exit with the
  code on their `# exit:` line (`check` → 0, `compact` → 0, `serve` → 2, `serve data/nowhere` → 1,
  `client 127.0.0.1 1 …` → 1). The `check` run was repeated to confirm it is deterministic.
- `mo test --write --sim 100` has rewritten every `verified:` line and the `programs/.mo.ids`
  sidecar; the sidecar diff touches only the fourteen `ledger/*.mo` rows.

## Wall-clock

46 minutes 32 seconds (2026-09-16T01:43:53Z → 02:30:25Z), one session, no parallel workers.

## Loops to green, by cause

Six failing `mo` invocations in all. Every one of the six was fixed by the next edit.

| # | Module | Cause | Fix | First fix worked |
|---|---|---|---|---|
| 1 | `index.mo` | `MO0403` — `Time.fixture()` in the non-test helper `t0()` | `Time.from_parts(2_026, 1, 1, 0, 0, 0)` | yes |
| 2 | `book.mo` | property: `requires key?(key)` tripped — the walk's key `"w#{n}"` spelled a 20-digit run, which `card_run?` refuses | `"w#{n % 100_000}"` | yes |
| 3 | `desk.mo` | `MO0102` — `return` on a case arm's own line | `flushed` restructured as a block-form `if` value plus a `took` helper | yes |
| 4 | `desk.mo` | `MO0307` — anonymous-function parameter `s` bound but never read | renamed to `_` | yes |
| 5 | `journal.mo` | `MO0303` — `readied` took 8 parameters, the limit is 6 | the four carried values grouped into a private `Started` struct | yes |
| 6 | `journal.mo` | test failure: *a retry with the same key … one with a different body is 409* — the test helper `call` used the key as the whole request fingerprint, so a different body compared equal | the request became `"#{key} #{Json.encode(command)}"` | yes |

By kind: four checker diagnostics (MO0403, MO0102, MO0307, MO0303), one contract tripped by a
property, one test expectation. Ten of the fourteen modules — `money`, `entry`, `settle`, `teller`,
`store`, `records`, `api`, `check`, `main`, `server` — were green on their first `mo test`, and all
five program runs matched their `.expected` file on the first `mo run`.

One correction was made before any `mo` invocation and is not counted above: `money.mo`'s `day?`
first used a `try?` form that Mo does not have, replaced by a `case` on `Time.parse` while writing.

## Decisions the spec did not cover

1. **Refusal rule names.** The spec fixes the statuses but not the `rule` strings. Chosen, and made
   to match the wording already in `ledger.expected`: `no_account`, `same_account`, `currency`,
   `insufficient`, `over_hold`, `closed`, `no_hold`, `over_capture`, `no_capture`, `settled`,
   `future_day`. `refusal_body` writes `{"error": …, "rule": …, "by": N}`; a refusal that never
   reaches a rule (a missing account on `GET /accounts/{id}`, a listing of an account that is not
   there) is written as `{"error": …}` alone.
2. **The shape of an entry's JSON per kind.** A transfer carries `amount` and no `account`; a
   settlement carries neither; a hold, capture, release and refund carry both. The order is
   `id, kind, [account,] [amount,] postings, key, at`, then `expires_at`, `hold`, `capture`,
   `reason`, `day` as each applies.
3. **The clearing account.** `clearing:<CUR>`, one per currency, with no `Account` record of its
   own — so it is never counted by the overdraft `never`, never written as an account record, and
   appears in a statement only for a day it moved on.
4. **Statement order.** The book's accounts first, by their number zero-padded to twenty digits
   (so `a_10` follows `a_9`), then the clearing accounts that moved, by id.
5. **`Statement.settlement`** holds the entry number the statement was cut at, shown as `e_N`; a
   settlement shows every entry numbered below its own, which is what makes the same statement
   reproducible later.
6. **The store's name for a key** is `i_` and the key's bytes in lowercase hex, and a key row is
   `{"made", "status", "request", "body"}` with `made` first — both read off `data/demo/ledger.log`,
   which the spec does not describe.
7. **The request a key is compared by** is `"<METHOD> <path>\n<body>"` (`Api.fingerprint`).
8. **What a key row keeps.** A body only for a refusal (status ≥ 400) and for a settlement, whose
   statement would otherwise change once a later account opens; every other repeat is derived again
   from what the key made (the entry as it is, the account as it stands).
9. **Which accounts a call is a "look" on.** The account(s) the command names; the hold's account
   for a capture or a release; the capture's account for a refund; every account for health; none
   for opening an account or for settling a day.
10. **Paging.** Entries, closed holds and captures in pages of 256 by number; key rows in 1,024
    buckets by `hash * 31 + byte`, the same mixing the store uses for its 256 buckets.
11. **Listings.** Kept as lists under `"<account>/<kind>"`, an empty part standing for "all", and
    capped at a hundred when the number is pushed rather than when the list is read.
12. **`balanced?`** is *no entry's postings are unbalanced* **and** *the balances sum to the
    journal's postings*. The planted bug (a transfer written as two records) satisfies the second
    conjunct exactly — the balances read as a transfer's would — and is caught by the first.
13. **`covered?`** counts only the accounts the book opened, each as balance plus overdraft;
    clearing accounts have no overdraft and are left out.
14. **The batch on the log** is a `BEGIN <n>` line and its n `SET` lines; a replay takes all of them
    or, when the log ends inside the batch, none, and the table is then `cut`. `BEGIN 0` is a bad
    line.
15. **Expire timing.** An `Expire` is sent when a hold is *staged*, at `delay_to(expires_at, now)`,
    which is a second for a hold already past, so a release the log refused is tried again. A
    refused flush rolls the book back to what the log holds and re-arms an `Expire` for every live
    hold in that book, which is what keeps the third invariant true across a rollback.
16. **The journal's message shapes.** `Serve` stages, flushes and collects in one update; `Collect`
    flushes only while its ticket is still waiting, so calls staged together share one append; the
    acceptor's `Idle` asks for a `Flush` bounded at 10 seconds.
17. **The worker's two deadlines**, since an exchange carries none of the client's: 10 seconds to
    stage, 30 to collect, and a timed-out collect is 503.
18. **A journal that has not opened retries opening at every message**, not only on `Open` (the
    private `readied` helper), so a fault window during start does not leave it closed for the rest
    of the run.
19. **`wait N` in a check script** is a request to a listener of the check's own that nothing ever
    accepts, timing out after N ms, printed as `waited N ms`.
20. **`steady`** masks `at`, `expires_at`, `created_at` and `uptime_ms`, then replaces the clock's
    day with `<today>`; nothing else is touched.
21. **Private helpers the stripped signatures did not name** were added where a nested closure, the
    parameter limit or the no-`return`-on-an-arm rule forced one: `value_fields` (entry);
    `summed_in` (book, settle); `item_of`, `shown_item` (settle); `whole_text`, `pending_taken`,
    `emptied`, `applied_if` (store); `taken_pending`, `emptied`, `bad_at`, `entry_pairs`,
    `key_pairs` (records); `took` (desk); `made_under` (teller); `Started`, `readied`, `armed`,
    `made` (journal); `balance_in` (server).
22. **Four signatures the stripper had cut mid-return-type** were restored:
    `Index.pushed → Map(String, List(UInt64))`, `Book.captured`, `Book.released`, `Book.refunded →
    Result(Moved, Refusal)`, and `Records.flushed_to → Result(Table, StoreError)`. The contracts on
    the three `Book` functions went with them and were written again from the `test rejects` each
    must trip: `requires key?(key)` on `captured`, `requires reason?(reason)` on `released`,
    `requires amount?(amount)` on `refunded`, plus the `ensures` the spec asks for on a capture.
23. **Test fixtures the spec left open.** Ada's overdraft is 10,000 and grace's 0 throughout;
    `Teller.t0()` and `Records.t0()` are 2026-09-14T10:00:00Z so that settling that day is not a
    future day; `Journal.started` makes the folder `d` before it opens, since the journal tests do
    not.
