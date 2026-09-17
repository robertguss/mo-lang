# sim: --faults 20 --until 0.5
module Jobq.Queue
expose Opening, Logs, Batch, Answer, Flushed, Policy, Queue, Queues, Warden, Worker, Workers, opening, flushed, stamp, policy, retained, guarded, spent?, due?, shelf_lines

use Jobq.Api{Routed, respond, route}
use Jobq.Board{Board, Call, Command, Decision, Outcome, Kept, board, decide, health_of, rebuilt, records, retaining, shelf_applied, shelf_records, shelf_snapshot, shelved, snapshot}
use Jobq.Job{Job, Phase, Making, shown, to_ms}
use Jobq.Store{Table, StoreError, blank, blank_log, cut_short?, emptied, journaled, line_of, open, open_log, pairs, reopened, rewritten, writing_to}

intent "The queue process: every call is decided against the board at once, and its records join a batch; the batch is appended to the log in one write, so one fsync covers every call taken since the last, and only then is each caller answered; the queue keeps the board as the log last held it beside the board it answers from, both sharing every page a batch did not change, so a batch the log did not take is answered 503 and the board goes back, a log that may end in part of a write is written whole with the next batch, and the store keeps no second copy of any job. The archive, jobq.archive beside the log, takes the done and dead jobs a look finds older than the retention, and every batch writes the archive's changes before the log's, so a kill between the two leaves the job archived. A queue that fails is started again and rebuilds its board from the log, answering 503 until it has; a warden counts the restarts and stops the service with exit 70 once more of them fall inside the window than the budget allows; and the chaos switch fails the queue on purpose after every N-th write is on disk."

never "a response is sent before its record is durable"
  for a in Answer.all
    a.changed and !a.durable
  end
end

# How a queue starts: the board its store's and its archive's records hold, and the two stores,
# which keep no values once the board holds them.
struct Opening
  board: Board
  table: Table
  archive: Table
end

# The two logs a queue writes: the live one, and the archive.
struct Logs
  live: Table
  shelf: Table
end

# The calls taken since the last flush: the board after them, the board as the logs hold it,
# the log and the archive, whether each may end in part of a write, their records and archive
# changes, and their outcomes, in order.
struct Batch
  board: Board
  durable: Board
  table: Table
  torn: Bool
  archive: Table
  archive_torn: Bool
  writes: List((String, Option(String)))
  shelved: List((String, Option(String)))
  outcomes: List(Outcome)
end

# An answer as it is sent: the outcome, whether its batch changed the store, and whether that
# change was on disk.
struct Answer
  outcome: Outcome
  changed: Bool
  durable: Bool
end

# After a flush: the board to answer from, which the logs now hold, the log and the archive,
# whether each may end in part of a write, and the answers.
struct Flushed
  board: Board
  table: Table
  torn: Bool
  archive: Table
  archive_torn: Bool
  answers: List(Answer)
end

# A queue over a store and an archive just opened; None when a record is not the job its key
# names.
fn opening(table: Table, archive: Table, now: Time) : Option(Opening)
  held = try rebuilt(pairs(table), pairs(archive), to_ms(now))
  Some(Opening(board: held, table: emptied(table), archive: emptied(archive)))
end

# An archive change as the line the archive keeps: the record, or the tombstone of a job deleted.
fn shelf_lines(changes: List((String, Option(String)))) : List(String)
  changes.map(fn(c) line_of((c.0, Some(c.1 or "deleted"))) end)
end

# The clock's now cut to whole milliseconds, as a job's times are kept.
fn stamp(clock: Clock) : Time
  to_ms(clock.now)
end

# The batch written: appended in one write, or, when the log may be torn, the log written whole
# from the board after the batch, which holds the batch too. On success each outcome is answered
# as decided; otherwise every one is 503 and the board goes back to the one the log holds, keeping
# the numbers already handed out.
#
# The archive's changes go first, and only then the log's: an archive that may be torn is written
# whole from the archive the logs hold plus the batch's changes. When the archive takes its changes
# and the log does not, the answers are 503 and the board goes back to the one the logs hold, which
# now includes the archive's changes.
fn flushed(fs: Fs, batch: Batch) : Flushed
  ensures result.answers.size == batch.outcomes.size

  if batch.writes.size == 0 and batch.shelved.size == 0
    return Flushed(board: batch.board, table: batch.table, torn: batch.torn, archive: batch.archive,
      archive_torn: batch.archive_torn,
      answers: batch.outcomes.map(fn(o) Answer(outcome: o, changed: false, durable: false) end))
  end
  case shelf_written(fs, batch)
    Ok(archive):
      shelf_torn = batch.archive_torn and batch.shelved.size == 0
      logged(fs, batch, archive, shelf_torn)
    Error(problem):
      torn = problem == Torn or batch.archive_torn
      reason = if torn
        "the archive may end in part of a write; it is written whole with the next batch"
      else
        "the archive did not take the change"
      end
      refused(batch, batch.durable,
        Flushed(board: batch.durable, table: batch.table, torn: batch.torn, archive: batch.archive,
        archive_torn: torn, answers: []),
        reason)
  end
end

