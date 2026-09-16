# sim: --faults 20 --until 0.5
module Jobq.Queue
expose Opening, Batch, Answer, Flushed, Policy, Queue, Queues, Warden, Worker, Workers, opening, flushed, stamp, policy, guarded, spent?, due?

use Jobq.Api{Routed, respond, route}
use Jobq.Board{Board, Call, Command, Decision, Outcome, Kept, board, decide, health_of, rebuilt, records, snapshot}
use Jobq.Job{Job, Phase, Making, shown, to_ms}
use Jobq.Store{Table, StoreError, blank, cut_short?, emptied, journaled, line_of, open, pairs, reopened, rewritten, writing_to}

intent "The queue process: every call is decided against the board at once, and its records join a batch; the batch is appended to the log in one write, so one fsync covers every call taken since the last, and only then is each caller answered; the queue keeps the board as the log last held it beside the board it answers from, both sharing every page a batch did not change, so a batch the log did not take is answered 503 and the board goes back, a log that may end in part of a write is written whole with the next batch, and the store keeps no second copy of any job. A queue that fails is started again and rebuilds its board from the log, answering 503 until it has; a warden counts the restarts and stops the service with exit 70 once more of them fall inside the window than the budget allows; and the chaos switch fails the queue on purpose after every N-th write is on disk."

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

# Each asker the batch kept answered, in the order they asked; an asker whose deadline has
# passed is answered all the same, and the runtime drops the answer.
fn delivered(waiting: List(Reply(Outcome)), answers: List(Answer))
  for i in 0..waiting.size
    if waiting.get(i) is Some(held)
      held.answer(outcome_at(answers, i))
    end
  end
end

fn outcome_at(answers: List(Answer), i: UInt64) : Outcome
  case answers.get(i)
    Some(answer): answer.outcome
    None: Unavailable(reason: "no answer")
  end
end

# How the service keeps going: at most `max_restarts` restarts of the queue inside `window_ms`,
# and the chaos switch, which fails the queue after every `crash_every`-th write, 0 for never.
struct Policy
  max_restarts: UInt64
  window_ms: UInt64
  crash_every: UInt64
end

fn policy(max_restarts: UInt64, window_ms: UInt64, crash_every: UInt64) : Policy
  Policy(max_restarts: max_restarts, window_ms: window_ms, crash_every: crash_every)
end

# The restarts still inside the window at `now`: those less than `window_ms` before it.
fn recent(restarts: List(Time), now: Time, window_ms: UInt64) : List(Time)
  restarts.filter(fn(at) (now - at).ms < window_ms.to_i64 end)
end

# Whether a failure at `now` is one more than the budget allows: the restarts already inside the
# window have spent it.
fn spent?(restarts: List(Time), now: Time, rules: Policy) : Bool
  recent(restarts, now, rules.window_ms).size >= rules.max_restarts
end

# Whether the chaos switch comes round in a batch that took the board's writes from `before` to
# `after`: a multiple of `every` lies past `before` and at or below `after`.
fn due?(before: UInt64, after: UInt64, every: UInt64) : Bool
  every > 0 and after / every > before / every
end

# The outcome as the queue answers it: health with the restarts since the service started.
fn with_restarts(outcome: Outcome, restarts: UInt64) : Outcome
  if outcome is Healthy(counts)
    var told = counts
    told.restarts = restarts
    return Healthy(counts: told)
  end
  outcome
end

fn rebuilding() : Outcome
  Unavailable(reason: "the queue is rebuilding its board from the log")
end

