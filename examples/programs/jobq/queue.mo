# sim: --faults 20 --until 0.5
module Jobq.Queue
expose Opening, Batch, Answer, Flushed, Queue, Queues, Worker, Workers, opening, flushed, stamp

use Jobq.Api{Routed, respond, route}
use Jobq.Board{Board, Call, Command, Outcome, Kept, board, decide, rebuilt, records}
use Jobq.Job{Phase, shown, to_ms}
use Jobq.Store{Table, StoreError, blank, compact, open, pairs, put_all}

intent "The queue process: every call is decided against the board at once, and its records join a batch; the batch is appended to the store in one write, so one fsync covers every call taken since the last, and only then is each caller answered; a batch the log did not take is answered 503 and the board goes back to what the store holds, and a log that may end in part of a batch is rewritten whole before the next."

never "a response is sent before its record is durable"
  for a in Answer.all
    a.changed and !a.durable
  end
end

# How a queue starts: the board its store's records hold, and the store.
struct Opening
  board: Board
  table: Table
end

# The calls taken since the last flush: the board after them, the store as it was before them,
# whether its log may end in part of a write, their records, and their outcomes, in order.
struct Batch
  board: Board
  table: Table
  torn: Bool
  writes: List((String, Option(String)))
  outcomes: List(Outcome)
end

# An answer as it is sent: the outcome, whether its batch changed the store, and whether that
# change was on disk.
struct Answer
  outcome: Outcome
  changed: Bool
  durable: Bool
end

struct Flushed
  board: Board
  table: Table
  torn: Bool
  answers: List(Answer)
end

# A queue over a store just opened; None when a record is not the job its key names.
fn opening(table: Table, now: Time) : Option(Opening)
  held = try rebuilt(pairs(table), to_ms(now))
  Some(Opening(board: held, table: table))
end

# The clock's now cut to whole milliseconds, as a job's times are kept.
fn stamp(clock: Clock) : Time
  to_ms(clock.now)
end

# The batch written: rewritten whole first when the log may be torn, then every record in one
# append. On success each outcome is answered as decided; otherwise every one is 503 and the
# board is rebuilt from the store as it is, keeping the numbers already handed out.
fn flushed(fs: Fs, batch: Batch) : Flushed
  ensures result.answers.size == batch.outcomes.size

  if batch.writes.size == 0
    return Flushed(board: batch.board, table: batch.table, torn: batch.torn,
      answers: batch.outcomes.map(fn(o) Answer(outcome: o, changed: false, durable: false) end))
  end
  whole = if batch.torn: compact(fs, batch.table) else: Ok(batch.table)
  written = case whole
    Ok(ready): put_all(fs, ready, batch.writes)
    Error(problem): Error(problem)
  end
  case written
    Ok(table):
      Flushed(board: batch.board, table: table, torn: false, answers: batch.outcomes.map(fn(o)
        Answer(outcome: o, changed: true, durable: true)
      end))
    Error(problem): refused(batch, whole, problem)
  end
end

fn refused(batch: Batch, whole: Result(Table, StoreError), problem: StoreError) : Flushed
  table = case whole
    Ok(ready): ready
    Error(_): batch.table
  end
  var held = rebuilt(pairs(table), batch.board.started) or batch.board
  held.next = batch.board.next
  torn = problem == Torn or (batch.torn and whole is Error(_))
  reason = if torn
    "the log may end in part of a write; it is rewritten whole before the next"
  else
    "the log did not take the change"
  end
  Flushed(board: held, table: table, torn: torn,
    answers: batch.outcomes.map(fn(o) unanswered(o, reason) end))
end

# An outcome the log did not take, answered 503 instead.
fn unanswered(outcome: Outcome, reason: String) : Answer
  refused_outcome = if outcome is Unavailable(_): outcome else: Unavailable(reason: reason)
  Answer(outcome: refused_outcome, changed: false, durable: false)
end

# Each waiting worker told its answer, in the order they asked.
fn delivered(waiting: List(Handle(Worker)), answers: List(Answer))
  for i in 0..waiting.size
    if waiting.get(i) is Some(worker)
      worker.send(Done(outcome: outcome_at(answers, i)))
    end
  end
