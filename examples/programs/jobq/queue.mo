# sim: --faults 20 --until 0.5
module Jobq.Queue
expose Opening, Batch, Answer, Flushed, Queue, Queues, Worker, Workers, opening, flushed, stamp

use Jobq.Api{Routed, respond, route}
use Jobq.Board{Board, Call, Command, Outcome, Kept, board, decide, rebuilt, records, snapshot}
use Jobq.Job{Phase, Making, shown, to_ms}
use Jobq.Store{Table, StoreError, blank, emptied, journaled, line_of, open, pairs, rewritten}

intent "The queue process: every call is decided against the board at once, and its records join a batch; the batch is appended to the log in one write, so one fsync covers every call taken since the last, and only then is each caller answered; the queue keeps the board as the log last held it beside the board it answers from, both sharing every page a batch did not change, so a batch the log did not take is answered 503 and the board goes back, a log that may end in part of a write is written whole with the next batch, and the store keeps no second copy of any job."

never "a response is sent before its record is durable"
  for a in Answer.all
    a.changed and !a.durable
  end
end

# How a queue starts: the board its store's records hold, and the store, which keeps no values
# once the board holds them.
struct Opening
  board: Board
  table: Table
end

# The calls taken since the last flush: the board after them, the board as the log holds it,
# the log, whether it may end in part of a write, their records, and their outcomes, in order.
struct Batch
  board: Board
  durable: Board
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

# After a flush: the board to answer from, which the log now holds, the log, whether it may end
# in part of a write, and the answers.
struct Flushed
  board: Board
  table: Table
  torn: Bool
  answers: List(Answer)
end

# A queue over a store just opened; None when a record is not the job its key names.
fn opening(table: Table, now: Time) : Option(Opening)
  held = try rebuilt(pairs(table), to_ms(now))
  Some(Opening(board: held, table: emptied(table)))
end

# The clock's now cut to whole milliseconds, as a job's times are kept.
fn stamp(clock: Clock) : Time
  to_ms(clock.now)
end

# The batch written: appended in one write, or, when the log may be torn, the log written whole
# from the board after the batch, which holds the batch too. On success each outcome is answered
# as decided; otherwise every one is 503 and the board goes back to the one the log holds, keeping
# the numbers already handed out.
fn flushed(fs: Fs, batch: Batch) : Flushed
  ensures result.answers.size == batch.outcomes.size

  if batch.writes.size == 0
    return Flushed(board: batch.board, table: batch.table, torn: batch.torn,
      answers: batch.outcomes.map(fn(o) Answer(outcome: o, changed: false, durable: false) end))
  end
  written = if batch.torn
    rewritten(fs, batch.table, snapshot(batch.board).map(fn(w)
      line_of(w)
    end))
  else
    journaled(fs, batch.table, batch.writes.map(fn(w) line_of(w) end))
  end
  case written
    Ok(table):
      Flushed(board: batch.board, table: table, torn: false, answers: batch.outcomes.map(fn(o)
        Answer(outcome: o, changed: true, durable: true)
      end))
    Error(problem): refused(batch, problem)
  end
end

fn refused(batch: Batch, problem: StoreError) : Flushed
  var held = batch.durable
  held.next = batch.board.next
  torn = problem == Torn or batch.torn
  reason = if torn
    "the log may end in part of a write; it is written whole with the next batch"
  else
    "the log did not take the change"
  end
  Flushed(board: held, table: batch.table, torn: torn,
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
    durable: Board = opening.board
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
            Batch(board: state.board, durable: state.durable, table: state.table, torn: state.torn,
            writes: state.writes, outcomes: state.outcomes))
          delivered(state.waiting, done.answers)
          state.board = done.board
          state.durable = done.board
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
          Batch(board: state.board, durable: state.durable, table: state.table, torn: state.torn,
          writes: state.writes, outcomes: state.outcomes))
        delivered(state.waiting, done.answers)
        state.board = done.board
        state.durable = done.board
        state.table = done.table
        state.torn = done.torn
        state.writes = []
        state.outcomes = []
        state.waiting = []
        state.flushing = false
      Serve(call):
        decision = decide(state.board, call, stamp(clock))
        done = flushed(fs,
          Batch(board: decision.board, durable: state.durable, table: state.table, torn: state.torn,
          writes: state.writes.concat(decision.writes),
          outcomes: state.outcomes.push(decision.outcome)))
        delivered(state.waiting, done.answers)
        state.board = done.board
        state.durable = done.board
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

# A job to make with no backoff and no delay.
fn plain(queue: String, payload: String, max_tries: UInt64) : Making
  Making(queue: queue, payload: payload, max_tries: max_tries, backoff_ms: 0, delay_ms: 0)
end

# A job made to wait: a delay before it is queued at all, and a backoff after each fail.
fn waits(queue: String, payload: String, max_tries: UInt64, delay_ms: UInt64,
  backoff_ms: UInt64) : Making
  Making(queue: queue, payload: payload, max_tries: max_tries, backoff_ms: backoff_ms,
    delay_ms: delay_ms)