# The warden keeps what must outlive a restart of the queue: how many there have been, when the
# recent ones were, and how many writes the board has applied. A queue announces itself from its
# state's first line, each time it starts; every start after the first is a restart, which the
# warden answers with the queue's `Begin`, unless it spends the budget, which trips the warden's
# invariant, and its line gives up at once, so the service exits 70 with the restarted queue
# still waiting and the log as the failure left it.
process Warden(clock: Clock, rules: Policy)
  state
    starts: UInt64
    restarts: UInt64
    times: List(Time)
    applied: UInt64
    spent: Bool
    queue: Option(Handle(Queue))
  end

  invariant "the queue restarts at most max_restarts times inside restart_window"
    !state.spent
  end

  message Born
  message Watch(queue: Handle(Queue))
  message Applied(count: UInt64) : UInt64
  message Restarts : UInt64

  fn update(state, message)
    case message
      Born:
        state.starts += 1
        if state.starts > 1
          now = stamp(clock)
          state.spent = spent?(state.times, now, rules)
          state.times = recent(state.times, now, rules.window_ms).push(now)
          state.restarts += 1
          if state.queue is Some(queue)
            queue.send(Begin(me: queue, restarts: state.restarts, applied: state.applied,
              opening: None))
          end
        end
      Watch(queue):
        state.queue = Some(queue)
      Applied(count):
        state.applied = count
        count
      Restarts: state.restarts
    end
  end
end

# The queue's first state line tells the warden it has started, and holds the store's log with
# no values until `Begin` gives the board.
fn announced(warden: Handle(Warden), store: Table) : Table
  warden.send(Born)
  emptied(store)
end

# The board a restarted queue rebuilds from the log its store names, None when it cannot.
fn reopening(fs: Fs, store: Table, started: Time) : Option(Opening)
  case reopened(fs, store)
    Ok(table): opening(table, started)
    Error(_): None
  end
end

# What the queue holds between two messages, beside the askers it keeps: the board it answers
# from, the board the log holds, the log, whether it may end in part of a write, the records and
# outcomes of the calls taken since the last flush, the restarts the warden counted, and the
# writes the board has applied.
struct Desk
  board: Board
  durable: Board
  table: Table
  torn: Bool
  writes: List((String, Option(String)))
  outcomes: List(Outcome)
  restarts: UInt64
  applied: UInt64
end

# A flush done: the desk after it, the answers, and whether the chaos switch failed the queue at
# it, once the warden holds the count.
struct Settled
  desk: Desk
  answers: List(Answer)
  failing: Bool
end

fn desk_of(start: Opening, restarts: UInt64, applied: UInt64) : Desk
  Desk(board: start.board, durable: start.board, table: start.table, torn: cut_short?(start.table),
    writes: [], outcomes: [], restarts: restarts, applied: applied)
end

# The desk with a call decided: its records and its outcome join the batch.
fn joined(desk: Desk, decision: Decision) : Desk
  var after = desk
  after.board = decision.board
  after.writes = desk.writes.concat(decision.writes)
  after.outcomes = desk.outcomes.push(with_restarts(decision.outcome, desk.restarts))
  after
end

# The desk with a look decided: its moves join the batch, with no outcome to answer.
fn swept(desk: Desk, decision: Decision) : Desk
  var after = desk
  after.board = decision.board
  after.writes = desk.writes.concat(decision.writes)
  after
end

# The batch flushed, and the chaos switch looked at: when the batch's writes carry the count past
# a multiple of `every`, the warden is told the count, since the failure discards the queue's
# state, and the answers are not sent.
fn settled(fs: Fs, warden: Handle(Warden), desk: Desk, every: UInt64) : Settled
  done = flushed(fs,
    Batch(board: desk.board, durable: desk.durable, table: desk.table, torn: desk.torn,
    writes: desk.writes, outcomes: desk.outcomes))
  took = done.answers.all?(fn(a) a.durable end)
  applied = if took: desk.applied + desk.writes.size else: desk.applied
  var after = desk
  after.board = done.board
  after.durable = done.board
  after.table = done.table
  after.torn = done.torn
  after.writes = []
  after.outcomes = []
  after.applied = applied
  if due?(desk.applied, applied, every)
    case warden.ask(Applied(count: applied), within: 1_000.ms)
      Ok(_) | Error(_):
        return Settled(desk: after, answers: done.answers, failing: true)
    end
  end
  Settled(desk: after, answers: done.answers, failing: false)
end

# The board given at the first start, or rebuilt from the log after a restart; None when the log
# cannot give one.
fn given_or_rebuilt(fs: Fs, store: Table, started: Time, given: Option(Opening)) : Option(Opening)
  case given
    Some(held): Some(held)
    None: reopening(fs, store, started)
  end