end

fn outcome_at(answers: List(Answer), i: UInt64) : Outcome
  case answers.get(i)
    Some(answer): answer.outcome
    None: Unavailable(reason: "no answer")
  end
end

# The one process that holds the board and writes the store. A worker's `Want` joins the batch
# and, when it is the first since a flush, sends the queue a `Flush`, which the mailbox delivers
# after the calls already waiting; `Serve` flushes at once and answers the asker itself.
process Queue(fs: Fs, clock: Clock, opening: Opening) mailbox: 100_000
  state
    board: Board = opening.board
    table: Table = opening.table
    torn: Bool
    writes: List((String, Option(String)))
    outcomes: List(Outcome)
    waiting: List(Handle(Worker))
    flushing: Bool
    me: Option(Handle(Queue))
  end

  message Begin(me: Handle(Queue))
  message Want(call: Call, from: Handle(Worker))
  message Sweep
  message Flush
  message Serve(call: Call) : Outcome

  fn update(state, message)
    case message
      Begin(me):
        state.me = Some(me)
      Want(call: call, from: from):
        decision = decide(state.board, call, stamp(clock))
        state.board = decision.board
        state.writes = state.writes.concat(decision.writes)
        state.outcomes = state.outcomes.push(decision.outcome)
        state.waiting = state.waiting.push(from)
        if !state.flushing and state.me is Some(me)
          me.send(Flush)
          state.flushing = true
        end
        if state.me is None
          done = flushed(fs,
            Batch(board: state.board, table: state.table, torn: state.torn, writes: state.writes,
            outcomes: state.outcomes))
          delivered(state.waiting, done.answers)
          state.board = done.board
          state.table = done.table
          state.torn = done.torn
          state.writes = []
          state.outcomes = []
          state.waiting = []
        end
      Sweep:
        decision = decide(state.board, Call(worker: "", command: Health), stamp(clock))
        state.board = decision.board
        state.writes = state.writes.concat(decision.writes)
        if decision.writes.size > 0 and !state.flushing and state.me is Some(me)
          me.send(Flush)
          state.flushing = true
        end
      Flush:
        done = flushed(fs,
          Batch(board: state.board, table: state.table, torn: state.torn, writes: state.writes,
          outcomes: state.outcomes))
        delivered(state.waiting, done.answers)
        state.board = done.board
        state.table = done.table
        state.torn = done.torn
        state.writes = []
        state.outcomes = []
        state.waiting = []
        state.flushing = false
      Serve(call):
        decision = decide(state.board, call, stamp(clock))
        done = flushed(fs,
          Batch(board: decision.board, table: state.table, torn: state.torn,
          writes: state.writes.concat(decision.writes),
          outcomes: state.outcomes.push(decision.outcome)))
        delivered(state.waiting, done.answers)
        state.board = done.board
        state.table = done.table
        state.torn = done.torn
        state.writes = []
        state.outcomes = []
        state.waiting = []
        outcome_at(done.answers, done.answers.size - 1)
    end
  end
end

# A queue that crashed would come back from the store it opened with and forget every change
# since, so it is not started again; its callers get 503 instead.
supervisor Queues(fs: Fs, clock: Clock, opening: Opening, exchange: Exchange, queue: Handle(Queue))
  child Queue(fs, clock, opening), restart: :never
  child Worker(exchange, queue), restart: :never
end

# One exchange: its request read into a route, answered at once or asked of the queue, and its
# response written when the queue's answer comes.
process Worker(exchange: Exchange, queue: Handle(Queue))
  state
    answered: Bool
  end

  message Go(me: Handle(Worker))
  message Done(outcome: Outcome)

  fn update(state, message)
    case message
      Go(me):
        case route(exchange.request)
          Answered(response):
            state.answered = exchange.reply(response, within: 10_000.ms) is Ok(_)
          Asked(call): queue.send(Want(call: call, from: me))
        end
      Done(outcome):
        state.answered = exchange.reply(respond(outcome), within: 10_000.ms) is Ok(_)
    end
  end
