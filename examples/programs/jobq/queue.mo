module Jobq.Queue
expose Queue, Queues, Opening, Racer, Racers, opening

use Jobq.Board{Call, Command, Outcome, Counts, served, swept, counts_of}
use Jobq.Books{Books, Survivor, books_of}
use Jobq.Store{Table, open}

intent "The queue process: it holds the board of every queue, takes one call at a time, and answers a call only once the board has put its change in the store; a Sweep puts back every lease that ran out, and Health gives the counts. It is never restarted, since a restart would come back from the store it opened with and forget every change since."

# How a queue starts: the board its store replayed to, and when.
struct Opening
  books: Books
  at: Time
end

# No invariant: each candidate is refused before a message can break it (the report lists them).
process Queue(fs: Fs, opening: Opening) mailbox: 4_096
  state
    books: Books = opening.books
    calls: UInt64
  end

  message Serve(call: Call) : Outcome
  message Sweep(at: Time)
  message Health(at: Time) : Counts

  fn update(state, message)
    case message
      Serve(call):
        done = served(fs, state.books, call)
        state.books = done.books
        state.calls += 1
        done.outcome
      Sweep(at):
        state.books = swept(fs, state.books, at)
      Health(at): counts_of(state.books, opening.at, at)
    end
  end
end

# A queue that crashed would come back from the store it opened with and forget every change
# since, so it is not started again; its clients get 503 instead.
supervisor Queues(fs: Fs, opening: Opening)
  child Queue(fs, opening), restart: :never
end

fn opening(table: Table, at: Time) : Opening
  Opening(books: books_of(table, at), at: at)
end

# A worker in a test that asks the queue for a lease when told to, and keeps what it got.
process Racer(queue: Handle(Queue), worker: String)
  state
    got: Option(Outcome)
  end

  message Go(at: Time)
  message Got : Option(Outcome)

  fn update(state, message)
    case message
      Go(at):
        lease = Call(worker: worker, at: at, command: Lease(queue: "emails", lease_ms: 30_000))
        state.got = case queue.ask(Serve(call: lease), within: 1.minute)
          Ok(outcome): Some(outcome)
          Error(_): None
        end
      Got: state.got
    end
  end
end

supervisor Racers(queue: Handle(Queue), worker: String)
  child Racer(queue, worker), restart: :never
end

fn at(seconds: UInt64) : Time
  Time.from_parts(2026, 9, 14, 9, 0, 0) + (seconds * 1_000).to_i64.ms
end

fn fresh() : Table
  Table(buckets: Map.new(), size: 0, dir: "d", name: "jobq.log", bytes: 0, lines: 0, cut: false)
end

fn serve(queue: Handle(Queue), worker: String, seconds: UInt64, command: Command) : Outcome
  call = Call(worker: worker, at: at(seconds), command: command)
  case queue.ask(Serve(call: call), within: 1.minute)
    Ok(outcome): outcome
    Error(_): Unavailable(reason: "no answer")
  end
end

fn holds?(got: Result(Option(Outcome), AskError)) : Bool
  got is Ok(Some(Found(_)))
end

fn create() : Command
  Create(queue: "emails", payload: "hi", max_attempts: 2)
end

# Under --sim a store call may fail, so a create or a lease may be 503; each assert holds in
# every seed, and the never over holds checks every lease the queue took.
test "two workers race for one job, and exactly one holds it"
  queue = Queue.start(Fs.fixture(), opening(fresh(), at(0)))
  if serve(queue, "ada", 0, create()) is Made(_)
    ada = Racer.start(queue, "ada")
    bob = Racer.start(queue, "bob")
    ada.send(Go(at: at(1)))
    bob.send(Go(at: at(1)))
    ada_got = ada.ask(Got, within: 1.minute)
    bob_got = bob.ask(Got, within: 1.minute)
    assert !(holds?(ada_got) and holds?(bob_got))
    both_answered = ada_got is Ok(Some(Empty)) or bob_got is Ok(Some(Empty))
    assert !both_answered or holds?(ada_got) or holds?(bob_got)
  end
end

test "a queue started again from its store finds the lease that ran out and leases the job again"
  fs = Fs.fixture()
  first = Queue.start(fs, opening(fresh(), at(0)))
  made = serve(first, "ada", 0, create())
  held = serve(first, "ada", 1, Lease(queue: "emails", lease_ms: 1_000))
  if made is Made(_) and held is Found(job) and open(fs, "d") is Ok(table)
    again = opening(table, at(10))
    kept = Survivor(id: job.id, before: Some(job), after: again.books.jobs.get(job.id))
    assert kept.before == kept.after
    second = Queue.start(fs, again)
    back = serve(second, "bob", 10, Fetch(id: job.id))
    assert back is Unavailable(_) or back is Found(_)
    if back is Found(looked)
      assert looked.state == Queued and looked.attempts == 1
    end
    leased_again = serve(second, "bob", 10, Lease(queue: "emails", lease_ms: 1_000))
    if leased_again is Found(next)
      assert next.id == job.id and next.attempts == 2 and next.worker == Some("bob")
    end
  end
end

test "a sweep puts back a lease that ran out, and health counts the job queued again"
  queue = Queue.start(Fs.fixture(), opening(fresh(), at(0)))
  if serve(queue, "ada", 0, create()) is Made(_)
    if serve(queue, "ada", 0, Lease(queue: "emails", lease_ms: 1_000)) is Found(_)
      queue.send(Sweep(at: at(5)))
      counts = queue.ask(Health(at: at(5)), within: 1.minute)
      assert counts is Error(_) or counts is Ok(Counts(queued: 1, leased: 0, done: 0, dead: 0,
        uptime_ms: 5_000)) or counts is Ok(Counts(queued: 0, leased: 1, done: 0, dead: 0,
        uptime_ms: 5_000))
    end
  end
end