# The batch's archive changes on disk: appended, or the archive written whole when it may be torn;
# nothing when the batch has none.
fn shelf_written(fs: Fs, batch: Batch) : Result(Table, StoreError)
  return Ok(batch.archive) if batch.shelved.size == 0
  if batch.archive_torn
    whole = shelf_lines(shelf_snapshot(batch.durable)).concat(shelf_lines(batch.shelved))
    return rewritten(fs, batch.archive, whole)
  end
  journaled(fs, batch.archive, shelf_lines(batch.shelved))
end

# The batch's records on disk once its archive changes are: appended, or the log written whole
# from the board after the batch when it may be torn.
fn logged(fs: Fs, batch: Batch, archive: Table, shelf_torn: Bool) : Flushed
  written = if batch.writes.size == 0
    Ok(batch.table)
  else
    if batch.torn
      rewritten(fs, batch.table, snapshot(batch.board).map(fn(w)
        line_of(w)
      end))
    else
      journaled(fs, batch.table, batch.writes.map(fn(w) line_of(w) end))
    end
  end
  case written
    Ok(table):
      Flushed(board: batch.board, table: table, torn: batch.torn and batch.writes.size == 0,
        archive: archive, archive_torn: shelf_torn, answers: batch.outcomes.map(fn(o)
        Answer(outcome: o, changed: true, durable: true)
      end))
    Error(problem):
      torn = problem == Torn or batch.torn
      reason = if torn
        "the log may end in part of a write; it is written whole with the next batch"
      else
        "the log did not take the change"
      end
      held = shelf_applied(batch.durable, batch.shelved)
      refused(batch, held,
        Flushed(board: held, table: batch.table, torn: torn, archive: archive,
        archive_torn: shelf_torn, answers: []),
        reason)
  end
end

# Every answer 503, and the board the logs hold, keeping the numbers already handed out.
fn refused(batch: Batch, durable: Board, kept: Flushed, reason: String) : Flushed
  var held = durable
  held.next = batch.board.next
  var after = kept
  after.board = held
  after.answers = batch.outcomes.map(fn(o) unanswered(o, reason) end)
  after
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
# the chaos switch, which fails the queue after every `crash_every`-th write, 0 for never, and how
# long a done or dead job stays on the board before it is archived.
struct Policy
  max_restarts: UInt64
  window_ms: UInt64
  crash_every: UInt64
  retain_ms: UInt64
end

# A policy that keeps done and dead jobs a day.
fn policy(max_restarts: UInt64, window_ms: UInt64, crash_every: UInt64) : Policy
  Policy(max_restarts: max_restarts, window_ms: window_ms, crash_every: crash_every,
    retain_ms: 86_400_000)
end

fn retained(rules: Policy, ms: UInt64) : Policy
  var after = rules
  after.retain_ms = ms
  after
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

# The board a restarted queue rebuilds from the logs its stores name, None when it cannot.
fn reopening(fs: Fs, logs: Logs, started: Time) : Option(Opening)
  case (reopened(fs, logs.live), reopened(fs, logs.shelf))
    (Ok(table), Ok(archive)): opening(table, archive, started)
    _: None
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
  archive: Table
  archive_torn: Bool
  writes: List((String, Option(String)))
  shelved: List((String, Option(String)))
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
    archive: start.archive, archive_torn: cut_short?(start.archive), writes: [], shelved: [],
    outcomes: [], restarts: restarts, applied: applied)
end

# Whether a call renames a queue. A rename is a batch of its own: the calls before it are flushed
# first and it is flushed at once, so no call decided after it shares its write. Otherwise an
# archive move decided after it would carry the new name to the archive, and a log that then
# refused the batch would leave that one job renamed while the rename was answered 503.
fn renames?(call: Call) : Bool
  call.command is Rename(queue: _, to: _)
end

# Whether the desk holds calls or moves not yet flushed.
fn pending?(desk: Desk) : Bool
  desk.outcomes.size > 0 or desk.writes.size > 0 or desk.shelved.size > 0
end

# The desk after a rename taken as a batch of its own, and whether the chaos switch failed the
# queue on the way: the calls kept before it flushed and answered, then the rename decided,
# flushed, and answered; the last asker kept is the rename's.
struct Alone
  desk: Desk
  failing: Bool
end

# A rename to take alone: the call, the time it is decided at, and the chaos switch's count.
struct Taken
  call: Call
  now: Time
  every: UInt64
end

fn alone(fs: Fs, warden: Handle(Warden), desk: Desk, waiting: List(Reply(Outcome)),
  taken: Taken) : Alone
  earlier = waiting.take(waiting.size - 1)
  var held = desk
  if pending?(desk)
    before = settled(fs, warden, desk, taken.every)
    if before.failing
      return Alone(desk: before.desk, failing: true)
    end
    delivered(earlier, before.answers)
    held = before.desk
  end
  end_of = settled(fs, warden, joined(held, decide(held.board, taken.call, taken.now)), taken.every)
  if !end_of.failing
    delivered(waiting.drop(earlier.size), end_of.answers)
  end
  Alone(desk: end_of.desk, failing: end_of.failing)
end

