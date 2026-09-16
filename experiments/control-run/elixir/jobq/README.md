# jobq

A durable job queue with an HTTP API, in Elixir on OTP 27, to the spec in
`spec/01-job-queue.md` at the root of this repository, with change 1,
`spec/01b-job-queue-change.md` (scheduled jobs, retry backoff, and the `tries`
rename) and change 2, `spec/01c-job-queue-change-2.md`: the folder checked at
open, a failing request that never takes the service down, and `GET /queues`.

A producer creates a job in a named queue — now, or after a delay — a worker
leases the next one for a while and then acks or fails it, a lease that runs out
puts the job back (after its backoff, if it has one), and a job that fails too
often is dead until an operator retries it. Every change is on the disk before
the response that reports it.

A folder is read before it is served, and a record in a state the API could
never have produced refuses it by name. Once it is open, nothing that goes
wrong inside one request reaches the next one: the request is answered `503`
and the service is left as it was, a store that cannot be written answers
`503` to every write while it goes on answering reads, and the writes resume
on their own once it can be written again — no restart, no operator.

## Running it

    mix escript.build

    ./jobq serve <dir> [--port N]      # default port 7900
    ./jobq compact <dir>
    ./jobq verify <dir>
    ./jobq client <host> <port> <token> <method> <path> [<json>]
    ./jobq check <dir> <script>

Exit 2 on a usage error, 1 when the directory cannot be opened or the port
cannot be bound. `serve`, `compact`, and `verify` all read the folder first and
all refuse an ill-formed record the same way, one line and exit 1:

    jobq: /tmp/jobq: record j_2: a leased job has a worker and a lease_until

`verify` is that check on its own, and says what it found:

    $ ./jobq verify /tmp/jobq
    5 jobs: queued 1, scheduled 0, leased 2, done 1, dead 1; next id j_7

    ./jobq serve /tmp/jobq &
    ./jobq client 127.0.0.1 7900 alice POST /jobs '{"queue":"emails","payload":"hi","max_tries":3}'
    ./jobq client 127.0.0.1 7900 bob POST /queues/emails/lease '{"lease_ms":30000}'
    ./jobq client 127.0.0.1 7900 bob POST /jobs/j_1/ack

A job may be created with a `delay_ms` and wait in `scheduled` until its
`run_at`; a job with a `backoff_ms` goes back to `scheduled` rather than
`queued` when a try does not take; a dead job goes back to its queue with
`POST /jobs/{id}/retry` and `tries` at 0.

    ./jobq client 127.0.0.1 7900 alice POST /jobs '{"queue":"emails","payload":"hi","max_tries":3,"delay_ms":60000,"backoff_ms":5000}'
    ./jobq client 127.0.0.1 7900 alice POST /jobs/j_2/retry

`GET /queues` is what an operator reads: every queue that has a job, by name,
with its counts per state. `/health`'s totals are the sums of the rows, and a
queue whose last job is deleted leaves the list.

    ./jobq client 127.0.0.1 7900 anyone GET /queues

## The checks

    mix compile --warnings-as-errors
    mix dialyzer
    mix credo --strict
    mix test
    ./check.sh                        # the program-level check, over a socket
    mix run bench/bench.exs           # the measurements

## The shape of it

    Jobq.Server            one service: the tree, :rest_for_one
      Jobq.Store           the log, one JSON record a line, fsynced in batches
      Jobq.Queue           every job, and the only process that moves one
      Jobq.Http.Listener   the socket, the connections, ten acceptors
        Jobq.Http.Socket   owns the listening socket, knows the bound port
        Task.Supervisor    a process per connection
        Jobq.Http.Acceptor accept, hand over, accept

Each batch goes through a log the store opens for it and closes again, which
is what makes a folder that has been made unwritable visible to the very next
write rather than to the next restart, beside an `fsync` that costs more than
both. A batch that does not reach the disk moves the store to a new *epoch*:
the waiters are told `503`, the queue is told the epoch and reads its jobs back
off the log — the state the disk agrees with — and a commit already on its way
under the old epoch is refused rather than written. So a request that was told
`503` left the job it named exactly as it found it, and the next request, from
any client, is answered as if it had never arrived.

A request is answered by the store, not by the queue. The queue takes the
operation, moves the job in memory, and hands the store the records and the
reply it owes the caller; the store writes them, `fsync`s, and only then
answers. Records that pile up while an `fsync` is in flight are written and
synced together, so a busy service pays one `fsync` for many jobs and no reply
is ever ahead of the disk.

A lease is a deadline, not a timer, and so is a scheduled job's `run_at`. Every
operation takes a *look* first: leases that have run out by the clock are moved
on — back to `queued`, to `scheduled` when the job has a backoff, or to `dead` on
its last try — and scheduled jobs whose `run_at` has passed are queued. Those
moves are written before the operation's own reply. An idle service takes the
same look on a tick, so a lease that runs out or a delay that comes due with
nobody asking is still freed.

The store is an append-only log of one JSON object per line under the job's id,
last record of an id wins, a `{"id":...,"deleted":true}` tombstone removes it.
A final line torn by a crash is dropped on replay; a complete line that is not
JSON refuses to open, and so does a record that is not well-formed — the rule
is `Jobq.Job.check_record/1`, one function over the whole of it, and the
refusal names the record's key and the rule it broke. A log the version before
change 1 wrote replays as it is: `attempts` and `max_attempts` are read as
`tries` and `max_tries` and a record with no `backoff_ms` has none, while the
service itself writes only the new names, so a `compact` leaves no old name
behind. One line is not a job: `{"next":N}`, which compaction writes when the
id counter stands above the highest job it kept, so the counter never goes back
over a job that was deleted; a counter that is not a number, or no higher than
an id the log carries, refuses the folder too.

No runtime dependency: OTP's `:json` and `:gen_tcp`, Elixir's `JSON`, and the
HTTP packet mode of `:inet` for parsing. `credo`, `dialyxir` and `stream_data`
are dev and test tools.
