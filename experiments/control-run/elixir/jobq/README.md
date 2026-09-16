# jobq

A durable job queue with an HTTP API, in Elixir on OTP 27, to the spec in
`spec/01-job-queue.md` at the root of this repository.

A producer creates a job in a named queue, a worker leases the next one for a
while and then acks or fails it, a lease that runs out puts the job back, and a
job that fails too often is dead. Every change is on the disk before the
response that reports it.

## Running it

    mix escript.build

    ./jobq serve <dir> [--port N]      # default port 7900
    ./jobq compact <dir>
    ./jobq client <host> <port> <token> <method> <path> [<json>]
    ./jobq check <dir> <script>

Exit 2 on a usage error, 1 when the directory cannot be opened or the port
cannot be bound.

    ./jobq serve /tmp/jobq &
    ./jobq client 127.0.0.1 7900 alice POST /jobs '{"queue":"emails","payload":"hi","max_attempts":3}'
    ./jobq client 127.0.0.1 7900 bob POST /queues/emails/lease '{"lease_ms":30000}'
    ./jobq client 127.0.0.1 7900 bob POST /jobs/j_1/ack

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

A lease is a deadline, not a timer. Every operation takes a *look* first: leases
that have run out by the clock are moved back to `queued`, or to `dead` on their
last attempt, and those moves are written before the operation's own reply. An
idle service takes the same look on a tick, so a lease that runs out with nobody
asking is still freed.

The store is an append-only log of one JSON object per line under the job's id,
last record of an id wins, a `{"id":...,"deleted":true}` tombstone removes it.
A final line torn by a crash is dropped on replay; a complete line that is not a
record refuses to open. One line is not a job: `{"next":N}`, which compaction
writes when the id counter stands above the highest job it kept, so the counter
never goes back over a job that was deleted.

No runtime dependency: OTP's `:json` and `:gen_tcp`, Elixir's `JSON`, and the
HTTP packet mode of `:inet` for parsing. `credo`, `dialyxir` and `stream_data`
are dev and test tools.