# The desk with a call decided: its records and its outcome join the batch.
fn joined(desk: Desk, decision: Decision) : Desk
  var after = desk
  after.board = decision.board
  after.writes = desk.writes.concat(decision.writes)
  after.shelved = desk.shelved.concat(decision.shelved)
  after.outcomes = desk.outcomes.push(with_restarts(decision.outcome, desk.restarts))
  after
end

# The desk with a look decided: its moves join the batch, with no outcome to answer.
fn swept(desk: Desk, decision: Decision) : Desk
  var after = desk
  after.board = decision.board
  after.writes = desk.writes.concat(decision.writes)
  after.shelved = desk.shelved.concat(decision.shelved)
  after
end

# The batch flushed, and the chaos switch looked at: when the batch's writes carry the count past
# a multiple of `every`, the warden is told the count, since the failure discards the queue's
# state, and the answers are not sent.
fn settled(fs: Fs, warden: Handle(Warden), desk: Desk, every: UInt64) : Settled
  done = flushed(fs,
    Batch(board: desk.board, durable: desk.durable, table: desk.table, torn: desk.torn,
    archive: desk.archive, archive_torn: desk.archive_torn, writes: desk.writes,
    shelved: desk.shelved, outcomes: desk.outcomes))
  took = done.answers.all?(fn(a) a.durable end)
  applied = if took: desk.applied + desk.writes.size + desk.shelved.size else: desk.applied
  var after = desk
  after.board = done.board
  after.durable = done.board
  after.table = done.table
  after.torn = done.torn
  after.archive = done.archive
  after.archive_torn = done.archive_torn
  after.writes = []
  after.shelved = []
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
fn given_or_rebuilt(fs: Fs, logs: Logs, started: Time, given: Option(Opening)) : Option(Opening)
  case given
    Some(held): Some(held)
    None: reopening(fs, logs, started)
  end
end

# The opening with its board keeping done and dead jobs as long as the policy says.
fn kept_for(start: Opening, rules: Policy) : Opening
  var held = start
  held.board = retaining(start.board, rules.retain_ms)
  held
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
process Queue(fs: Fs, clock: Clock, logs: Logs, started: Time, rules: Policy,
  warden: Handle(Warden)) mailbox: 100_000
  state
    desk: Desk = desk_of(Opening(board: board(started, 1), table: announced(warden, logs.live),
      archive: emptied(logs.shelf)),
      0, 0)
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
        start = given_or_rebuilt(fs, logs, started, given)
        state.failing = start is None
        if start is Some(held)
          state.desk = desk_of(kept_for(held, rules), restarts, applied)
          state.me = Some(me)
          me.send(Sweep)
        end
      Want(call):
        state.waiting = state.waiting.push(reply_to)
        if state.me is Some(_) and renames?(call)
          taken = Taken(call: call, now: stamp(clock), every: rules.crash_every)
          after = alone(fs, warden, state.desk, state.waiting, taken)
          state.desk = after.desk
          state.failing = after.failing
          state.waiting = []
        end
        if state.me is Some(me) and !renames?(call)
          state.desk = joined(state.desk, decide(state.desk.board, call, stamp(clock)))
          if !state.flushing
            me.send(Flush)
            state.flushing = true
          end
        end
      Sweep:
        if state.me is Some(me)
          decision = decide(state.desk.board, Call(worker: "", command: Health), stamp(clock))
          moved = decision.writes.size > 0 or decision.shelved.size > 0
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
supervisor Queues(fs: Fs, clock: Clock, logs: Logs, started: Time, rules: Policy,
  warden: Handle(Warden))
  child Warden(clock, rules), restart: :always, max_restarts: 0 per 1.minute
  child Queue(fs, clock, logs, started, rules,
    warden), restart: :always, max_restarts: 1_000_000 per 1.minute
end

# The warden and the queue it keeps: the queue told its own handle, and given the board its store
# opened with, so its first start replays nothing twice.
fn guarded(fs: Fs, clock: Clock, start: Opening, rules: Policy) : Handle(Queue)
  kept_by(fs, clock, Warden.start(clock, rules), start, rules)
end

fn kept_by(fs: Fs, clock: Clock, warden: Handle(Warden), start: Opening,
  rules: Policy) : Handle(Queue)
  logs = Logs(live: emptied(start.table), shelf: emptied(start.archive))
  queue = Queue.start(fs, clock, logs, start.board.started, rules, warden)
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

fn fresh_archive() : Table
  blank_log("d", "jobq.archive")
end

fn fresh_logs() : Logs
  Logs(live: fresh(), shelf: fresh_archive())
end

fn empty_start(clock: Clock) : Opening
  Opening(board: board(stamp(clock), 1), table: fresh(), archive: fresh_archive())
end

fn begun(fs: Fs, clock: Clock) : Handle(Queue)
  guarded(fs, clock, empty_start(clock), policy(5, 60_000, 0))
end

# A job to make with no backoff and no delay.
fn plain(queue: String, payload: String, max_tries: UInt64) : Making
  Making(queue: queue, key: None, payload: payload, max_tries: max_tries, backoff_ms: 0,
    delay_ms: 0)
end