end

# A record as the previous version wrote it, with attempts and max_attempts and no backoff.
fn old_record(id: String, state: String, attempts: UInt64, tail: String) : String
  "{\"id\": \"#{id}\", \"queue\": \"q\", \"state\": \"#{state}\", \"payload\": \"old\", \"attempts\": #{attempts}, \"max_attempts\": 3, \"created_at\": \"2026-09-14T09:00:00Z\", \"updated_at\": \"2026-09-14T09:05:00Z\"#{tail}}"
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

# Whether the job is no longer there to lease: a batch the log refused takes the board back to
# what the store holds, so under faults a job that was answered Made may be gone again. With no
# fault it is always there, and a lease that came back Empty is a fault of the queue's own.
fn gone?(queue: Handle(Queue), id: String) : Bool
  case served(queue, "p", Fetch(id: id))
    Found(_): false
    Made(_) | Listed(_) | Removed | Missing | Conflict(_) | Empty | Healthy(_) | Unavailable(_):
      true
  end
end

# Simulated time passes only while a test waits, so a wait on a fixture call is how a test lets a
# scheduled job come due (step 29; TOOLCHAIN-BUGS.md's frozen-clock note is older than that). The
# delay rides on the fixture the test builds, since a capability is held only as a parameter.
fn waited(slow: Fs) : Bool
  slow.write("wait", "x", within: 1.minute) is Ok(_)
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
# hold what the queue lists; Ended once nothing is queued, scheduled, or leased.
fn played(queue: Handle(Queue), fs: Fs, slow: Fs, clock: Clock, round: UInt64) : Played
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
      if round < 150
        revived(queue)
      end
      return ended(queue, slow)
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

# Every dead job put back in its queue, so a run ends with every job done.
fn revived(queue: Handle(Queue))
  held = served(queue, "p", Listing(queue: None, state: Some(Dead)))
  if held is Listed(jobs)
    for j in jobs
      back = served(queue, "p", Retry(id: "j_#{j.number}"))
      if unavailable?(back)
        break
      end
    end
  end
end

fn ended(queue: Handle(Queue), slow: Fs) : Played
  return Going if !waited(slow)
  case served(queue, "", Health)
    Healthy(counts):
      if counts.queued == 0 and counts.scheduled == 0 and counts.leased == 0: Ended else: Going
    Made(_) | Found(_) | Listed(_) | Removed | Missing | Conflict(_) | Empty | Unavailable(_): Going
  end
end

test "a call through the queue is answered once its record is in the log"
  fs = Fs.fixture()
  clock = Clock.fixture()
  queue = begun(fs, clock)
  made = served(queue, "p", Create(making: plain("emails", "hi", 2)))
  assert made is Made(_) or unavailable?(made)
  logged = fs.read("d/jobq.log", within: 1.minute)
  if made is Made(one) and logged is Ok(text)
    assert text.contains?("SET j_#{one.number} #{shown(one)}\n")
  end
  assert matches_store?(served(queue, "p", Listing(queue: None, state: None)), fs, stamp(clock))
end

test "a job made with a delay is in the log as scheduled, and is not leased before its run_at"
  fs = Fs.fixture()
  clock = Clock.fixture()
  queue = begun(fs, clock)
  made = served(queue, "p", Create(making: waits("q", "later", 2, 86_400_000, 0)))
  assert made is Made(_) or unavailable?(made)
  if made is Made(one) and fs.read("d/jobq.log", within: 1.minute) is Ok(text)
    assert one.state == Scheduled and one.run_at is Some(_) and one.tries == 0
    assert text.contains?("SET j_#{one.number} #{shown(one)}\n")
    assert text.contains?("\"state\": \"scheduled\"") and text.contains?("\"run_at\"")
  end
  lent = served(queue, "w1", Lease(queue: "q", lease_ms: 1_000))
  assert lent == Empty or unavailable?(lent)
  assert matches_store?(served(queue, "p", Listing(queue: None, state: None)), fs, stamp(clock))
end

test "a scheduled job is queued once the clock passes its run_at, and is leased with tries at 1"
  fs = Fs.fixture()
  clock = Clock.fixture()
  queue = begun(fs, clock)
  made = served(queue, "p", Create(making: waits("q", "soon", 2, 200, 0)))
  assert made is Made(_) or unavailable?(made)
  early = served(queue, "w1", Lease(queue: "q", lease_ms: 1_000))
  if made is Made(soon) and soon.run_at is Some(due) and stamp(clock) < due
    assert early == Empty or unavailable?(early)
  end
  moved = waited(Fs.fixture(delay: 400.ms))
  clean = made is Made(_) and !unavailable?(early) and moved
  lent = served(queue, "w1", Lease(queue: "q", lease_ms: 60_000))
  if made is Made(waiting) and clean
    assert lent is Found(_) or unavailable?(lent) or gone?(queue, "j_#{waiting.number}")
  end
  if clean and lent is Found(one)
    assert one.tries == 1 and one.state == Leased and one.run_at is None
    assert one.worker == Some("w1")
  end
  assert matches_store?(served(queue, "p", Listing(queue: None, state: None)), fs, stamp(clock))
