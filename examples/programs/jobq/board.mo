module Jobq.Board
expose Command, Call, Outcome, Counts, Served, Hold, Look, served, swept, counts_of

use Jobq.Books{Books, Stored, stored, deleted, reserving, books_of, survivors}
use Jobq.Job{State, Job, created, leased, acked, failed, expired, run_out?, held_by?, id_of, id_number, payload?}
use Jobq.Store{Table, open}

intent "The board every queue's jobs are on, and each move a call makes on it: a create, lease, ack, fail, delete, or lease run out is in the store before the board takes it or it is answered, a store that did not take it is 503 with the board as it was, and a lease that ran out is put back at the next look."

never "a job is held by two workers at once"
  for a in Hold.all, b in Hold.all if a.id == b.id and a.worker != b.worker
    a.from < b.until and b.from < a.until
  end
end

never "a response is sent before its record is durable"
  for s in Served.all
    s.changed and !s.durable
  end
end

never "a lease that ran out is still held after a look"
  for l in Look.all
    run_out?(l.job, l.now)
  end
end

enum Command
  Create(queue: String, payload: String, max_attempts: UInt64)
  Fetch(id: String)
  Listing(queue: Option(String), wanted: Option(State))
  Remove(id: String)
  Lease(queue: String, lease_ms: UInt64)
  Ack(id: String)
  Fail(id: String, reason: String)
end

# A call on the board: the worker's token, the time main's clock gave when the request came, and
# what it asks.
struct Call
  worker: String
  at: Time
  command: Command
end

enum Outcome
  Made(job: Job)
  Found(job: Job)
  Listed(jobs: List(Job))
  Removed
  Empty
  Missing
  Conflict(reason: String)
  Unavailable(reason: String)
end

struct Counts
  queued: UInt64
  leased: UInt64
  done: UInt64
  dead: UInt64
  uptime_ms: Int64
end

# A call's result: the board after it, the answer, whether the board changed, whether every change
# was in the store first, and the lease it handed out.
struct Served
  books: Books
  outcome: Outcome
  changed: Bool
  durable: Bool
  hold: Option(Hold)
end

# A lease the board took: the job, the worker, and the time it runs from and until.
struct Hold
  id: String
  worker: String
  from: Time
  until: Time
end

# A job as a look at it left it, and when the look was.
struct Look
  job: Job
  now: Time
end

enum Looked
  Seen(books: Books, look: Look, moved: Bool)
  Unseen(served: Served)
end

fn served(fs: Fs, books: Books, call: Call) : Served
  var ready = books
  ready.clock = max_of(books.clock, call.at)
  case call.command
    Create(queue: queue, payload: payload, max_attempts: most):
      creating(fs, ready, queue, payload, most)
    Fetch(id): fetching(fs, ready, id)
    Listing(queue: queue, wanted: wanted): listing(fs, ready, queue, wanted)
    Remove(id): removing(fs, ready, id)
    Lease(queue: queue, lease_ms: ms): leasing(fs, ready, call.worker, queue, ms)
    Ack(id): acking(fs, ready, call.worker, id)
    Fail(id: id, reason: reason): failing(fs, ready, call.worker, id, reason)
  end
end

fn answer(books: Books, outcome: Outcome, changed: Bool) : Served
  Served(books: books, outcome: outcome, changed: changed, durable: true, hold: None)
end

fn unavailable(books: Books, reason: String) : Served
  Served(books: books, outcome: Unavailable(reason: reason), changed: false, durable: false,
    hold: None)
end

# A create's id is spent whether or not its record reaches the store, so no id is handed out
# twice.
fn creating(fs: Fs, books: Books, queue: String, payload: String, most: UInt64) : Served
  if books.jobs.size >= 1_000_000
    return answer(books, Unavailable(reason: "the board holds a million jobs"), false)
  end
  case reserving(fs, books)
    Took(ready):
      job = created(ready.next_id, queue, payload, most, ready.clock)
      var spent = ready
      spent.next_id = ready.next_id + 1
      case stored(fs, spent, job)
        Took(after): answer(after, Made(job: job), true)
        Lost(books: lost, reason: why): unavailable(lost, why)
      end
    Lost(books: lost, reason: why): unavailable(lost, why)
  end
