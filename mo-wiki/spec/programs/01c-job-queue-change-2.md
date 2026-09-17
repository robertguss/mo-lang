# Program 1, change 2: the folder is checked at open, a failing request never takes the service down, and operators get `/queues`

**Status:** sealed 16 Sep 2026; generation two run 16 Sep, 02:00, read on `plans/erosion-round.md`. The second change to `jobq`, the erosion round's generation two (direction 43, measurement 3). Written by Claude (Fable) on 16 Sep 2026 (three sentences added the same morning, from generation two's decision lists: a forbidden field is ill-formed, `verify` never writes, a missing folder is exit 1) from the incident round 8's fourth oracle found: a log record in a state the API can never produce was refused at open by two of the three services and took the third one down at its first lease, with every request after it hanging. Everything in `01-job-queue.md` and `01b-job-queue-change.md` still holds unless a line below changes it. The shape is an operations ticket after an outage: bad data must be refused at the door, a failure inside one request must cost that request and nothing else, and the people running the service want to see the queues.

## What changes, in one screen

1. **The folder is checked at open.** Every record is checked against the job's rules before the service answers anything; a record that breaks one refuses the folder with exit 1 and a message that names the record's key and the rule. A new command, `jobq verify <dir>`, runs the same check without serving.
2. **One request's failure never takes the service down.** Whatever goes wrong while a request is handled, that request is answered `503` and the next request is answered normally. In particular a store that cannot be written answers `503` to every write and keeps answering reads, and writes resume on their own once the store can be written again.
3. **`GET /queues`** lists every queue with its counts per state.

## The rules a record must meet

A job record is well-formed when it decodes as a job under the current names or the old ones (change 1) and:

```
queued     tries < max_tries; no run_at, worker, lease_until
scheduled  tries < max_tries; run_at present; no worker, lease_until
leased     1 <= tries <= max_tries; worker and lease_until present; no run_at
done       1 <= tries <= max_tries; no run_at, worker, lease_until
dead       1 <= tries <= max_tries; no run_at, worker, lease_until
```

plus the field rules of `01-job-queue.md` (the queue name, the payload, `max_tries` 1 to 100, `backoff_ms` 0 to 3,600,000) and the record's key naming the job's id. A record that carries a field its state forbids (a `worker` on a queued job, a `run_at` on a done one) is ill-formed, not a record with an extra field to ignore. A record that is not well-formed refuses the folder: `jobq serve` exits 1 before binding the port, `jobq verify` exits 1, and both print one line `jobq: <dir>: record <key>: <rule>` for the first such record. A torn last line is still cut off, not refused; an `ids` counter that is not a number, or lower than a job's number, is refused as before.

`jobq verify <dir>` exits 0 and prints `<n> jobs: queued <q>, scheduled <s>, leased <l>, done <d>, dead <x>; next id j_<k>` for a folder that opens, and 2 on a usage error, 1 when the folder cannot be opened or a record fails. A folder that does not exist is a folder that cannot be opened: exit 1. `verify` never writes: the folder's bytes are the same after it as before, a torn last line included.

## Failure inside a request

A response is `503 {"error": "..."}` when the request could not be completed because of a failure in the service rather than in the request: the store could not be written, the queue did not answer within 5 seconds, or anything the implementation did not expect. After a `503` the service is in the state it was in before that request, the job the request named is unchanged, and the next request, from any client, is answered as if the failed one had never arrived. Nothing about a `503` needs an operator: when a store that refused a write can be written again, the next write goes through.

The hidden suite for this change (the third suite, run 16 Sep) made the folder unwritable for a while under load and then writable again; every response during that time is a `2xx` whose record is on disk, a `4xx`, or a `503`, the counts in `/health` never move on a `503`, and after the folder is writable again every write is answered `2xx` with no restart. It will also serve a folder with one ill-formed record and expect the refusal, and kill the service under load as before.

## `GET /queues`

```
GET /queues   → 200 {"queues": [{"name": "emails", "queued": n, "scheduled": n, "leased": n, "done": n, "dead": n}, ...]}
```

Sorted by name, every queue that has at least one job in any state, with a token like every route; `/health`'s totals are the sums of these. A queue whose last job is deleted disappears from the list.

## Usage

```
jobq serve <dir> [--port N]
jobq compact <dir>
jobq verify <dir>
jobq client <host> <port> <token> <method> <path> [<json>]
jobq check <dir> <script>
```

`serve`, `compact`, and `verify` all refuse an ill-formed folder the same way; `compact` on a folder that opens writes only well-formed records.

## Nevers

- A folder with an ill-formed record is never served.
- A failure inside one request never stops the next request from being answered.
- A `503` never leaves a job changed.
- Everything in the earlier lists still holds.

## Contracts and tests the reader expects to see

The well-formedness rule as one function with a `requires`-free signature and a test per state; `verify` tested on the program's own fixture folders and on a hand-written ill-formed one; the unwritable-folder test (make the folder read-only, write, expect `503`, read, expect `200`, make it writable, write, expect `2xx`); `/queues` after creates in three queues and after a delete that empties one; the `--sim` or equivalent fault run with the folder failing mid-run; the program-level check script extended with `verify` and `/queues`.

## Measured, for the round

The round's page (`plans/erosion-round.md`) says what is measured. For the maintainer nothing is asked beyond the report: loops to green by cause, wall-clock, files changed, and the numbered list of decisions this page did not cover.
