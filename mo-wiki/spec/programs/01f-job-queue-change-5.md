# Program 1, change 5: a lease handed to another worker, and a queue renamed with jobs in flight

The fifth change to `jobq`, the erosion round's generation five (direction 43,
measurement 3). Written by Claude (Fable) on 16 Sep 2026 after generation four,
where a key and an archive beside the log came out whole in all four languages.
Four generations have pressed on durability: what a restart rebuilds, what
compaction keeps, what a kill between two writes leaves. Every maintainer
carried it. This change presses on something else: the queue's own rules. Two of
the `never`s written on the first day ("a job is never held by two workers at
once"; "one record per job under its id") stand in the way of the two features
below, and the maintainer has to change the rule without breaking what the rule
protected. Everything in `01-job-queue.md`, `01b-…`, `01c-…`, `01d-…`, and
`01e-…` still holds unless a line below changes it. The shape is a product
ticket: a worker that is shutting down wants to pass its job to a colleague
without losing the lease, and an operator wants to rename a queue that is busy.

## What changes, in one screen

1. **A lease is handed off.** The worker holding a leased job may hand it to
   another worker by name. The job stays leased, keeps its `lease_until` and its
   `tries`, and from the response on belongs to the new worker: only the new
   worker may ack, fail, or hand it off; the old worker is told `409` from then
   on.
2. **A queue is renamed.** An operator renames a queue, and every job in it, in
   every state, live or archived, is in the new queue from the response on, keys
   included; a lease in flight is unaffected and its ack still works. The rename
   is one durable record, not one per job.
3. **A rename is undone by a rename**, and a name once freed can be used again.

## The handoff

```
POST   /jobs/{id}/handoff    {"to": "<worker>"}    → 200 {job}  |  409  |  404
```

`to` is a token as the lease's is: 1 to 128 bytes, no whitespace; anything else
is `400`. The caller must hold a live lease on the job, by the same rule as
`ack` (`409` otherwise, and a lease that has run out is run out at this look
like any other). `to` equal to the caller's own token is `200` and changes
nothing. The response is the job with `"worker"` set to `to`; `lease_until`,
`tries`, and `updated_at` unchanged apart from `updated_at`. After the handoff
the old worker's `ack`, `fail`, and `handoff` on this job are `409`, and the new
worker's are as if it had leased the job itself. A handoff is a write: it is in
the store before the response, it counts for the chaos switch, and after a
restart or a stop and start the job is leased to the new worker with the same
`lease_until`. The `never` "a job is never held by two workers at once" still
holds: at no look, and in no record, does a job carry two workers.

## The rename

```
POST   /queues/{name}/rename   {"to": "<queue>"}    → 200 {"queue": "<to>", "moved": n}  |  404  |  409
```

`to` is a queue name by the queue name's rule (`400` otherwise). `name` must
have at least one job in any state, live or archived (`404` otherwise, the same
as `/queues` listing it). `to` must have no job in any state, live or archived
(`409 "exists"` otherwise; there is no merging). `to` equal to `name` is `409`
too. `moved` counts every job that changed queue, archived ones included.

From the response on: every job that was in `name` reads, lists, and leases as
being in `to`; `GET /queues` shows `to` with the counts `name` had and no longer
shows `name`; a key that was used in `name` is used in `to` and free in `name`;
`GET /jobs?queue=<to>&key=<k>` finds the job; a lease held on a job of `name` is
a lease on a job of `to`, with the same worker and `lease_until`, and its ack
and fail are `200`; a lease request on `name` is `204`. Renaming `to` back to
`name` restores everything, including the keys. `POST /jobs` into `name` after
the rename starts a fresh queue with that name.

**The record.** A rename is written to the live log as one record naming `name`
and `to`, on disk before the response; it is not written per job. The store
replays it in order with the job records, so a job created into `name` after the
rename record is in `name`, and one created before it is in `to`. `jobq compact`
folds every rename into the job records it rewrites (the compacted log has every
job under its current queue and no rename record). `jobq verify` checks a rename
record's two names by the queue name's rule and refuses the folder on a bad one
as it would on a bad job record, and applies renames when it counts. The archive
is not rewritten by a rename: an archived job's queue is the live log's renames
applied to the archive record's queue, at open and at every read. Until the
archive is compacted, an archive record may carry a queue name that has since
been renamed; `compact` rewrites the archive with current names.

**Under a kill.** A rename is one write, so a kill leaves it wholly on the disk
or wholly off it; the reopened folder shows either every job moved or none. The
hidden suite will rename a queue under a load of leases, acks, keyed creates,
and handoffs, kill the service during it, reopen the folder, and check that
every job is in exactly one queue, that every key is used once per queue, that
every acknowledged write is present, and that no job is held by two workers.

## Usage

Unchanged from change 4. The two new routes are the whole of it.

## Nevers

- A job is never held by two workers at once (unchanged; a handoff moves the
  lease, it does not copy it).
- A handoff never changes a lease's `lease_until` or a job's `tries`.
- A rename never leaves a job in two queues, or in none.
- A rename never lets a key name two jobs in one queue.
- A rename never touches a lease: the same worker holds it until the same
  `lease_until`.
- Everything in the earlier lists still holds.

## Contracts and tests the reader expects to see

The handoff as a state transition with its `requires` (the caller holds the
lease) and its `ensures` (the job leased to `to`, `tries` and `lease_until`
unchanged), tested: from the holder; from a stranger; after the lease ran out;
to the holder itself; twice in a row (A to B, B to C, then A's ack `409`, C's
`200`); across a restart. The rename as a pure step over the board and the key
map, tested with jobs in every state, with keys, with a lease in flight whose
ack succeeds after; the `409` on an existing target and on a key clash that
cannot happen because targets are empty (the test says why the clash needs no
code); the replay with a rename record between job records; `compact` on a log
with two renames and the archive with an old name; `verify` on a bad rename
record; the `--sim` or equivalent fault run with the rename's write failing; the
program-level check script extended with a handoff and a rename. The report says
which `never` or `invariant` the maintainer had to change or add, and which
tripped during the work.

## Measured, for the round

The round's page says what is measured. For the maintainer nothing is asked
beyond the report: loops to green by cause, wall-clock, files changed, and the
numbered list of decisions this page did not cover.