end

fn fetching(fs: Fs, books: Books, id: String) : Served
  case looked(fs, books, id)
    Seen(books: after, look: look, moved: moved): answer(after, Found(job: look.job), moved)
    Unseen(served): served
  end
end

# The jobs of a queue, or every queue, in a state, or any, by id, at most 100; each run-out lease
# among them is put back first, since a read is a look.
fn listing(fs: Fs, books: Books, queue: Option(String), wanted: Option(State)) : Served
  now = books.clock
  due = books.jobs.values.filter(fn(j) in_queue?(j, queue) and run_out?(j, now) end)
  var board = books
  var moved = false
  for job in due
    case looked(fs, board, job.id)
      Seen(books: after, look: _, moved: _):
        board = after
        moved = true
      Unseen(served):
        return served
    end
  end
  kept = board.jobs.values.filter(fn(j) in_queue?(j, queue) and in_state?(j, wanted) end)
  jobs = kept.sort_by(fn(j) id_number(j.id) or 0 end).take(100)
  answer(board, Listed(jobs: jobs), moved)
end

fn in_queue?(job: Job, queue: Option(String)) : Bool
  (queue or job.queue) == job.queue
end

fn in_state?(job: Job, wanted: Option(State)) : Bool
  (wanted or job.state) == job.state
end

fn removing(fs: Fs, books: Books, id: String) : Served
  case looked(fs, books, id)
    Seen(books: after, look: look, moved: moved):
      if look.job.state == Leased
        return answer(after, Conflict(reason: "#{id} is leased"), moved)
      end
      case deleted(fs, after, look.job)
        Took(gone): answer(gone, Removed, true)
        Lost(books: lost, reason: why): unavailable(lost, why)
      end
    Unseen(served): served
  end
end

# The oldest queued job of the queue, leased to the worker; a run-out lease on an older job is put
# back on the way, and a job it makes dead is passed over.
fn leasing(fs: Fs, books: Books, worker: String, queue: String, lease_ms: UInt64) : Served
  var board = books
  var moved = false
  for n in (books.open.get(queue) or Set.new()).to_list
    case looked(fs, board, id_of(n))
      Seen(books: after, look: look, moved: stepped):
        board = after
        moved = moved or stepped
        if look.job.state == Queued
          return lease_taken(fs, board, leased(look.job, worker, lease_ms, board.clock))
        end
      Unseen(served):
        return served
    end
  end
  answer(board, Empty, moved)
end

fn lease_taken(fs: Fs, books: Books, held: Job) : Served
  case stored(fs, books, held)
    Took(after):
      hold = Hold(id: held.id, worker: held.worker or "", from: held.updated_at,
        until: held.lease_until or held.updated_at)
      Served(books: after, outcome: Found(job: held), changed: true, durable: true,
        hold: Some(hold))
    Lost(books: lost, reason: why): unavailable(lost, why)
  end
end

fn acking(fs: Fs, books: Books, worker: String, id: String) : Served
  case looked(fs, books, id)
    Seen(books: after, look: look, moved: moved):
      if !held_by?(look.job, worker, after.clock)
        return answer(after, Conflict(reason: "#{worker} holds no live lease on #{id}"), moved)
      end
      done = acked(look.job, after.clock)
      changed(fs, after, done)
    Unseen(served): served
  end
end

fn failing(fs: Fs, books: Books, worker: String, id: String, reason: String) : Served
  case looked(fs, books, id)
    Seen(books: after, look: look, moved: moved):
      if !held_by?(look.job, worker, after.clock)
        return answer(after, Conflict(reason: "#{worker} holds no live lease on #{id}"), moved)
      end
      changed(fs, after, failed(look.job, reason, after.clock))
    Unseen(served): served
  end