# A job made to wait: a delay before it is queued at all, and a backoff after each fail.
fn waits(queue: String, payload: String, max_tries: UInt64, delay_ms: UInt64,
  backoff_ms: UInt64) : Making
  Making(queue: queue, key: None, payload: payload, max_tries: max_tries, backoff_ms: backoff_ms,
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
  case (open(fs, "d"), open_log(fs, "d", "jobq.archive"))
    (Ok(table), Ok(archive)):
      case opening(table, archive, clock.now)
        Some(held): served(guarded(fs, clock, held, policy(5, 60_000, 0)), worker, command)
        None: Unavailable(reason: "a record is not a job")
      end
    _: Unavailable(reason: "the store did not open")
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
  held = try reread(fs, now)
  Some(records(held))
end

# The board a queue opened on the store and archive now would hold.
fn reread(fs: Fs, now: Time) : Option(Board)
  case (open(fs, "d"), open_log(fs, "d", "jobq.archive"))
    (Ok(table), Ok(archive)): rebuilt(pairs(table), pairs(archive), now)
    _: None
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
  guarded(fs, clock, empty_start(clock), policy(1_000, 60_000, every))
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
      listing = served(queue, "p", Listing(queue: None, state: None, key: None))
      return Wrong(why: "a 503 left the store unlike the queue") if !matches_store?(listing, fs,
        stamp(clock))
    Empty:
      recovered(queue)
      if round < 150
        revived(queue)
      end
      return ended(queue, slow)
    Made(_) | Listed(_) | Removed | Missing | Conflict(_) | Healthy(_) | Tallied(_) | Renamed(queue: _,
      moved: _) | Absent(_):
      return Wrong(why: "a lease gave #{lent}")
  end
  Going
end

# Every job still leased acked by the worker its record names: a worker whose lease was granted
# but whose answer was lost under faults learns of it this way and finishes it.
fn recovered(queue: Handle(Queue))
  held = served(queue, "p", Listing(queue: None, state: Some(Leased), key: None))
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
  held = served(queue, "p", Listing(queue: None, state: Some(Dead), key: None))
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

# A job to make under a key, with no backoff and no delay.
fn keyed(queue: String, key: String, payload: String) : Making
  Making(queue: queue, key: Some(key), payload: payload, max_tries: 2, backoff_ms: 0, delay_ms: 0)
end

# A board at `at` holding j_1, done at `at`, kept a second before it is archived.
fn done_board(at: Time) : Board
  made = decide(retaining(board(at, 1), 1_000),
    Call(worker: "p", command: Create(making: keyed("q", "k", "x"))), at)
  held = decide(made.board, Call(worker: "w", command: Lease(queue: "q", lease_ms: 1_000)), at)
  decide(held.board, Call(worker: "w", command: Ack(id: "j_1")), at).board
end

# The durable batch that writes a board's jobs to a fresh log and archive.
fn written_whole(fs: Fs, b: Board) : Flushed
  flushed(fs,
    Batch(board: b, durable: board(b.started, 1), table: fresh(), torn: true,
    archive: fresh_archive(), archive_torn: false, writes: snapshot(b), shelved: [], outcomes: []))
end

# Whether each job a worker acked is in the store or the archive, and in only one of them.
fn each_kept_once(fs: Fs, now: Time, acked: List(UInt64)) : Bool
  case reread(fs, now)
    Some(held):
      live = records(held)
      shelf = shelf_records(held)
      acked.all?(fn(n) held_once?(live, shelf, n) end)
    None: true
  end
end

fn held_once?(live: List(String), shelf: List(String), number: UInt64) : Bool
  mark = "{\"id\": \"j_#{number}\","
  in_live = live.any?(fn(r) r.starts_with?(mark) end)
  in_shelf = shelf.any?(fn(r) r.starts_with?(mark) end)
  in_live != in_shelf
end

# The queues every job a board holds is in, live and archived, by number.
fn placements(b: Board) : List(String)
  records(b).concat(shelf_records(b)).map(fn(r) queue_named(r) end)
end

fn queue_named(record: String) : String
  case Json.decode(record)
    Ok(Object(fields)):
      case fields.get("queue")
        Some(String(name)): name
        Some(_) | None: ""
      end
    Ok(_) | Error(_): ""
  end
end

fn job_of_outcome(outcome: Outcome) : Job
  case outcome
    Found(one): one
    Made(one): one
    Listed(_) | Removed | Missing | Conflict(_) | Empty | Healthy(_) | Tallied(_) | Renamed(queue: _,
      moved: _) | Absent(_) | Unavailable(_):
      Job(number: 0, queue: "", key: None, state: Queued, payload: "", tries: 0, max_tries: 1,
        backoff_ms: 0, created_at: Time.from_parts(2026, 1, 1, 0, 0, 0),
        updated_at: Time.from_parts(2026, 1, 1, 0, 0, 0), run_at: None, worker: None,
        lease_until: None, reason: None, archived_at: None)
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
  assert matches_store?(served(queue, "p", Listing(queue: None, state: None, key: None)), fs,
    stamp(clock))
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
  assert matches_store?(served(queue, "p", Listing(queue: None, state: None, key: None)), fs,
    stamp(clock))
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
  assert matches_store?(served(queue, "p", Listing(queue: None, state: None, key: None)), fs,
    stamp(clock))
end

test "a batch the log did not take is 503, and the board goes back to what the store holds"
  fs = Fs.fixture()
  at = Time.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(empty)
  start = board(at, 1)
  one = decide(start, Call(worker: "p", command: Create(making: plain("q", "1", 1))), at)
  first = flushed(fs,
    Batch(board: one.board, durable: start, table: emptied(empty), torn: false,
    archive: fresh_archive(), archive_torn: false, writes: one.writes, shelved: [],
    outcomes: [one.outcome]))
  assert first.answers.map(fn(a) a.outcome end) == [one.outcome] and !first.torn
  two = decide(first.board, Call(worker: "p", command: Create(making: plain("q", "2", 1))), at)
  slow = Fs.fixture(delay: 1.minute)
  torn = flushed(slow,
    Batch(board: two.board, durable: first.board, table: first.table, torn: false,
    archive: fresh_archive(), archive_torn: false, writes: two.writes, shelved: [],
    outcomes: [two.outcome, one.outcome]))
  assert torn.torn and torn.answers.all?(fn(a) unavailable?(a.outcome) end)
  assert records(torn.board) == records(first.board) and torn.board.next == 3
  three = decide(torn.board, Call(worker: "p", command: Create(making: plain("q", "3", 1))), at)
  again = flushed(fs,
    Batch(board: three.board, durable: torn.board, table: torn.table, torn: true,
    archive: fresh_archive(), archive_torn: false, writes: three.writes, shelved: [],
    outcomes: [three.outcome]))
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
    Batch(board: one.board, durable: start, table: emptied(empty), torn: false,
    archive: fresh_archive(), archive_torn: false, writes: one.writes, shelved: [],
    outcomes: [one.outcome]))
  assert stuck.answers.all?(fn(a) unavailable?(a.outcome) end)
  assert stuck.answers.all?(fn(a) !a.changed and !a.durable end)
  assert records(stuck.board) == records(start) and records(stuck.board) == []
  assert health_of(stuck.board, at) == health_of(start, at)
  reading = decide(stuck.board,
    Call(worker: "p", command: Listing(queue: None, state: None, key: None)), at)
  read = flushed(unwritable,
    Batch(board: reading.board, durable: stuck.board, table: stuck.table, torn: stuck.torn,
    archive: fresh_archive(), archive_torn: false, writes: reading.writes, shelved: [],
    outcomes: [reading.outcome]))
  assert read.answers.map(fn(a) a.outcome end) == [Listed(jobs: [])]
  two = decide(stuck.board, Call(worker: "p", command: Create(making: plain("q", "2", 1))), at)
  again = flushed(fs,
    Batch(board: two.board, durable: stuck.board, table: stuck.table, torn: stuck.torn,
    archive: fresh_archive(), archive_torn: false, writes: two.writes, shelved: [],
    outcomes: [two.outcome]))
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
  listing = started_again(fs, clock, "p", Listing(queue: None, state: None, key: None))
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