end

# The calls a queue took before `Begin`, each answered 503.
fn refusals(n: UInt64) : List(Answer)
  var answers = [Answer(outcome: rebuilding(), changed: false, durable: false)].take(0)
  for _ in 0..n
    answers = answers.push(Answer(outcome: rebuilding(), changed: false, durable: false))
  end
  answers
end

# The one process that holds the board and writes the store. A worker's `Want` joins the batch
# and, when it is the first since a flush, sends the queue a `Flush`, which the mailbox delivers
# after the calls already waiting; `Serve` flushes at once and answers the asker itself. Until
# `Begin` gives it its board, after its start or a restart, it writes nothing: a `Serve` is
# answered 503 at once, and a `Want` is kept and answered 503 when `Begin` comes, before the board
# is rebuilt.
process Queue(fs: Fs, clock: Clock, store: Table, started: Time, rules: Policy,
  warden: Handle(Warden)) mailbox: 100_000
  state
    desk: Desk = desk_of(Opening(board: board(started, 1), table: announced(warden, store)), 0, 0)
    waiting: List(Reply(Outcome))
    flushing: Bool
    me: Option(Handle(Queue))
    failing: Bool
  end

  invariant "the board is whole: it opened from the log, and the chaos switch has not come round"
    !state.failing
  end

  message Begin(me: Handle(Queue), restarts: UInt64, applied: UInt64, opening: Option(Opening))
  message Want(call: Call) : Outcome
  message Sweep
  message Flush
  message Serve(call: Call) : Outcome

  fn update(state, message)
    case message
      Begin(me: me, restarts: restarts, applied: applied, opening: given):
        held_back = state.waiting.size
        delivered(state.waiting, refusals(held_back))
        state.waiting = []
        start = given_or_rebuilt(fs, store, started, given)
        state.failing = start is None
        if start is Some(held)
          state.desk = desk_of(held, restarts, applied)
          state.me = Some(me)
          me.send(Sweep)
        end
      Want(call):
        state.waiting = state.waiting.push(reply_to)
        if state.me is Some(me)
          state.desk = joined(state.desk, decide(state.desk.board, call, stamp(clock)))
          if !state.flushing
            me.send(Flush)
            state.flushing = true
          end
        end
      Sweep:
        if state.me is Some(me)
          decision = decide(state.desk.board, Call(worker: "", command: Health), stamp(clock))
          moved = decision.writes.size > 0
          state.desk = swept(state.desk, decision)
          if moved and !state.flushing
            me.send(Flush)
            state.flushing = true
          end
        end
      Flush:
        if state.me is Some(_)
          end_of = settled(fs, warden, state.desk, rules.crash_every)
          if !end_of.failing
            delivered(state.waiting, end_of.answers)
          end
          state.failing = end_of.failing
          state.desk = end_of.desk
          state.waiting = []
          state.flushing = false
        end
      Serve(call):
        if state.me is Some(_)
          state.desk = joined(state.desk, decide(state.desk.board, call, stamp(clock)))
          end_of = settled(fs, warden, state.desk, rules.crash_every)
          if !end_of.failing
            delivered(state.waiting, end_of.answers)
          end
          state.failing = end_of.failing
          state.desk = end_of.desk
          state.waiting = []
          outcome_at(end_of.answers, end_of.answers.size - 1)
        else
          rebuilding()
        end
    end
  end
end

# A queue that fails is started again, and rebuilds its board from the log; the warden that
# counts its restarts gives up at its first failure, since a failure there is the budget spent.
supervisor Queues(fs: Fs, clock: Clock, store: Table, started: Time, rules: Policy,
  warden: Handle(Warden))
  child Warden(clock, rules), restart: :always, max_restarts: 0 per 1.minute
  child Queue(fs, clock, store, started, rules,
    warden), restart: :always, max_restarts: 1_000_000 per 1.minute
end

# The warden and the queue it keeps: the queue told its own handle, and given the board its store
# opened with, so its first start replays nothing twice.
fn guarded(fs: Fs, clock: Clock, start: Opening, rules: Policy) : Handle(Queue)
  kept_by(fs, clock, Warden.start(clock, rules), start, rules)
