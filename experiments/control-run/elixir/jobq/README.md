# jobq

A durable job queue with an HTTP API, in Elixir on OTP 27, to the spec in
`spec/01-job-queue.md` at the root of this repository, with change 1,
`spec/01b-job-queue-change.md`: scheduled jobs, retry backoff, and the `tries`
rename.

A producer creates a job in a named queue — now, or after a delay — a worker
leases the next one for a while and then acks or fails it, a lease that runs out
puts the job back (after its backoff, if it has one), and a job that fails too
often is dead until an operator retries it. Every change is on the disk before
the response that reports it.

## Running it

    mix escript.build

    ./jobq serve <dir> [--port N]      # default port 7900
    ./jobq compact <dir>
    ./jobq client <host> <port> <token> <method> <path> [<json>]
    ./jobq check <dir> <script>

Exit 2 on a usage error, 1 when the directory cannot be opened or the port
cannot be bound.

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
A final line torn by a crash is dropped on replay; a complete line that is not a
record refuses to open. A log the version before change 1 wrote replays as it
is: `attempts` and `max_attempts` are read as `tries` and `max_tries` and a
record with no `backoff_ms` has none, while the service itself writes only the
new names, so a `compact` leaves no old name behind. One line is not a job:
`{"next":N}`, which compaction
writes when the id counter stands above the highest job it kept, so the counter
never goes back over a job that was deleted.

No runtime dependency: OTP's `:json` and `:gen_tcp`, Elixir's `JSON`, and the
HTTP packet mode of `:inet` for parsing. `credo`, `dialyxir` and `stream_data`
are dev and test tools.