end

test "a batch the log did not take is 503, and the board goes back to what the store holds"
  fs = Fs.fixture()
  at = Time.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(empty)
  start = board(at, 1)
  one = decide(start, Call(worker: "p", command: Create(making: plain("q", "1", 1))), at)
  first = flushed(fs,
    Batch(board: one.board, durable: start, table: emptied(empty), torn: false, writes: one.writes,
    outcomes: [one.outcome]))
  assert first.answers.map(fn(a) a.outcome end) == [one.outcome] and !first.torn
  two = decide(first.board, Call(worker: "p", command: Create(making: plain("q", "2", 1))), at)
  slow = Fs.fixture(delay: 1.minute)
  torn = flushed(slow,
    Batch(board: two.board, durable: first.board, table: first.table, torn: false,
    writes: two.writes, outcomes: [two.outcome, one.outcome]))
  assert torn.torn and torn.answers.all?(fn(a) unavailable?(a.outcome) end)
  assert records(torn.board) == records(first.board) and torn.board.next == 3
  three = decide(torn.board, Call(worker: "p", command: Create(making: plain("q", "3", 1))), at)
  again = flushed(fs,
    Batch(board: three.board, durable: torn.board, table: torn.table, torn: true,
    writes: three.writes, outcomes: [three.outcome]))
  assert !again.torn and again.answers.map(fn(a) a.outcome end) == [three.outcome]
  kept = Kept(before: records(again.board), after: stored(fs, at) or [])
  assert kept.after == kept.before
end

test "a queue started again from its log finds a lease that ran out and hands the job out again"
  fs = Fs.fixture()
  clock = Clock.fixture()
  first = begun(fs, clock)
  made = served(first, "p", Create(making: plain("q", "x", 3)))
  lent = served(first, "w1", Lease(queue: "q", lease_ms: 100))
  aged = aged_log(fs, lent)
  again = reopened(fs, clock, "w2", Lease(queue: "q", lease_ms: 100))
  if made is Made(_) and aged and again is Found(back)
    assert back.tries == 2 and back.worker == Some("w2")
  end
  assert again is Found(_) or unavailable?(again) or !aged
end

test "a queue started on a log the previous version wrote replays every job and writes the new names"
  fs = Fs.fixture()
  clock = Clock.fixture()
  held = ", \"worker\": \"w-old\", \"lease_until\": \"2000-01-01T00:00:00Z\""
  queued_line = old_record("j_1", "queued", 0, "")
  leased_line = old_record("j_2", "leased", 1, held)
  old = "SET ids 1000\nSET j_1 #{queued_line}\nSET j_2 #{leased_line}\n"
  wrote = fs.write("d/jobq.log", old, within: 1.minute) is Ok(_)
  listing = reopened(fs, clock, "p", Listing(queue: None, state: None))
  assert listing is Listed(_) or unavailable?(listing)
  if wrote and listing is Listed(jobs)
    assert jobs.size == 2
    assert jobs.map(fn(j) j.tries end) == [0, 1]
    assert jobs.all?(fn(j) j.max_tries == 3 and j.backoff_ms == 0 end)
    assert jobs.all?(fn(j) j.state == Queued end)
  end
  lent = reopened(fs, clock, "w1", Lease(queue: "q", lease_ms: 60_000))
  assert lent is Found(_) or unavailable?(lent) or !wrote
  if wrote and lent is Found(_) and fs.read("d/jobq.log", within: 1.minute) is Ok(text)
    written = text.split("\n").filter(fn(line) line != "" end)
    last_line = written.last or ""
    assert last_line.contains?("\"tries\": 1, \"max_tries\": 3, \"backoff_ms\": 0")
    assert !last_line.contains?("attempts")
  end
end

test "every answer is right or 503 with the store unchanged, and every job ends done or dead once faults stop"
  fs = Fs.fixture()
  clock = Clock.fixture()
  queue = begun(fs, clock)
  for i in 0..6
    backoff = if i % 2 == 0: 100 else: 0
    made = served(queue, "p", Create(making: waits("q", "job #{i}", 2, 0, backoff)))
    assert made is Made(_) or unavailable?(made)
  end
  slow = Fs.fixture(delay: 150.ms)
  var last = Going
  for round in 0..300
    last = played(queue, fs, slow, clock, round)
    if last != Going
      break
    end
  end
  assert last == Ended
end

verified: types, contracts, tests (7), property (0 seeds), sim (100 runs)
          proven: not run
