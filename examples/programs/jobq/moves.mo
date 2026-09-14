module Jobq.Moves
expose Command, Call, Outcome, Served, serve, swept, unwritten

use Jobq.Board{find, placed, removed, oldest_queued, due_in, due_anywhere, listed}
use Jobq.Books{Step, Books, Place, Committed, committed, opened, unopened}
use Jobq.Job{Job, State, job, leased, acked, failed, ran_out, run_out?, holds?, payload?, id_of, number_of}
use Jobq.Store{StoreError, delete}

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

fn serve(fs: Fs, books: Books, call: Call, now: Time) : Served
  case call.command
    Create(queue: queue, payload: payload, max_attempts: max):
      creating(fs, books, job(books.next_id, queue, payload, max, now), now)
    Fetch(id): fetching(fs, books, id, now)
    Listing(queue: queue, status: status): listing(fs, books, queue, status, now)
    Remove(id): removing(fs, books, id, now)
    Lease(queue: queue, lease_ms: ms): leasing(fs, books, call.worker, queue, ms, now)
    Ack(id): acking(fs, books, call.worker, id, now)
    Fail(id: id, reason: reason): failing(fs, books, call.worker, id, reason, now)
  end
end

# An id is spent whether or not its job reaches the log, so no id is handed out twice; the log
# reserves ids a thousand at a time, so a replay never hands out one it handed out before.
fn creating(fs: Fs, books: Books, made: Job, now: Time) : Served
  ceiling = if books.next_id >= books.reserved
    books.next_id + 1_000
  else
    0
  end
  var spent = books
  spent.next_id = books.next_id + 1
  done = committed(fs, spent, [(None, made)], ceiling, now)
  answered(done, Made(job: made))
end

fn fetching(fs: Fs, books: Books, id: String, now: Time) : Served
  case held(books, id)
    Some(kept):
      done = committed(fs, books, expired_of([kept], now), 0, now)
      answered(done, Found(job: find(done.books.board, kept.number) or kept))
    None: Served(books: books, outcome: Missing, steps: [])
  end
end

# A listing looks at the leases run out in its queue, or in every queue, before it lists.
fn listing(fs: Fs, books: Books, queue: Option(String), status: Option(State), now: Time) : Served
  due = case queue
    Some(name): due_in(books.board, name, now)
    None: due_anywhere(books.board, now)
  end
  done = committed(fs, books, expired_of(due, now), 0, now)
  answered(done, Listed(jobs: listed(done.books.board, queue, status, 100)))
end

fn removing(fs: Fs, books: Books, id: String, now: Time) : Served
  case held(books, id)
    Some(kept):
      looked = committed(fs, books, expired_of([kept], now), 0, now)
      current = find(looked.books.board, kept.number) or kept
      if !looked.ok or current.status == Leased
        return answered(looked, Conflict(reason: "the job is leased"))
      end
      deleted(fs, looked, current, now)
    None: Served(books: books, outcome: Missing, steps: [])
  end
end

fn deleted(fs: Fs, looked: Committed, job: Job, now: Time) : Served
  books = looked.books
  case delete(fs, books.table, id_of(job.number))
    Ok(table):
      var after = books
      after.table = table
      after.board = removed(books.board, job.number)
      step = Step(before: Some(job), after: None, now: now, logged: true, kept: true)
      Served(books: after, outcome: Removed, steps: looked.steps.push(step))
    Error(problem):
      step = Step(before: Some(job), after: None, now: now, logged: false, kept: false)
      var torn = books
      torn.torn = books.torn or problem == Torn
      Served(books: torn, outcome: unwritten(torn), steps: looked.steps.push(step))
  end
end

# A lease looks at the queue's leases run out, then hands out its oldest queued job, both in
# one write.
fn leasing(fs: Fs, books: Books, worker: String, queue: String, lease_ms: UInt64,
  now: Time) : Served
  ensures result.outcome is Handed(job) implies handed_to?(books, job, worker)

  expired = expired_of(due_in(books.board, queue, now), now)
  looked = expired.reduce(books.board, fn(b, change) placed(b, change.1) end)
  case oldest_queued(looked, queue)
    Some(next):
      handed = leased(next, worker, lease_ms, now)
      changes = expired.push((find(books.board, next.number), handed))
      answered(committed(fs, books, changes, 0, now), Handed(job: handed))
    None: answered(committed(fs, books, expired, 0, now), Empty)
  end