end

fn kept_by(fs: Fs, clock: Clock, warden: Handle(Warden), start: Opening,
  rules: Policy) : Handle(Queue)
  queue = Queue.start(fs, clock, emptied(start.table), start.board.started, rules, warden)
  warden.send(Watch(queue: queue))
  queue.send(Begin(me: queue, restarts: 0, applied: 0, opening: Some(start)))
  queue
end

# The queue's answer to one call, or 503: a queue that has not answered in five seconds, or that
# is down after a crash, costs the request that asked it and no other, and the next request is
# asked as if it had never come.
fn answer_of(queue: Handle(Queue), call: Call) : Outcome
  case queue.ask(Want(call: call), within: 5_000.ms)
    Ok(outcome): outcome
    Error(Timeout): Unavailable(reason: "the queue did not answer within 5 seconds")
    Error(Down): Unavailable(reason: "the queue failed and is rebuilding its board from the log")
  end
end

# One exchange: its request read into a route, answered at once or asked of the queue, whose
# answer comes when the batch the call joined is on disk.
process Worker(exchange: Exchange, queue: Handle(Queue))
  state
    answered: Bool
  end

  message Go

  fn update(state, message)
    case message
      Go:
        response = case route(exchange.request)
          Answered(made): made
          Asked(call): respond(answer_of(queue, call))
        end
        state.answered = exchange.reply(response, within: 10_000.ms) is Ok(_)
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
  guarded(fs, clock, Opening(board: board(stamp(clock), 1), table: fresh()), policy(5, 60_000, 0))
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
fn started_again(fs: Fs, clock: Clock, worker: String, command: Command) : Outcome
  case open(fs, "d")
    Ok(table):
      case opening(table, clock.now)
        Some(held): served(guarded(fs, clock, held, policy(5, 60_000, 0)), worker, command)
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
  !(served(queue, "p", Fetch(id: id)) is Found(_))
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
# The log's text with the lease's end moved into the past, written back.
fn aged_text(fs: Fs, text: String, until: String) : Bool
  past = text.replace(until, "\"2025-12-31T23:00:00Z\"")
  text.contains?(until) and fs.write("d/jobq.log", past, within: 1.minute) is Ok(_)
end

fn aged_log(fs: Fs, lent: Outcome) : Bool
  if lent is Found(held)
    until = Json.encode(held.lease_until or held.created_at)
    return case fs.read("d/jobq.log", within: 1.minute)
      Ok(text): aged_text(fs, text, until)
      Error(_): false
    end
  end
  false
end

# The call asked until the queue answers it with anything but 503, up to 50 times with a wait
# between, as a client asks while the queue rebuilds its board.
fn answered(queue: Handle(Queue), slow: Fs, worker: String, command: Command) : Outcome
  var got = rebuilding()
  for _ in 0..50
    got = served(queue, worker, command)
    if !unavailable?(got) or !waited(slow)
      break
    end
  end
  got
end

# A queue under a warden whose chaos switch fails it after every `every`-th write, with a budget
# no test spends.
fn chaotic(fs: Fs, clock: Clock, every: UInt64) : Handle(Queue)
  guarded(fs, clock, Opening(board: board(stamp(clock), 1), table: fresh()),
    policy(1_000, 60_000, every))
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
    Made(_) | Listed(_) | Removed | Missing | Conflict(_) | Healthy(_) | Tallied(_):
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
  if served(queue, "", Health) is Healthy(counts)
    return Ended if counts.queued == 0 and counts.scheduled == 0 and counts.leased == 0
  end
  Going
end

# A record on disk whose answer the failure took: job j_500, put in the log beside the queue's.
fn lost_answer(fs: Fs, one: Job) : Bool
  record = shown(one).replace("\"id\": \"j_#{one.number}\"", "\"id\": \"j_500\"")
  line = line_of(("j_500",
    Some(record.replace("\"payload\": \"one\"", "\"payload\": \"answer lost\""))))
  case fs.read("d/jobq.log", within: 1.minute)
    Ok(text): fs.write("d/jobq.log", "#{text}#{line}", within: 1.minute) is Ok(_)
    Error(_): false
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