test "a second create with a key is answered with the first job, after a restart too, and a delete frees it"
  fs = Fs.fixture()
  clock = Clock.fixture()
  queue = begun(fs, clock)
  first = served(queue, "p", Create(making: keyed("q", "order-1", "one")))
  assert first is Made(_) or unavailable?(first)
  again = served(queue, "p", Create(making: keyed("q", "order-1", "ignored")))
  if first is Made(made)
    assert again == Found(job: made) or unavailable?(again)
    later = started_again(fs, clock, "p", Create(making: keyed("q", "order-1", "later")))
    assert later == Found(job: made) or unavailable?(later)
    listed = started_again(fs, clock, "p",
      Listing(queue: Some("q"), state: None, key: Some("order-1")))
    assert listed == Listed(jobs: [made]) or unavailable?(listed)
    gone = served(queue, "p", Remove(id: "j_#{made.number}"))
    if gone == Removed
      fresh_one = served(queue, "p", Create(making: keyed("q", "order-1", "new")))
      assert unavailable?(fresh_one) or fresh_one is Made(_)
      if fresh_one is Made(other)
        assert other.number != made.number
      end
    end
  end
end

test "a batch writes the archive before the log, and a log that refuses after the archive took leaves the job archived"
  fs = Fs.fixture()
  at = Time.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  b = done_board(at)
  base = written_whole(fs, b)
  assert base.answers == [] and !base.torn
  now = at + 1_000.ms
  moved = decide(base.board, Call(worker: "p", command: Fetch(id: "j_1")), now)
  assert moved.shelved.size == 1 and moved.writes == [("j_1", None)]
  refused_log = flushed(fs,
    Batch(board: moved.board, durable: base.board, table: blank(".."), torn: false,
    archive: base.archive, archive_torn: false, writes: moved.writes, shelved: moved.shelved,
    outcomes: [moved.outcome]))
  assert refused_log.answers.all?(fn(a) unavailable?(a.outcome) and !a.durable end)
  assert records(refused_log.board) == [] and shelf_records(refused_log.board).size == 1
  assert health_of(refused_log.board, now).archived == 1
  assert fs.read("d/jobq.archive", within: 1.minute) is Ok(shelf_text)
  assert shelf_text.contains?("\"archived_at\"")
  assert fs.read("d/jobq.log", within: 1.minute) is Ok(log_text)
  assert log_text.contains?("SET j_1 ") and !log_text.contains?("DEL j_1")
  assert reread(fs, now) is Some(both)
  assert records(both) == [] and shelf_records(both) == shelf_records(refused_log.board)
  assert health_of(both, now).archived == 1 and health_of(both, now).done == 0
  finished = flushed(fs,
    Batch(board: moved.board, durable: base.board, table: base.table, torn: false,
    archive: base.archive, archive_torn: false, writes: moved.writes, shelved: moved.shelved,
    outcomes: [moved.outcome]))
  assert finished.answers.all?(fn(a) a.durable end)
  assert fs.read("d/jobq.log", within: 1.minute) is Ok(after_text)
  assert after_text.ends_with?("DEL j_1\n")
  assert reread(fs, now) is Some(once)
  assert shelf_records(once) == shelf_records(moved.board) and records(once) == []