end

fn handed_to?(books: Books, job: Job, worker: String) : Bool
  case find(books.board, job.number)
    Some(before):
      job.status == Leased and job.worker == Some(worker) and job.attempts == before.attempts + 1
    None: false
  end
end

fn acking(fs: Fs, books: Books, worker: String, id: String, now: Time) : Served
  ensures result.outcome is Found(job) implies job.status == Done

  case held(books, id)
    Some(kept):
      if holds?(kept, worker, now)
        return answered(committed(fs, books, [(Some(kept), acked(kept, now))], 0, now),
          Found(job: acked(kept, now)))
      end
      refused(fs, books, kept, now)
    None: Served(books: books, outcome: Missing, steps: [])
  end
end

fn failing(fs: Fs, books: Books, worker: String, id: String, reason: String, now: Time) : Served
  case held(books, id)
    Some(kept):
      if holds?(kept, worker, now)
        after = failed(kept, reason, now)
        return answered(committed(fs, books, [(Some(kept), after)], 0, now), Found(job: after))
      end
      refused(fs, books, kept, now)
    None: Served(books: books, outcome: Missing, steps: [])
  end
end

# An ack or a fail from a worker without a live lease: 409, once a lease run out is looked at.
fn refused(fs: Fs, books: Books, job: Job, now: Time) : Served
  done = committed(fs, books, expired_of([job], now), 0, now)
  answered(done, Conflict(reason: "the caller does not hold a live lease on the job"))
end

# The listener's Idle: every lease run out, in every queue, is looked at.
fn swept(fs: Fs, books: Books, now: Time) : Served
  answered(committed(fs, books, expired_of(due_anywhere(books.board, now), now), 0, now), Empty)
end

fn held(books: Books, id: String) : Option(Job)
  find(books.board, try number_of(id))
end

# Each job whose lease has run out beside the job it becomes; the rest are looked at and left.
fn expired_of(jobs: List(Job), now: Time) : List((Option(Job), Job))
  due = jobs.filter(fn(job) run_out?(job, now) end)
  due.map(fn(job) (Some(job), ran_out(job, now)) end)
end

# A write's answer: the outcome when the log took it, 503 when it did not.
fn answered(done: Committed, outcome: Outcome) : Served
  if done.ok
    return Served(books: done.books, outcome: outcome, steps: done.steps)
  end
  Served(books: done.books, outcome: unwritten(done.books), steps: done.steps)
end

fn unwritten(books: Books) : Outcome
  if books.torn
    return Unavailable(reason: "the log may end in part of a change; it is rewritten at the next change")
  end
  Unavailable(reason: "the log did not take the change")
end

fn place() : Place
  Place(dir: "d", log: "jobq.log")
end

fn call(worker: String, command: Command) : Call
  Call(worker: worker, command: command)
end

# The books of an empty folder with n jobs created in q, each allowed max attempts.
fn with_jobs(fs: Fs, n: UInt64, max: UInt64, at: Time) : Books
  var books = case opened(fs, place())
    Ok(fresh): fresh
    Error(_): unopened(place())
  end
  for i in 0..n
    books = serve(fs, books, call("p", Create(queue: "q", payload: "job #{i}", max_attempts: max)),
      at).books
  end
  books
end

fn lease_of(worker: String, ms: UInt64) : Call
  call(worker, Lease(queue: "q", lease_ms: ms))
end

test "a create reads back and lists; a leased job is 409 to delete; an unknown id is 404"
  fs = Fs.fixture()
  at = Time.fixture()
  made = serve(fs, with_jobs(fs, 0, 1, at),
    call("p", Create(queue: "q", payload: "hi", max_attempts: 2)), at)
  assert made.outcome is Made(job)
  assert id_of(job.number) == "j_1" and job.status == Queued
  assert serve(fs, made.books, call("p", Fetch(id: "j_1")), at).outcome == Found(job: job)
  assert serve(fs, made.books, call("p", Fetch(id: "j_2")), at).outcome == Missing
  listing = call("p", Listing(queue: Some("q"), status: Some(Queued)))
  assert serve(fs, made.books, listing, at).outcome == Listed(jobs: [job])
  held = serve(fs, made.books, lease_of("w", 1_000), at)
  assert serve(fs, held.books, call("p", Remove(id: "j_1")), at).outcome is Conflict(_)
  gone = serve(fs, held.books, call("p", Remove(id: "j_1")), at + 1.minute)
  assert gone.outcome == Removed
  assert serve(fs, gone.books, call("p", Fetch(id: "j_1")), at).outcome == Missing
  assert serve(fs, gone.books, call("p", Remove(id: "j_1")), at).outcome == Missing