end

supervisor Workers(exchange: Exchange, queue: Handle(Queue))
  child Worker(exchange, queue), restart: :never
end

# An empty store over the log d/jobq.log, for a test that must not fail before it starts.
fn fresh() : Table
  blank("d")
end

fn begun(fs: Fs, clock: Clock) : Handle(Queue)
  Queue.start(fs, clock, Opening(board: board(stamp(clock), 1), table: fresh()))
end

fn served(queue: Handle(Queue), worker: String, command: Command) : Outcome
  case queue.ask(Serve(call: Call(worker: worker, command: command)), within: 1.minute)
    Ok(outcome): outcome
    Error(_): Unavailable(reason: "no answer")
  end
end

# A queue started again from what the store holds now, asked one call.
fn reopened(fs: Fs, clock: Clock, worker: String, command: Command) : Outcome
  case open(fs, "d")
    Ok(table):
      case opening(table, clock.now)
        Some(held): served(Queue.start(fs, clock, held), worker, command)
        None: Unavailable(reason: "a record is not a job")
      end
    Error(_): Unavailable(reason: "the store did not open")
  end
end

fn unavailable?(outcome: Outcome) : Bool
  outcome is Unavailable(_)
end

# The records a queue opened on the store now would hold, or None when it cannot be read.
fn stored(fs: Fs, now: Time) : Option(List(String))
  case open(fs, "d")
    Ok(table):
      held = try rebuilt(pairs(table), now)
      Some(records(held))
    Error(_): None
  end
end

# Whether a listing matches what the store holds: the store may be unreadable under faults, and a
# listing that was not answered says nothing.
fn matches_store?(listing: Outcome, fs: Fs, now: Time) : Bool
  case (listing, stored(fs, now))
    (Listed(jobs), Some(held)): jobs.map(fn(j) shown(j) end) == held
    _: true
  end
end

# The log with a lease's end moved an hour before the service started, as if it had stopped and
# the lease ran out while it was down; true once the log says so.
fn aged_log(fs: Fs, lent: Outcome) : Bool
  case lent
    Found(held):
      until = Json.encode(held.lease_until or held.created_at)
      case fs.read("d/jobq.log", within: 1.minute)
        Ok(text):
          past = text.replace(until, "\"2025-12-31T23:00:00Z\"")
          text.contains?(until) and fs.write("d/jobq.log", past, within: 1.minute) is Ok(_)
        Error(_): false
      end
    Made(_) | Listed(_) | Removed | Missing | Conflict(_) | Empty | Healthy(_) | Unavailable(_):
      false
  end
end

enum Played
  Going
  Ended
  Wrong(why: String)
end

# One round of a worker's loop: lease, then ack, or fail every fourth; after a 503 the store must
# hold what the queue lists; Ended once nothing is queued or leased.
fn played(queue: Handle(Queue), fs: Fs, clock: Clock, round: UInt64) : Played
  worker = "w#{round % 3}"
  lent = served(queue, worker, Lease(queue: "q", lease_ms: 3_600_000))
  case lent
    Found(held):
      return Wrong(why: "leased to #{held.worker}") if held.worker != Some(worker)
      settle = if round % 4 == 0
        Fail(id: "j_#{held.number}", reason: "retry")
      else
        Ack(id: "j_#{held.number}")
      end
      after = served(queue, worker, settle)
      return Wrong(why: "a settle gave #{after}") if !(after is Found(_)) and !unavailable?(after)
    Unavailable(_):
      listing = served(queue, "p", Listing(queue: None, state: None))
      return Wrong(why: "a 503 left the store unlike the queue") if !matches_store?(listing, fs,
        stamp(clock))
    Empty:
      recovered(queue)
      return ended(queue)
    Made(_) | Listed(_) | Removed | Missing | Conflict(_) | Healthy(_):
      return Wrong(why: "a lease gave #{lent}")
  end
  Going
end