end

fn changed(fs: Fs, books: Books, job: Job) : Served
  case stored(fs, books, job)
    Took(after): answer(after, Found(job: job), true)
    Lost(books: lost, reason: why): unavailable(lost, why)
  end
end

# A look at a job: a lease that ran out is put back, in the store first.
fn looked(fs: Fs, books: Books, id: String) : Looked
  case books.jobs.get(id)
    Some(job):
      now = books.clock
      return Seen(books: books, look: Look(job: job, now: now), moved: false) if !run_out?(job, now)
      back = expired(job, now)
      case stored(fs, books, back)
        Took(after): Seen(books: after, look: Look(job: back, now: now), moved: true)
        Lost(books: lost, reason: why): Unseen(served: unavailable(lost, why))
      end
    None: Unseen(served: answer(books, Missing, false))
  end
end

# Every run-out lease on the board put back, as the listener's Idle asks; a store that does not
# take one leaves it for the next look.
fn swept(fs: Fs, books: Books, at: Time) : Books
  now = max_of(books.clock, at)
  due = books.jobs.values.filter(fn(j) run_out?(j, now) end)
  var board = books
  board.clock = now
  for job in due
    board = case looked(fs, board, job.id)
      Seen(books: after, look: _, moved: _): after
      Unseen(served): served.books
    end
  end
  board
end

fn counts_of(books: Books, since: Time, at: Time) : Counts
  jobs = books.jobs.values
  Counts(queued: jobs.count(fn(j) j.state == Queued end),
    leased: jobs.count(fn(j) j.state == Leased end), done: jobs.count(fn(j) j.state == Done end),
    dead: jobs.count(fn(j) j.state == Dead end), uptime_ms: (max_of(books.clock, at) - since).ms)
end

fn at(seconds: UInt64) : Time
  Time.from_parts(2026, 9, 14, 9, 0, 0) + (seconds * 1_000).to_i64.ms
end

fn call(worker: String, seconds: UInt64, command: Command) : Call
  Call(worker: worker, at: at(seconds), command: command)
end

fn fresh() : Table
  Table(buckets: Map.new(), size: 0, dir: "d", name: "jobq.log", bytes: 0, lines: 0, cut: false)
end

fn create(queue: String, most: UInt64) : Command
  Create(queue: queue, payload: "work", max_attempts: most)
end

test "a created job reads back, and so does the board replayed from its store"
  fs = Fs.fixture()
  made = served(fs, books_of(fresh(), at(0)), call("ada", 0, create("emails", 3)))
  assert made.outcome is Made(job)
  assert job.id == "j_1" and job.state == Queued and made.changed and made.durable
  assert served(fs, made.books, call("bob", 1, Fetch(id: "j_1"))).outcome == Found(job: job)
  assert served(fs, made.books, call("bob", 1, Fetch(id: "j_2"))).outcome == Missing
  assert open(fs, "d") is Ok(table)
  replayed = books_of(table, at(2))
  assert survivors(made.books, replayed).all?(fn(s) s.before == s.after end)
  assert replayed.next_id == 101
end

test "a lease hands out the oldest queued job of its queue, and nothing when none is queued"
  fs = Fs.fixture()
  var books = books_of(fresh(), at(0))
  for queue in ["emails", "other", "emails"]
    books = served(fs, books, call("ada", 0, create(queue, 3))).books
  end
  first = served(fs, books, call("ada", 1, Lease(queue: "emails", lease_ms: 30_000)))
  assert first.outcome is Found(held)
  assert held.id == "j_1" and held.worker == Some("ada") and held.attempts == 1
  second = served(fs, first.books, call("bob", 1, Lease(queue: "emails", lease_ms: 30_000)))
  assert second.outcome is Found(next)
  assert next.id == "j_3"
  assert served(fs, second.books,
    call("carl", 1, Lease(queue: "emails", lease_ms: 100))).outcome == Empty
  assert served(fs, second.books,
    call("carl", 1, Lease(queue: "none", lease_ms: 100))).outcome == Empty
