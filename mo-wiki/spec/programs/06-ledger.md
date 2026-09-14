# Program 6: `ledger`, a payments ledger whose invariants are the point

The spec altitude of program 6 from the program menu, written by Claude (Fable) in session 6, 14 Sep 2026, after rounds 6 and 7 found that a job queue comes out correct in Mo, Go, and Python alike and that no invariant a job queue can state is one a message can break. A ledger is the program where the invariants are the product: money is conserved, a refund never exceeds its charge, a hold never exceeds what is available, and every one of those can be broken by a message that arrives at the wrong moment or by a store write that fails halfway. Robert reads this page, the exposed signatures, the contracts, the `never`s, the `invariant`s, and the `verified:` lines. A worker implements it in Mo; round 8 puts it against Go and Python under a hidden defect suite.

## Intent

`ledger` keeps accounts and moves money between them by double-entry postings: every transfer debits one account and credits another in one journal entry, and the sum over all accounts of every entry is zero. It holds funds for a card authorization, captures or releases the hold, refunds a capture up to its amount, and settles a day's entries into a statement. Every change is durable before it is answered, every request carries an idempotency key so a retried request is answered the same way once, and every answer is derived from the journal, never from a counter kept beside it.

## The package story

The store is `Recipes.Store`, implemented in the program's own modules as `jobq` did, checked with `mo check --recipe`. No other recipe. Money is a `type Money = Int64 where value >= 0` in minor units; an amount is never a float.

## Accounts and entries

An account has an `id` (`a_` and a counter), a `name` (1 to 64 bytes of letters, digits, `-`, `_`), a `currency` (three uppercase letters), an `overdraft` limit (0 or more, default 0), and a balance that is the sum of its postings. An entry has an `id` (`e_` and a counter), a `kind` (`transfer`, `hold`, `capture`, `release`, `refund`, `settlement`), `postings` (a list of `(account, amount)` where a negative amount is a debit), a `key` (the idempotency key that made it), `at`, and for a hold its `expires_at`, for a capture, release, or refund the `hold` or `capture` it answers. A hold reduces an account's available balance without moving money; a capture turns a hold into a transfer; a release cancels it; a refund is a transfer back, at most the captured amount in total across refunds.

## The API

Every request carries `authorization: Bearer <token>` (`401` without one) and, for every request that changes something, `idempotency-key: <key>` (1 to 128 bytes; `400` without one). A key seen before with the same body is answered with the same status and body as the first time; with a different body it is `409`.

```
POST   /accounts                {"name": "ada", "currency": "USD", "overdraft": 0}   → 201 {account}
GET    /accounts/{id}            → 200 {account}  |  404
POST   /transfers               {"from": "a_1", "to": "a_2", "amount": 1500}       → 201 {entry}  |  422 insufficient
POST   /holds                   {"account": "a_1", "amount": 5000, "ttl_ms": 60000} → 201 {entry}  |  422
POST   /holds/{id}/capture      {"amount": 4200}   → 201 {entry}  |  409 released, expired, or captured  |  422 over the hold
POST   /holds/{id}/release      → 201 {entry}  |  409
POST   /captures/{id}/refund    {"amount": 1000}   → 201 {entry}  |  422 over what remains
GET    /entries?account=a_1&kind=k  → 200 {"entries": [...]}  by id, at most 100
POST   /settle                  {"day": "2026-09-14"}  → 201 {statement}: per account, the opening balance, the entries, the closing balance
GET    /health                  → 200 {"accounts": n, "entries": n, "held": total, "uptime_ms": n}   no token
```

`{account}` carries `id`, `name`, `currency`, `overdraft`, `balance`, `available` (balance minus live holds), `created_at`. A transfer across currencies is `422`. `422` bodies say which rule refused and by how much. A body that is not JSON, a missing field, or the wrong shape is `400`; the wrong method `405`; an unknown route `404`. Amounts are integers; a negative or zero amount is `400`.

## Durability and time

Every entry is in the store before its response is sent, one record per entry and one per account under their ids, and the idempotency table under the key. On start the store is replayed and every balance is recomputed from the postings; a stored balance is never trusted over the sum. A hold expires at `expires_at` by the clock `main` holds, checked at the next look (any request on the account, a capture, a release, health) and by a delayed message the ledger sends itself at `ttl_ms` (`send(Expire(id), delay:)`), whichever comes first; an expired hold is released in the journal as a `release` entry with `reason: expired`. The answer to a capture or release that races an expiry is decided by the journal's order, never by two clocks. Every call that can wait carries `within:`, derived from the request's `reply_by` wherever an asker exists.

## Nevers, over history

- Money is never created or destroyed: for every entry, the postings sum to zero.
- A refund never exceeds its charge: the refunds of a capture never sum past the captured amount.
- A capture never exceeds its hold, and a hold is never captured or released twice.
- An account never goes below minus its overdraft, counting live holds against it.
- A response is never sent before its entry is durable.
- A card number never reaches an entry or a statement (a 16-digit run in a `name` or a `reason` is refused).
- An idempotency key never produces two entries.

## Invariants, on the ledger process

The spec expects these on the process that owns the journal, and each must be trippable by a message the process accepts, which is the reason this program exists: a transfer whose second posting fails to be written, a capture that lands after a release, a refund that lands after a partial refund, a retry that lands twice. The report says, for each invariant kept, which message trips it in a test, and for each left out why no message can.

- The sum of all balances equals the sum of all overdrafts drawn, and both equal the journal's postings.
- Total held never exceeds the sum of available balances before the holds.
- Every live hold has a future `expires_at` or a pending `Expire`.
- The idempotency table names an entry that exists.

## Contracts the reader expects to see

`requires` on names, currencies, amounts, keys, and `ttl_ms` (100 to 86,400,000), each with its `rejects`; `ensures` on `transfer` that the two accounts' balances moved by the amount and nothing else did; `ensures` on `capture` that the hold is closed and the entry's postings equal the captured amount; `ensures` on `settle` that opening plus entries equals closing for every account.

## Usage

```
ledger serve <dir> [--port N]      default port 7910
ledger compact <dir>
ledger client <host> <port> <token> <method> <path> [<json>] [--key K]
ledger check <dir> <script>        serve on a free port and play the script through the client
```

Exit 2 on a usage error, 1 if `<dir>` cannot be opened or the port cannot be bound.

## Tests the reader expects to see

Unit tests for every route and status; the store recipe's tests through `mo check --recipe`; a property that any sequence of valid transfers keeps every entry's postings at zero and every balance at the postings' sum; a race in which two captures of one hold arrive at once and exactly one is `201`; a hold that expires by the delayed message and one that expires at a look, both leaving a `release` entry; a retry with the same key answered identically and one with a different body answered `409`; a replay that creates, transfers, holds, stops, starts, and finds every balance equal to the postings; a `--sim 100` run under injected `Fs` failures in which every response was either correct or a `503` that changed nothing, and no `never` tripped; and a test that plants a bug (a transfer written as two records) and shows which invariant or `never` catches it, so the report can say whether the checks earn their keep.

## Measured

Transfers a second with 1 and with 32 clients over a local socket, under `mo run` and as a binary; resident memory at 100k entries; replay of a 1M-entry journal; the `within:` count with chosen and derived; the invariants kept and tripped; loops to green by cause; wall-clock; the Q16 ledger; the runtime-surface questions the worker wanted to ask. Round 8 adds the hidden suite, the loop time, and the dependency count against Go and Python.