end

test "an archive that refuses the move writes nothing to the log, and a torn one is written whole next time"
  fs = Fs.fixture()
  at = Time.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  base = written_whole(fs, done_board(at))
  now = at + 1_000.ms
  moved = decide(base.board, Call(worker: "p", command: Fetch(id: "j_1")), now)
  slow = Fs.fixture(delay: 1.minute)
  stuck = flushed(slow,
    Batch(board: moved.board, durable: base.board, table: base.table, torn: false,
    archive: base.archive, archive_torn: false, writes: moved.writes, shelved: moved.shelved,
    outcomes: [moved.outcome]))
  assert stuck.answers.all?(fn(a) unavailable?(a.outcome) end)
  assert stuck.archive_torn and !stuck.torn
  assert records(stuck.board) == records(base.board) and shelf_records(stuck.board) == []
  assert reread(fs, now) is Some(unmoved)
  assert records(unmoved).size == 1 and shelf_records(unmoved) == []
  again = decide(stuck.board, Call(worker: "p", command: Fetch(id: "j_1")), now)
  assert again.shelved.size == 1
  assert fs.write("d/jobq.archive", "SET j_1 {\"id\": \"j_", within: 1.minute) is Ok(_)
  whole = flushed(fs,
    Batch(board: again.board, durable: stuck.board, table: stuck.table, torn: stuck.torn,
    archive: stuck.archive, archive_torn: stuck.archive_torn, writes: again.writes,
    shelved: again.shelved, outcomes: [again.outcome]))
  assert whole.answers.all?(fn(a) a.durable end) and !whole.archive_torn
  assert reread(fs, now) is Some(moved_now)
  assert records(moved_now) == [] and shelf_records(moved_now) == shelf_records(again.board)
end

test "a deleted archived job is a tombstone in the archive, and its stale live record stays gone"
  fs = Fs.fixture()
  at = Time.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  base = written_whole(fs, done_board(at))
  now = at + 1_000.ms
  moved = decide(base.board, Call(worker: "p", command: Fetch(id: "j_1")), now)
  only_shelf = flushed(fs,
    Batch(board: moved.board, durable: base.board, table: blank(".."), torn: false,
    archive: base.archive, archive_torn: false, writes: moved.writes, shelved: moved.shelved,
    outcomes: []))
  gone = decide(only_shelf.board, Call(worker: "p", command: Remove(id: "j_1")), now)
  assert gone.outcome == Removed and gone.writes == []
  deleted = flushed(fs,
    Batch(board: gone.board, durable: only_shelf.board, table: base.table, torn: false,
    archive: only_shelf.archive, archive_torn: false, writes: gone.writes, shelved: gone.shelved,
    outcomes: [gone.outcome]))
  assert deleted.answers.map(fn(a) a.outcome end) == [Removed]
  assert fs.read("d/jobq.archive", within: 1.minute) is Ok(text)
  assert text.ends_with?("SET j_1 deleted\n")
  assert reread(fs, now) is Some(after)
  assert records(after) == [] and shelf_records(after) == []
  assert health_of(after, now).archived == 0 and health_of(after, now).done == 0
  made = decide(after, Call(worker: "p", command: Create(making: keyed("q", "k", "new"))), now)
  assert made.outcome is Made(_)
end

test "a queue opened on a job in both files counts it once, archived, and reads it by id"
  fs = Fs.fixture()
  clock = Clock.fixture()
  at = stamp(clock)
  b = done_board(at)
  moved = shelved(b, at + 1_000.ms)
  live = String.join(snapshot(b).map(fn(w) line_of(w) end), "")
  logged_live = fs.write("d/jobq.log", live, within: 1.minute) is Ok(_)
  shelf = String.join(shelf_lines(moved.shelved), "")
  wrote = logged_live and fs.write("d/jobq.archive", shelf, within: 1.minute) is Ok(_)
  health = started_again(fs, clock, "", Health)
  if wrote and health is Healthy(counts)
    assert counts.archived == 1 and counts.done == 0
  end
  read = started_again(fs, clock, "p", Fetch(id: "j_1"))
  if wrote and read is Found(one)
    assert one.archived_at is Some(_) and one.state == Done
  end
  retry = started_again(fs, clock, "p", Retry(id: "j_1"))
  assert retry == Conflict(reason: "j_1 is archived") or unavailable?(retry) or !wrote
  listing = started_again(fs, clock, "p", Listing(queue: None, state: None, key: None))
  assert listing == Listed(jobs: []) or unavailable?(listing) or !wrote
