module Jobq.Moves
expose Command, Call, Outcome, Served, serve, swept, unwritten, shifted

use Jobq.Board{find, placed, removed, oldest_queued, due_in, due_anywhere, listed}
use Jobq.Books{Step, Books, Place, Moment, Committed, committed, opened, unopened}
use Jobq.Job{Job, State, job, leased, acked, failed, ran_out, run_out?, holds?, payload?, id_of, number_of}
use Jobq.Journal{deleted_from}
use Jobq.Store{StoreError}

intent "What each call does to the jobs, given the time: every change a call makes, and every lease run out that its look finds, goes to the log in one write before the books change or the call is answered; a change the log did not take is 503 with the books as they were, and one that may have left part of a line makes the next change rewrite the log whole first."

# What a client asks, once its request is read and its fields keep their rules.
enum Command
  Create(queue: String, payload: String, max_attempts: UInt64)
  Fetch(id: String)
  Listing(queue: Option(String), status: Option(State))
  Remove(id: String)
  Lease(queue: String, lease_ms: UInt64)
  Ack(id: String)
  Fail(id: String, reason: String)
end

# A command and the token that sent it, which names the worker on a lease.
struct Call
  worker: String
  command: Command
end

enum Outcome
  Made(job: Job)
  Found(job: Job)
  Handed(job: Job)
  Listed(jobs: List(Job))
  Removed
  Empty
  Missing
  Conflict(reason: String)
  Unavailable(reason: String)
end

struct Served
  books: Books
  outcome: Outcome
  steps: List(Step)
end

fn serve(fs: Fs, books: Books, call: Call, at: Moment) : Served
  # body gone; regenerate
end

# An id is spent whether or not its job reaches the log, so no id is handed out twice; the log
# reserves ids a thousand at a time, so a replay never hands out one it handed out before.
fn creating(fs: Fs, books: Books, made: Job, at: Moment) : Served
  # body gone; regenerate
end

fn fetching(fs: Fs, books: Books, id: String, at: Moment) : Served
  # body gone; regenerate
end

# A listing looks at the leases run out in its queue, or in every queue, before it lists.
fn listing(fs: Fs, books: Books, queue: Option(String), status: Option(State), at: Moment) : Served
  # body gone; regenerate
end

fn removing(fs: Fs, books: Books, id: String, at: Moment) : Served
  # body gone; regenerate
end

fn deleted(fs: Fs, looked: Committed, job: Job, at: Moment) : Served
  # body gone; regenerate
end

# A lease looks at the queue's leases run out, then hands out its oldest queued job, both in
# one write.
fn leasing(fs: Fs, books: Books, worker: String, queue: String, lease_ms: UInt64,
  at: Moment) : Served
  ensures result.outcome is Handed(job) implies handed_to?(books, job, worker)
  # body gone; regenerate
end

fn handed_to?(books: Books, job: Job, worker: String) : Bool
  # body gone; regenerate
end

fn acking(fs: Fs, books: Books, worker: String, id: String, at: Moment) : Served
  ensures result.outcome is Found(job) implies job.state == Done
  # body gone; regenerate
end

fn failing(fs: Fs, books: Books, worker: String, id: String, reason: String, at: Moment) : Served
  # body gone; regenerate
end

# An ack or a fail from a worker without a live lease: 409, once a lease run out is looked at.
fn refused(fs: Fs, books: Books, job: Job, at: Moment) : Served
  # body gone; regenerate
end

# The listener's Idle: every lease run out, in every queue, is looked at.
fn swept(fs: Fs, books: Books, at: Moment) : Served
  # body gone; regenerate
end

fn held(books: Books, id: String) : Option(Job)
  # body gone; regenerate
end

# Each job whose lease has run out beside the job it becomes; the rest are looked at and left.
fn expired_of(jobs: List(Job), now: Time) : List((Option(Job), Job))
  # body gone; regenerate
end

# A write's answer: the outcome when the log took it, 503 when it did not.
fn answered(done: Committed, outcome: Outcome) : Served
  # body gone; regenerate
end

fn unwritten(books: Books) : Outcome
  # body gone; regenerate
end

fn place() : Place
  # body gone; regenerate
end

fn call(worker: String, command: Command) : Call
  # body gone; regenerate
end

# The books of an empty folder with n jobs created in q, each allowed max attempts.
fn with_jobs(fs: Fs, n: UInt64, max: UInt64, at: Moment) : Books
  # body gone; regenerate
end

# The same moment, d later, on the same deadline.
fn shifted(at: Moment, d: Duration) : Moment
  # body gone; regenerate
end

fn lease_of(worker: String, ms: UInt64) : Call
  # body gone; regenerate
end

test "a create reads back and lists; a leased job is 409 to delete; an unknown id is 404"
  fs = Fs.fixture()
  at = Moment(now: Time.fixture(), by: Deadline.fixture(1.minute))
  made = serve(fs, with_jobs(fs, 0, 1, at),
    call("p", Create(queue: "q", payload: "hi", max_attempts: 2)), at)
  assert made.outcome is Made(job)
  assert id_of(job.number) == "j_1" and job.state == Queued
  assert serve(fs, made.books, call("p", Fetch(id: "j_1")), at).outcome == Found(job: job)
  assert serve(fs, made.books, call("p", Fetch(id: "j_2")), at).outcome == Missing
  listing = call("p", Listing(queue: Some("q"), status: Some(Queued)))
  assert serve(fs, made.books, listing, at).outcome == Listed(jobs: [job])
  held = serve(fs, made.books, lease_of("w", 1_000), at)
  assert serve(fs, held.books, call("p", Remove(id: "j_1")), at).outcome is Conflict(_)
  gone = serve(fs, held.books, call("p", Remove(id: "j_1")), shifted(at, 1.minute))
  assert gone.outcome == Removed
  assert serve(fs, gone.books, call("p", Fetch(id: "j_1")), at).outcome == Missing
  assert serve(fs, gone.books, call("p", Remove(id: "j_1")), at).outcome == Missing