end

test "a lease that runs out is leased again with attempts at 2, and on its last attempt the job is dead"
  fs = Fs.fixture()
  made = served(fs, books_of(fresh(), at(0)), call("ada", 0, create("emails", 2)))
  first = served(fs, made.books, call("ada", 1, Lease(queue: "emails", lease_ms: 1_000)))
  second = served(fs, first.books, call("bob", 2, Lease(queue: "emails", lease_ms: 1_000)))
  assert second.outcome is Found(again)
  assert again.worker == Some("bob") and again.attempts == 2
  third = served(fs, second.books, call("carl", 3, Lease(queue: "emails", lease_ms: 1_000)))
  assert third.outcome == Empty
  assert served(fs, third.books, call("carl", 3, Fetch(id: "j_1"))).outcome is Found(dead)
  assert dead.state == Dead and dead.attempts == 2
end

test "an ack or a fail needs a live lease the caller holds, and otherwise is 409"
  fs = Fs.fixture()
  made = served(fs, books_of(fresh(), at(0)), call("ada", 0, create("emails", 3)))
  held = served(fs, made.books, call("ada", 0, Lease(queue: "emails", lease_ms: 1_000))).books
  assert served(fs, held, call("bob", 0, Ack(id: "j_1"))).outcome is Conflict(_)
  assert served(fs, held, call("bob", 0, Fail(id: "j_1", reason: "no"))).outcome is Conflict(_)
  late = served(fs, held, call("ada", 5, Ack(id: "j_1")))
  assert late.outcome is Conflict(_) and late.changed
  assert served(fs, late.books, call("ada", 5, Fetch(id: "j_1"))).outcome is Found(back)
  assert back.state == Queued and back.attempts == 1
  again = served(fs, late.books, call("ada", 5, Lease(queue: "emails", lease_ms: 1_000))).books
  done = served(fs, again, call("ada", 5, Ack(id: "j_1")))
  assert done.outcome is Found(acked_job)
  assert acked_job.state == Done and acked_job.attempts == 2
  assert served(fs, done.books, call("ada", 5, Ack(id: "j_1"))).outcome is Conflict(_)
  assert served(fs, done.books, call("ada", 5, Ack(id: "j_7"))).outcome == Missing
end

test "a fail puts the job back with its reason, and a delete is 204 unless the job is leased"
  fs = Fs.fixture()
  var books = books_of(fresh(), at(0))
  books = served(fs, books, call("ada", 0, create("emails", 3))).books
  books = served(fs, books, call("ada", 0, create("emails", 3))).books
  books = served(fs, books, call("ada", 0, Lease(queue: "emails", lease_ms: 1_000))).books
  back = served(fs, books, call("ada", 0, Fail(id: "j_1", reason: "smtp down")))
  assert back.outcome is Found(queued)
  assert queued.state == Queued and queued.reason == Some("smtp down")
  gone = served(fs, back.books, call("bob", 0, Remove(id: "j_1")))
  assert gone.outcome == Removed
  assert served(fs, gone.books, call("bob", 0, Fetch(id: "j_1"))).outcome == Missing
  assert served(fs, gone.books, call("bob", 0, Remove(id: "j_1"))).outcome == Missing
  leased_now = served(fs, gone.books, call("ada", 0, Lease(queue: "emails", lease_ms: 1_000)))
  assert served(fs, leased_now.books, call("bob", 0, Remove(id: "j_2"))).outcome is Conflict(_)
  assert open(fs, "d") is Ok(table)
  assert books_of(table, at(1)).jobs.keys == ["j_2"]
end

