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
  case call.command
    Create(queue: queue, payload: payload, max_attempts: max):
      creating(fs, books, job(books.next_id, queue, payload, max, at.now), at)
    Fetch(id): fetching(fs, books, id, at)
    Listing(queue: queue, status: status): listing(fs, books, queue, status, at)
    Remove(id): removing(fs, books, id, at)
    Lease(queue: queue, lease_ms: lease_ms): leasing(fs, books, call.worker, queue, lease_ms, at)
    Ack(id): acking(fs, books, call.worker, id, at)
    Fail(id: id, reason: reason): failing(fs, books, call.worker, id, reason, at)
  end
end

# An id is spent whether or not its job reaches the log, so no id is handed out twice; the log
# reserves ids a thousand at a time, so a replay never hands out one it handed out before.
fn creating(fs: Fs, books: Books, made: Job, at: Moment) : Served
  var spent = books
  spent.next_id = books.next_id + 1
  ceiling = if spent.next_id > books.reserved: spent.next_id + 1_000 else: 0
  answered(committed(fs, spent, [(None, made)], ceiling, at), Made(job: made))
end

fn fetching(fs: Fs, books: Books, id: String, at: Moment) : Served
  case held(books, id)
    Some(kept):
      done = committed(fs, books, expired_of([kept], at.now), 0, at)
      answered(done, Found(job: find(done.books.board, kept.number) or kept))
    None: Served(books: books, outcome: Missing, steps: [])
  end
end

# A listing looks at the leases run out in its queue, or in every queue, before it lists.
fn listing(fs: Fs, books: Books, queue: Option(String), status: Option(State), at: Moment) : Served
  stale = case queue
    Some(name): due_in(books.board, name, at.now)
    None: due_anywhere(books.board, at.now)
  end
  done = committed(fs, books, expired_of(stale, at.now), 0, at)
  answered(done, Listed(jobs: listed(done.books.board, queue, status, 100)))
end

fn removing(fs: Fs, books: Books, id: String, at: Moment) : Served
  case held(books, id)
    Some(kept):
      looked = committed(fs, books, expired_of([kept], at.now), 0, at)
      return answered(looked, unwritten(looked.books)) if !looked.ok
      now_held = find(looked.books.board, kept.number) or kept
      if now_held.state == Leased
        return Served(books: looked.books, outcome: Conflict(reason: "the job is leased"),
          steps: looked.steps)
      end
      deleted(fs, looked, now_held, at)
    None: Served(books: books, outcome: Missing, steps: [])
  end
end

fn deleted(fs: Fs, looked: Committed, job: Job, at: Moment) : Served
  case deleted_from(fs, looked.books.table, id_of(job.number), at.by)
    Ok(table):
      var after = looked.books
      after.table = table
      after.board = removed(looked.books.board, job.number)
      step = Step(before: Some(job), after: None, now: at.now, logged: true, kept: true)
      Served(books: after, outcome: Removed, steps: looked.steps.push(step))
    Error(problem):
      var back = looked.books
      back.torn = looked.books.torn or problem == Torn
      step = Step(before: Some(job), after: Some(job), now: at.now, logged: false, kept: false)
      Served(books: back, outcome: unwritten(back), steps: looked.steps.push(step))
  end
end

# A lease looks at the queue's leases run out, then hands out its oldest queued job, both in
# one write.
fn leasing(fs: Fs, books: Books, worker: String, queue: String, lease_ms: UInt64,
  at: Moment) : Served
  ensures result.outcome is Handed(job) implies handed_to?(books, job, worker)
  stale = expired_of(due_in(books.board, queue, at.now), at.now)
  freed = stale.reduce(books.board, fn(board, change) placed(board, change.1) end)
  case oldest_queued(freed, queue)
    Some(next):
      held = leased(next, worker, lease_ms, at.now)
      done = committed(fs, books, stale.push((Some(next), held)), 0, at)
      answered(done, Handed(job: held))
    None: answered(committed(fs, books, stale, 0, at), Empty)
  end
end

fn handed_to?(books: Books, job: Job, worker: String) : Bool
  known = find(books.board, job.number) is Some(_)
  known and job.state == Leased and job.worker == Some(worker)
end

fn acking(fs: Fs, books: Books, worker: String, id: String, at: Moment) : Served
  ensures result.outcome is Found(job) implies job.state == Done
  case held(books, id)
    Some(kept):
      return refused(fs, books, kept, at) if !holds?(kept, worker, at.now)
      done_job = acked(kept, at.now)
      answered(committed(fs, books, [(Some(kept), done_job)], 0, at), Found(job: done_job))
    None: Served(books: books, outcome: Missing, steps: [])
  end
end

fn failing(fs: Fs, books: Books, worker: String, id: String, reason: String, at: Moment) : Served
  case held(books, id)
    Some(kept):
      return refused(fs, books, kept, at) if !holds?(kept, worker, at.now)
      again = failed(kept, reason, at.now)
      answered(committed(fs, books, [(Some(kept), again)], 0, at), Found(job: again))
    None: Served(books: books, outcome: Missing, steps: [])
  end
end

# An ack or a fail from a worker without a live lease: 409, once a lease run out is looked at.
fn refused(fs: Fs, books: Books, job: Job, at: Moment) : Served
  done = committed(fs, books, expired_of([job], at.now), 0, at)
  answered(done, Conflict(reason: "the caller does not hold a live lease on the job"))
end

# The listener's Idle: every lease run out, in every queue, is looked at.
fn swept(fs: Fs, books: Books, at: Moment) : Served
  ended = expired_of(due_anywhere(books.board, at.now), at.now)
  answered(committed(fs, books, ended, 0, at), Listed(jobs: ended.map(fn(change) change.1 end)))
end

fn held(books: Books, id: String) : Option(Job)
  find(books.board, try number_of(id))
end

# Each job whose lease has run out beside the job it becomes; the rest are looked at and left.
fn expired_of(jobs: List(Job), now: Time) : List((Option(Job), Job))
  ran = jobs.filter(fn(job) job.state == Leased and run_out?(job, now) end)
  ran.map(fn(job) (Some(job), ran_out(job, now)) end)
end

# A write's answer: the outcome when the log took it, 503 when it did not.
fn answered(done: Committed, outcome: Outcome) : Served
  return Served(books: done.books, outcome: outcome, steps: done.steps) if done.ok
  Served(books: done.books, outcome: unwritten(done.books), steps: done.steps)
end

fn unwritten(books: Books) : Outcome
  return Unavailable(reason: "the log may end in part of the change") if books.torn
  Unavailable(reason: "the log did not take the change")
end

fn place() : Place
  Place(dir: "d", log: "jobq.log")
end

fn call(worker: String, command: Command) : Call
  Call(worker: worker, command: command)
end

# The books of an empty folder with n jobs created in q, each allowed max attempts.
fn with_jobs(fs: Fs, n: UInt64, max: UInt64, at: Moment) : Books
  var books = unopened(place())
  for i in 0..n
    books = serve(fs, books, call("p", Create(queue: "q", payload: "#{i}", max_attempts: max)),
      at).books
  end
  books
end

# The same moment, d later, on the same deadline.
fn shifted(at: Moment, d: Duration) : Moment
  Moment(now: at.now + d, by: at.by)
end

fn lease_of(worker: String, ms: UInt64) : Call
  Call(worker: worker, command: Lease(queue: "q", lease_ms: ms))
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

verified: types, contracts, tests (8), property (200 seeds), sim (not run)
          proven: not run