end

# The move's two writes under faults: the seed fails the archive's append, the log's, or neither,
# and a job acked is in the log or the archive, never both and never neither, whatever failed.
test "under faults, old done jobs move to the archive and each is kept exactly once"
  fs = Fs.fixture()
  clock = Clock.fixture()
  queue = guarded(fs, clock, empty_start(clock), retained(policy(5, 60_000, 0), 300))
  var acked = [0].take(0)
  for i in 0..6
    made = served(queue, "p", Create(making: keyed("q", "k#{i}", "job #{i}")))
    lent = served(queue, "w", Lease(queue: "q", lease_ms: 3_600_000))
    if made is Made(_) and lent is Found(held)
      done = served(queue, "w", Ack(id: "j_#{held.number}"))
      if done is Found(_)
        acked = acked.push(held.number)
      end
    end
  end
  slow = Fs.fixture(delay: 150.ms)
  for _ in 0..8
    moved = waited(slow)
    queue.send(Sweep)
    health = served(queue, "", Health)
    assert health is Healthy(_) or unavailable?(health) or !moved
    assert each_kept_once(fs, stamp(clock), acked)
  end
  for number in acked
    again = served(queue, "p", Fetch(id: "j_#{number}"))
    assert again is Found(_) or unavailable?(again)
    if again is Found(one)
      assert one.state == Done
    end
  end
  listing = served(queue, "p", Listing(queue: None, state: None, key: None))
  assert matches_store?(listing, fs, stamp(clock))
end

test "a handoff and a rename are answered once their records are in the log, and a restart keeps both"
  fs = Fs.fixture()
  clock = Clock.fixture()
  queue = begun(fs, clock)
  made = served(queue, "p", Create(making: keyed("q", "k", "one")))
  lent = served(queue, "w1", Lease(queue: "q", lease_ms: 3_600_000))
  passed = served(queue, "w1", Handoff(id: "j_1", to: "w2"))
  moved = served(queue, "op", Rename(queue: "q", to: "r"))
  clean = made is Made(_) and lent is Found(_) and passed is Found(_) and moved is Renamed(queue: _,
    moved: _)
  assert passed is Found(_) or unavailable?(passed) or passed is Conflict(_) or passed == Missing
  if clean and fs.read("d/jobq.log", within: 1.minute) is Ok(text)
    assert moved == Renamed(queue: "r", moved: 1)
    assert text.ends_with?("\"worker\": \"w2\", \"lease_until\": #{Json.encode((job_of_outcome(lent)).lease_until or stamp(clock))}}\nSET rename_1 {\"from\": \"q\", \"to\": \"r\"}\n")
    again = started_again(fs, clock, "p", Fetch(id: "j_1"))
    if again is Found(held)
      assert held.queue == "r" and held.worker == Some("w2") and held.tries == 1
      assert held.lease_until == job_of_outcome(lent).lease_until
    end
    keyed_again = started_again(fs, clock, "p",
      Listing(queue: Some("r"), state: None, key: Some("k")))
    assert keyed_again is Listed(_) or unavailable?(keyed_again)
    if keyed_again is Listed(found)
      assert found.size == 1
    end
    old_worker = started_again(fs, clock, "w1", Ack(id: "j_1"))
    assert old_worker is Conflict(_) or unavailable?(old_worker)
    new_worker = started_again(fs, clock, "w2", Ack(id: "j_1"))
    assert new_worker is Found(_) or unavailable?(new_worker)
    lease_old = started_again(fs, clock, "w3", Lease(queue: "q", lease_ms: 1_000))
    assert lease_old == Empty or unavailable?(lease_old)
  end
end