# The incident's second lesson, at the flush: a store that cannot be written costs the writes in
# flight and nothing else. The folder is made unwritable by a store whose calls all run out of
# time, since no fixture turns a folder read-only part way through a run.
test "a log that cannot be written answers its writes 503, answers reads, and takes the next batch"
  fs = Fs.fixture()
  at = Time.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(empty)
  start = board(at, 1)
  unwritable = Fs.fixture(delay: 1.minute)
  one = decide(start, Call(worker: "p", command: Create(making: plain("q", "1", 1))), at)
  stuck = flushed(unwritable,
    Batch(board: one.board, durable: start, table: emptied(empty), torn: false, writes: one.writes,
    outcomes: [one.outcome]))
  assert stuck.answers.all?(fn(a) unavailable?(a.outcome) end)
  assert stuck.answers.all?(fn(a) !a.changed and !a.durable end)
  assert records(stuck.board) == records(start) and records(stuck.board) == []
  assert health_of(stuck.board, at) == health_of(start, at)
  reading = decide(stuck.board, Call(worker: "p", command: Listing(queue: None, state: None)), at)
  read = flushed(unwritable,
    Batch(board: reading.board, durable: stuck.board, table: stuck.table, torn: stuck.torn,
    writes: reading.writes, outcomes: [reading.outcome]))
  assert read.answers.map(fn(a) a.outcome end) == [Listed(jobs: [])]
  two = decide(stuck.board, Call(worker: "p", command: Create(making: plain("q", "2", 1))), at)
  again = flushed(fs,
    Batch(board: two.board, durable: stuck.board, table: stuck.table, torn: stuck.torn,
    writes: two.writes, outcomes: [two.outcome]))
  assert again.answers.map(fn(a) a.outcome end) == [two.outcome]
  assert again.answers.all?(fn(a) a.durable end) and !again.torn
  assert stored(fs, at) == Some(records(again.board))
end

test "a queue started again from its log finds a lease that ran out and hands the job out again"
  fs = Fs.fixture()
  clock = Clock.fixture()
  first = begun(fs, clock)
  made = served(first, "p", Create(making: plain("q", "x", 3)))
  lent = served(first, "w1", Lease(queue: "q", lease_ms: 100))
  aged = aged_log(fs, lent)
  again = started_again(fs, clock, "w2", Lease(queue: "q", lease_ms: 100))
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
  listing = started_again(fs, clock, "p", Listing(queue: None, state: None))
  assert listing is Listed(_) or unavailable?(listing)
  if wrote and listing is Listed(jobs)
    assert jobs.size == 2
    assert jobs.map(fn(j) j.tries end) == [0, 1]
    assert jobs.all?(fn(j) j.max_tries == 3 and j.backoff_ms == 0 end)
    assert jobs.all?(fn(j) j.state == Queued end)
  end
  lent = started_again(fs, clock, "w1", Lease(queue: "q", lease_ms: 60_000))
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

test "a failure inside the window spends a budget whose restarts are all inside it, and one after it does not"
  at = Time.fixture()
  rules = policy(2, 60_000, 0)
  assert !spent?([], at, rules)
  assert !spent?([at], at + 1.minute, rules)
  assert spent?([at, at + 1.seconds], at + 2.seconds, rules)
  assert !spent?([at, at + 1.seconds], at + 1.minute, rules)
  assert !spent?([at, at + 1.seconds], at + 61.seconds, rules)
  assert spent?([], at, policy(0, 60_000, 0))
  assert !spent?([at, at, at, at], at + 1.minute, policy(5, 1_000, 0))
end

test "the chaos switch comes round on every N-th write, once for a batch that passes it, and never at 0"
  assert !due?(0, 2, 3) and due?(2, 3, 3) and due?(0, 3, 3)
  assert !due?(3, 5, 3) and due?(5, 9, 3) and due?(4, 10, 3)
  assert due?(0, 1, 1) and due?(1, 2, 1)
  assert !due?(0, 1_000, 0)
  assert !due?(3, 3, 3)