end

test "a lease hands out the oldest queued job first, and nothing queued is 204"
  fs = Fs.fixture()
  at = Moment(now: Time.fixture(), by: Deadline.fixture(1.minute))
  first = serve(fs, with_jobs(fs, 2, 3, at), lease_of("a", 1_000), at)
  assert first.outcome is Handed(one)
  assert one.number == 1 and one.attempts == 1 and one.worker == Some("a")
  second = serve(fs, first.books, lease_of("b", 1_000), at)
  assert second.outcome is Handed(two)
  assert two.number == 2
  assert serve(fs, second.books, lease_of("c", 1_000), at).outcome == Empty
  assert serve(fs, second.books, call("c", Lease(queue: "other", lease_ms: 1_000)),
    at).outcome == Empty
end

test "the holder acks or fails its job; anyone else, or the holder once the lease ran out, is 409"
  fs = Fs.fixture()
  at = Moment(now: Time.fixture(), by: Deadline.fixture(1.minute))
  held = serve(fs, with_jobs(fs, 1, 3, at), lease_of("a", 1_000), at)
  assert serve(fs, held.books, call("b", Ack(id: "j_1")), at).outcome is Conflict(_)
  assert serve(fs, held.books, call("a", Ack(id: "j_1")),
    shifted(at, 1_000.ms)).outcome is Conflict(_)
  assert serve(fs, held.books, call("a", Ack(id: "j_1")), at).outcome is Found(done)
  assert done.state == Done
  failing = serve(fs, held.books, call("a", Fail(id: "j_1", reason: "no")), at)
  assert failing.outcome is Found(again)
  assert again.state == Queued and again.reason == Some("no")
  assert serve(fs, failing.books, call("a", Fail(id: "j_9", reason: "no")), at).outcome == Missing
end

test "a lease that runs out is leased again with attempts at 2, and one on its last attempt is dead"
  fs = Fs.fixture()
  at = Moment(now: Time.fixture(), by: Deadline.fixture(1.minute))
  first = serve(fs, with_jobs(fs, 1, 2, at), lease_of("a", 1_000), at)
  later = shifted(at, 1_000.ms)
  again = serve(fs, first.books, lease_of("b", 1_000), later)
  assert again.outcome is Handed(job)
  assert job.attempts == 2 and job.worker == Some("b")
  last = serve(fs, again.books, lease_of("c", 1_000), shifted(later, 1.minute))
  assert last.outcome == Empty
  assert serve(fs, last.books, call("c", Fetch(id: "j_1")), later).outcome is Found(dead)
  assert dead.state == Dead and dead.attempts == 2
end

test "a replay finds a lease that ran out while the service was stopped, at its next look"
  fs = Fs.fixture()
  at = Moment(now: Time.fixture(), by: Deadline.fixture(1.minute))
  leased_books = serve(fs, with_jobs(fs, 1, 3, at), lease_of("a", 30_000), at).books
  assert opened(fs, place(), Deadline.fixture(1.minute)) is Ok(replayed)
  assert find(replayed.board, 1) == find(leased_books.board, 1)
  looked = serve(fs, replayed, call("p", Fetch(id: "j_1")), shifted(at, 1.minute))
  assert looked.outcome is Found(job)
  assert job.state == Queued and job.attempts == 1
  assert opened(fs, place(), Deadline.fixture(1.minute)) is Ok(again)
  assert find(again.board, 1) == Some(job)
end

test "a change the log does not take is 503 with the jobs as they were, and the next rewrites it"
  fs = Fs.fixture()
  at = Moment(now: Time.fixture(), by: Deadline.fixture(1.minute))
  books = with_jobs(fs, 1, 3, at)
  slow = Moment(now: at.now, by: Deadline.fixture(10_000.ms))
  refused = serve(Fs.fixture(delay: 1.minute), books, lease_of("a", 1_000), slow)
  assert refused.outcome is Unavailable(_)
  assert refused.books.board == books.board and refused.books.torn
  mended = serve(fs, refused.books, lease_of("a", 1_000),
    Moment(now: at.now, by: Deadline.fixture(1.minute)))
  assert mended.outcome is Handed(_) and !mended.books.torn
  assert opened(fs, place(), Deadline.fixture(1.minute)) is Ok(replayed)
  assert find(replayed.board, 1) == find(mended.books.board, 1)
end

test "an id is never handed out twice, across a delete and a replay"
  fs = Fs.fixture()
  at = Moment(now: Time.fixture(), by: Deadline.fixture(1.minute))
  books = with_jobs(fs, 2, 1, at)
  assert serve(fs, books, call("p", Remove(id: "j_2")), at).outcome == Removed
  assert opened(fs, place(), Deadline.fixture(1.minute)) is Ok(replayed)
  made = serve(fs, replayed, call("p", Create(queue: "q", payload: "", max_attempts: 1)), at)
  assert made.outcome is Made(job)
  assert job.number > 2
end

property "a create then a read gives back any valid payload"
  for payload in any(String) if payload?(payload)
    fs = Fs.fixture()
    at = Moment(now: Time.fixture(), by: Deadline.fixture(1.minute))
    create = call("p", Create(queue: "q", payload: payload, max_attempts: 1))
    made = serve(fs, with_jobs(fs, 0, 1, at), create, at)
    assert made.outcome is Made(job)
    assert serve(fs, made.books, call("p", Fetch(id: id_of(job.number))), at).outcome is Found(read)
    assert read.payload == payload
  end
end