test "a rename the log did not take is 503 and moves nothing, and the next batch takes it whole"
  fs = Fs.fixture()
  at = Time.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  base = written_whole(fs, done_board(at))
  now = at + 1_000.ms
  archived_one = decide(base.board, Call(worker: "p", command: Health), now)
  shelf_first = flushed(fs,
    Batch(board: archived_one.board, durable: base.board, table: base.table, torn: false,
    archive: base.archive, archive_torn: false, writes: archived_one.writes,
    shelved: archived_one.shelved, outcomes: [archived_one.outcome]))
  assert shelf_first.answers.all?(fn(a) a.durable end)
  second = decide(shelf_first.board, Call(worker: "p", command: Create(making: plain("q", "2", 1))),
    now)
  took = flushed(fs,
    Batch(board: second.board, durable: shelf_first.board, table: shelf_first.table, torn: false,
    archive: shelf_first.archive, archive_torn: false, writes: second.writes, shelved: [],
    outcomes: [second.outcome]))
  moved = decide(took.board, Call(worker: "op", command: Rename(queue: "q", to: "r")), now)
  assert moved.outcome == Renamed(queue: "r", moved: 2)
  slow = Fs.fixture(delay: 1.minute)
  stuck = flushed(slow,
    Batch(board: moved.board, durable: took.board, table: took.table, torn: false,
    archive: took.archive, archive_torn: false, writes: moved.writes, shelved: [],
    outcomes: [moved.outcome]))
  assert stuck.answers.all?(fn(a) unavailable?(a.outcome) and !a.changed end)
  assert placements(stuck.board) == ["q", "q"]
  assert reread(fs, now) is Some(unmoved)
  assert placements(unmoved) == ["q", "q"]
  again = decide(stuck.board, Call(worker: "op", command: Rename(queue: "q", to: "r")), now)
  after = decide(again.board, Call(worker: "p", command: Create(making: plain("q", "3", 1))), now)
  whole = flushed(fs,
    Batch(board: after.board, durable: stuck.board, table: stuck.table, torn: stuck.torn,
    archive: stuck.archive, archive_torn: false, writes: again.writes.concat(after.writes),
    shelved: [], outcomes: [again.outcome, after.outcome]))
  assert whole.answers.map(fn(a) a.outcome end) == [again.outcome, after.outcome]
  assert reread(fs, now) is Some(renamed)
  assert placements(renamed) == ["r", "q", "r"]
  assert records(renamed) == records(after.board)
  assert shelf_records(renamed) == shelf_records(after.board)
  torn = flushed(fs,
    Batch(board: after.board, durable: whole.board, table: whole.table, torn: true,
    archive: whole.archive, archive_torn: true, writes: [("ids", Some("1001"))],
    shelved: [("j_9", None)], outcomes: []))
  assert !torn.torn and !torn.archive_torn
  assert fs.read("d/jobq.log", within: 1.minute) is Ok(text)
  assert text.contains?("SET rename_1 ") and text.contains?("\"renames\": 1}")
  assert reread(fs, now) is Some(rewritten_whole)
  assert placements(rewritten_whole) == ["r", "q", "r"]
end

# The rename's one write under faults: the seed fails it or not, and a reopened folder shows every
# job of the queue moved or none, each key used once, and no job held by two workers.
test "under faults, a rename under a load of leases, acks, keyed creates, and handoffs moves every job or none"
  fs = Fs.fixture()
  clock = Clock.fixture()
  queue = begun(fs, clock)
  for i in 0..4
    made = served(queue, "p", Create(making: keyed("q", "k#{i}", "job #{i}")))
    assert made is Made(_) or unavailable?(made)
  end
  lent = served(queue, "w1", Lease(queue: "q", lease_ms: 3_600_000))
  passed = if lent is Found(held)
    served(queue, "w1", Handoff(id: "j_#{held.number}", to: "w2"))
  else
    lent
  end
  assert passed is Found(_) or unavailable?(passed) or passed == Empty or passed is Conflict(_)
  queue.send(Sweep)
  moved = answer_of(queue, Call(worker: "op", command: Rename(queue: "q", to: "r")))
  assert moved is Renamed(queue: _, moved: _) or unavailable?(moved) or moved is Absent(_)
  after = served(queue, "p", Create(making: keyed("q", "k0", "after")))
  assert after is Made(_) or after is Found(_) or unavailable?(after)
  case reread(fs, stamp(clock))
    Some(held):
      later = if after is Made(one): one.number else: 0
      before = records(held).concat(shelf_records(held)).filter(fn(r)
        !r.starts_with?("{\"id\": \"j_#{later}\",")
      end).map(fn(r) queue_named(r) end)
      if moved is Renamed(queue: _, moved: _)
        assert before.all?(fn(name) name == "r" end)
      end
      if unavailable?(moved)
        assert !placements(held).contains?("r")
      end
      leased = decide(held,
        Call(worker: "p", command: Listing(queue: None, state: Some(Leased), key: None)),
        stamp(clock))
      if leased.outcome is Listed(jobs)
        assert jobs.size <= 1
        if passed is Found(one) and jobs.size == 1
          assert (jobs.first or one).worker == Some("w2")
        end
      end
    None:
      assert true
  end
  if moved is Renamed(queue: _, moved: _)
    ack = served(queue, "w2", Ack(id: "j_1"))
    assert ack is Found(_) or unavailable?(ack) or ack is Conflict(_) or ack == Missing
  end
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
  queue = kept_by(fs, clock, warden, empty_start(clock), rules)
  made = served(queue, "p", Create(making: plain("q", "one", 2)))
  lent = served(queue, "w1", Lease(queue: "q", lease_ms: 3_600_000))
  lost = if made is Made(one): lost_answer(fs, one) else: false
  second = Queue.start(fs, clock, fresh_logs(), stamp(clock), rules, warden)
  assert unavailable?(served(second, "p", Listing(queue: None, state: None, key: None)))
  health = answered(queue, slow, "", Health)
  assert health is Healthy(_) or unavailable?(health)
  if health is Healthy(counts)
    assert counts.restarts == 1
  end
  listing = answered(queue, slow, "p", Listing(queue: None, state: None, key: None))
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
  queue = Queue.start(fs, clock, fresh_logs(), stamp(clock), rules, Warden.start(clock, rules))
  assert unavailable?(served(queue, "p", Create(making: plain("q", "no", 2))))
  queue.send(Sweep)
  queue.send(Flush)
  start = empty_start(clock)
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

verified: types, contracts, tests (23), property (0 seeds), sim (100 runs, invariants (kept 2, tripped 1))
          proven: not run