# Every job still leased acked by the worker its record names: a worker whose lease was granted
# but whose answer was lost under faults learns of it this way and finishes it.
fn recovered(queue: Handle(Queue))
  held = served(queue, "p", Listing(queue: None, state: Some(Leased)))
  if held is Listed(jobs)
    for j in jobs
      settle = served(queue, j.worker or "p", Ack(id: "j_#{j.number}"))
      if unavailable?(settle)
        break
      end
    end
  end
end

fn ended(queue: Handle(Queue)) : Played
  case served(queue, "", Health)
    Healthy(counts): if counts.queued == 0 and counts.leased == 0: Ended else: Going
    Made(_) | Found(_) | Listed(_) | Removed | Missing | Conflict(_) | Empty | Unavailable(_): Going
  end
end

test "a call through the queue is answered once its record is in the log"
  fs = Fs.fixture()
  clock = Clock.fixture()
  queue = begun(fs, clock)
  made = served(queue, "p", Create(queue: "emails", payload: "hi", max_attempts: 2))
  assert made is Made(_) or unavailable?(made)
  logged = fs.read("d/jobq.log", within: 1.minute)
  if made is Made(one) and logged is Ok(text)
    assert text.contains?("SET j_#{one.number} #{shown(one)}\n")
  end
  assert matches_store?(served(queue, "p", Listing(queue: None, state: None)), fs, stamp(clock))
end

test "a batch the log did not take is 503, and the board goes back to what the store holds"
  fs = Fs.fixture()
  at = Time.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(empty)
  one = decide(board(at, 1),
    Call(worker: "p", command: Create(queue: "q", payload: "1", max_attempts: 1)), at)
  first = flushed(fs,
    Batch(board: one.board, table: empty, torn: false, writes: one.writes, outcomes: [one.outcome]))
  assert first.answers.map(fn(a) a.outcome end) == [one.outcome] and !first.torn
  two = decide(first.board,
    Call(worker: "p", command: Create(queue: "q", payload: "2", max_attempts: 1)), at)
  slow = Fs.fixture(delay: 1.minute)
  torn = flushed(slow,
    Batch(board: two.board, table: first.table, torn: false, writes: two.writes,
    outcomes: [two.outcome, one.outcome]))
  assert torn.torn and torn.answers.all?(fn(a) unavailable?(a.outcome) end)
  assert records(torn.board) == records(first.board) and torn.board.next == 3
  three = decide(torn.board,
    Call(worker: "p", command: Create(queue: "q", payload: "3", max_attempts: 1)), at)
  again = flushed(fs,
    Batch(board: three.board, table: torn.table, torn: true, writes: three.writes,
    outcomes: [three.outcome]))
  assert !again.torn and again.answers.map(fn(a) a.outcome end) == [three.outcome]
  kept = Kept(before: records(again.board), after: stored(fs, at) or [])
  assert kept.after == kept.before
end

test "a queue started again from its log finds a lease that ran out and hands the job out again"
  fs = Fs.fixture()
  clock = Clock.fixture()
  first = begun(fs, clock)
  made = served(first, "p", Create(queue: "q", payload: "x", max_attempts: 3))
  lent = served(first, "w1", Lease(queue: "q", lease_ms: 100))
  aged = aged_log(fs, lent)
  again = reopened(fs, clock, "w2", Lease(queue: "q", lease_ms: 100))
  if made is Made(_) and aged and again is Found(retried)
    assert retried.attempts == 2 and retried.worker == Some("w2")
  end
  assert again is Found(_) or unavailable?(again) or !aged
end

test "every answer is right or 503 with the store unchanged, and every job ends done or dead once faults stop"
  fs = Fs.fixture()
  clock = Clock.fixture()
  queue = begun(fs, clock)
  for i in 0..6
    made = served(queue, "p", Create(queue: "q", payload: "job #{i}", max_attempts: 2))
    assert made is Made(_) or unavailable?(made)
  end
  var last = Going
  for round in 0..300
    last = played(queue, fs, clock, round)
    if last != Going
      break
    end
  end
  assert last == Ended
end

verified: types, contracts, tests (4), property (0 seeds), sim (100 runs)
          proven: not run