test "a listing filters by queue and state, by id, at most 100, and puts back a run-out lease first"
  fs = Fs.fixture()
  var books = books_of(fresh(), at(0))
  for i in 0..104
    books = served(fs, books, call("ada", 0, create(if i < 2: "other" else: "emails", 3))).books
  end
  books = served(fs, books, call("ada", 0, Lease(queue: "other", lease_ms: 1_000))).books
  listed = served(fs, books, call("ada", 0, Listing(queue: None, wanted: None)))
  assert listed.outcome is Listed(every)
  assert every.size == 100 and every.map(fn(j) j.id end).take(3) == ["j_1", "j_2", "j_3"]
  leased_now = served(fs, books,
    call("ada", 0, Listing(queue: Some("other"), wanted: Some(Leased))))
  assert leased_now.outcome is Listed(holding)
  assert holding.map(fn(j) j.id end) == ["j_1"]
  later = served(fs, books, call("bob", 5, Listing(queue: Some("other"), wanted: Some(Queued))))
  assert later.outcome is Listed(others)
  assert others.map(fn(j) j.id end) == ["j_1", "j_2"] and later.changed
end

test "a store that does not take a change is 503 with the board as it was, and the next change is taken once it does"
  fs = Fs.fixture()
  made = served(fs, books_of(fresh(), at(0)), call("ada", 0, create("emails", 3)))
  slow = Fs.fixture(delay: 1.minute)
  refused = served(slow, made.books, call("ada", 1, create("emails", 3)))
  assert refused.outcome is Unavailable(_) and !refused.durable
  assert refused.books.jobs == made.books.jobs and refused.books.torn
  held = served(slow, made.books, call("ada", 1, Lease(queue: "emails", lease_ms: 1_000)))
  assert held.outcome is Unavailable(_) and held.books.jobs == made.books.jobs
  again = served(fs, refused.books, call("ada", 2, create("emails", 3)))
  assert again.outcome is Made(job)
  assert job.id == "j_3" and !again.books.torn
  assert open(fs, "d") is Ok(table)
  assert books_of(table, at(3)).jobs.keys == ["j_1", "j_3"]
end

test "a sweep puts back every run-out lease, and the counts say where every job is"
  fs = Fs.fixture()
  var books = books_of(fresh(), at(0))
  for queue in ["a", "b", "c"]
    books = served(fs, books, call("ada", 0, create(queue, 1))).books
    books = served(fs, books, call("ada", 0, Lease(queue: queue, lease_ms: 1_000))).books
  end
  assert counts_of(books, at(0), at(0)) == Counts(queued: 0, leased: 3, done: 0, dead: 0,
    uptime_ms: 0)
  after = swept(fs, books, at(2))
  assert counts_of(after, at(0), at(2)) == Counts(queued: 0, leased: 0, done: 0, dead: 3,
    uptime_ms: 2_000)
end

test rejects "two workers holding one job at once trips the never"
  first = Hold(id: "j_1", worker: "ada", from: at(0), until: at(30))
  second = Hold(id: "j_1", worker: "bob", from: at(10), until: at(40))
  assert first.until > second.from
end

test rejects "a change answered before its record is durable trips the never"
  early = Served(books: books_of(fresh(), at(0)), outcome: Removed, changed: true, durable: false,
    hold: None)
  assert early.changed
end

test rejects "a run-out lease still held after a look trips the never"
  job = leased(created(1, "emails", "", 3, at(0)), "ada", 1_000, at(0))
  look = Look(job: job, now: at(5))
  assert look.now == at(5)
end

property "a create then a fetch gives back any valid payload"
  for payload in any(String) if payload?(payload)
    fs = Fs.fixture()
    command = Create(queue: "q", payload: payload, max_attempts: 3)
    made = served(fs, books_of(fresh(), at(0)), call("ada", 0, command))
    assert served(fs, made.books, call("ada", 0, Fetch(id: "j_1"))).outcome is Found(job)
    assert job.payload == payload
  end
end

verified: types, contracts, tests (12), property (200 seeds), sim (not run)
          proven: not run