end

test "a lease hands out the oldest queued job first, and nothing queued is 204"
  fs = Fs.fixture()
  at = Time.fixture()
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
  at = Time.fixture()
  held = serve(fs, with_jobs(fs, 1, 3, at), lease_of("a", 1_000), at)
  assert serve(fs, held.books, call("b", Ack(id: "j_1")), at).outcome is Conflict(_)
  assert serve(fs, held.books, call("a", Ack(id: "j_1")), at + 1_000.ms).outcome is Conflict(_)
  assert serve(fs, held.books, call("a", Ack(id: "j_1")), at).outcome is Found(done)
  assert done.status == Done
  failing = serve(fs, held.books, call("a", Fail(id: "j_1", reason: "no")), at)
  assert failing.outcome is Found(again)
  assert again.status == Queued and again.reason == Some("no")
  assert serve(fs, failing.books, call("a", Fail(id: "j_9", reason: "no")), at).outcome == Missing
end

test "a lease that runs out is leased again with attempts at 2, and one on its last attempt is dead"
  fs = Fs.fixture()
  at = Time.fixture()
  first = serve(fs, with_jobs(fs, 1, 2, at), lease_of("a", 1_000), at)
  later = at + 1_000.ms
  again = serve(fs, first.books, lease_of("b", 1_000), later)
  assert again.outcome is Handed(job)
  assert job.attempts == 2 and job.worker == Some("b")
  last = serve(fs, again.books, lease_of("c", 1_000), later + 1.minute)
  assert last.outcome == Empty
  assert serve(fs, last.books, call("c", Fetch(id: "j_1")), later).outcome is Found(dead)
  assert dead.status == Dead and dead.attempts == 2
end

test "a replay finds a lease that ran out while the service was stopped, at its next look"
  fs = Fs.fixture()
  at = Time.fixture()
  leased_books = serve(fs, with_jobs(fs, 1, 3, at), lease_of("a", 30_000), at).books
  assert opened(fs, place()) is Ok(replayed)
  assert find(replayed.board, 1) == find(leased_books.board, 1)
  looked = serve(fs, replayed, call("p", Fetch(id: "j_1")), at + 1.minute)
  assert looked.outcome is Found(job)
  assert job.status == Queued and job.attempts == 1
  assert opened(fs, place()) is Ok(again)
  assert find(again.board, 1) == Some(job)
end

test "a change the log does not take is 503 with the jobs as they were, and the next rewrites it"
  fs = Fs.fixture()
  at = Time.fixture()
  books = with_jobs(fs, 1, 3, at)
  refused = serve(Fs.fixture(delay: 1.minute), books, lease_of("a", 1_000), at)
  assert refused.outcome is Unavailable(_)
  assert refused.books.board == books.board and refused.books.torn
  mended = serve(fs, refused.books, lease_of("a", 1_000), at)
  assert mended.outcome is Handed(_) and !mended.books.torn
  assert opened(fs, place()) is Ok(replayed)
  assert find(replayed.board, 1) == find(mended.books.board, 1)
end

test "an id is never handed out twice, across a delete and a replay"
  fs = Fs.fixture()
  at = Time.fixture()
  books = with_jobs(fs, 2, 1, at)
  assert serve(fs, books, call("p", Remove(id: "j_2")), at).outcome == Removed
  assert opened(fs, place()) is Ok(replayed)
  made = serve(fs, replayed, call("p", Create(queue: "q", payload: "", max_attempts: 1)), at)
  assert made.outcome is Made(job)
  assert job.number > 2
end

property "a create then a read gives back any valid payload"
  for payload in any(String) if payload?(payload)
    fs = Fs.fixture()
    at = Time.fixture()
    create = call("p", Create(queue: "q", payload: payload, max_attempts: 1))
    made = serve(fs, with_jobs(fs, 0, 1, at), create, at)
    assert made.outcome is Made(job)
    assert serve(fs, made.books, call("p", Fetch(id: id_of(job.number))), at).outcome is Found(read)
    assert read.payload == payload
  end
end

verified: types, contracts, tests (8), property (200 seeds), sim (not run)
          proven: not run