end

# A process test cannot show a crash and still hold its asserts, so the restart's path is shown
# without one: a second queue started under the same warden is a birth after the first, which the
# warden counts as a restart and answers by beginning the queue it watches again, with no board,
# exactly as it answers a queue the runtime has restarted.
test "a queue begun again rebuilds its board from the log, keeps its leases and ids, and counts the restart"
  fs = Fs.fixture()
  clock = Clock.fixture()
  slow = Fs.fixture(delay: 10.ms)
  rules = policy(5, 60_000, 0)
  warden = Warden.start(clock, rules)
  queue = kept_by(fs, clock, warden, Opening(board: board(stamp(clock), 1), table: fresh()), rules)
  made = served(queue, "p", Create(making: plain("q", "one", 2)))
  lent = served(queue, "w1", Lease(queue: "q", lease_ms: 3_600_000))
  lost = if made is Made(one): lost_answer(fs, one) else: false
  second = Queue.start(fs, clock, fresh(), stamp(clock), rules, warden)
  assert unavailable?(served(second, "p", Listing(queue: None, state: None)))
  health = answered(queue, slow, "", Health)
  assert health is Healthy(_) or unavailable?(health)
  if health is Healthy(counts)
    assert counts.restarts == 1
  end
  listing = answered(queue, slow, "p", Listing(queue: None, state: None))
  assert matches_store?(listing, fs, stamp(clock))
  if lost and listing is Listed(jobs)
    assert jobs.any?(fn(j) j.number == 500 and j.payload == "answer lost" end)
  end
  if lent is Found(held)
    back = answered(queue, slow, "p", Fetch(id: "j_#{held.number}"))
    if back is Found(again)
      assert again.worker == Some("w1") and again.lease_until == held.lease_until
      assert again.state == Leased and again.tries == 1
    end
  end
  after = answered(queue, slow, "p", Create(making: plain("q", "after", 2)))
  if lost and after is Made(next)
    assert next.number > 500
  end
end

test "a queue not yet begun writes nothing, and answers every call 503, a kept one once it begins"
  fs = Fs.fixture()
  clock = Clock.fixture()
  rules = policy(5, 60_000, 0)
  queue = Queue.start(fs, clock, fresh(), stamp(clock), rules, Warden.start(clock, rules))
  assert unavailable?(served(queue, "p", Create(making: plain("q", "no", 2))))
  queue.send(Sweep)
  queue.send(Flush)
  start = Opening(board: board(stamp(clock), 1), table: fresh())
  queue.send(Begin(me: queue, restarts: 0, applied: 0, opening: Some(start)), delay: 100.ms)
  assert answer_of(queue,
    Call(worker: "p", command: Create(making: plain("q", "kept", 2)))) == rebuilding()
  assert fs.read("d/jobq.log", within: 1.minute) is Error(_)
  assert served(queue, "", Health) is Healthy(_)
end

test rejects "the chaos switch fails the queue once its third write is on disk"
  fs = Fs.fixture()
  queue = chaotic(fs, Clock.fixture(), 3)
  for i in 0..12
    outcome = served(queue, "p", Create(making: plain("q", "job #{i}", 2)))
    assert outcome is Made(_) or unavailable?(outcome)
  end
end

# The fault run with the failure injected: the seed decides where among the writes each seventh
# one falls, and every answer up to the failure is right or 503.
test rejects "under faults, the chaos switch fails the queue at a seventh write in the middle of the workers' rounds"
  fs = Fs.fixture()
  clock = Clock.fixture()
  queue = chaotic(fs, clock, 7)
  for i in 0..4
    made = served(queue, "p", Create(making: waits("q", "job #{i}", 2, 0, 0)))
    assert made is Made(_) or unavailable?(made)
  end
  slow = Fs.fixture(delay: 150.ms)
  for round in 0..40
    assert !(played(queue, fs, slow, clock, round) is Wrong(_))
  end
end

verified: types, contracts, tests (14), property (0 seeds), sim (100 runs, invariants (kept 2, tripped 1))
          proven: not run
