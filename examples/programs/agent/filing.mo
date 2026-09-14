module Agent.Filing
expose Written, readied, created, looked, listed, transcribed, cancelled, put, finished, swept, next_line

use Agent.Record{Order, Record, Status, default_budget, record, final?, id_of, number_of}
use Agent.Shelf{Entry, Shelf, Readied, Moment, Asked, Named, Placed, Ended, Ending, Outcome, Verdict, Change, Put, Settled, Swept, unready, grace, with_shelf, opened_answer, verdict_of, ending, settled_run}
use Agent.Transcript{Step, header_line, step_line, end_line, unreplayed, replayed, steps_of, log_of}

intent "What the book of runs does: it opens the logs into the shelf, failing a run a log left running as restarted, and writes each change (a run made, a step, an end, a cancel, a run lost) to its run's log before the shelf takes it."

never "a step reaches a log before the step before it"
  for w in Written.all
    w.n != w.after + 1
  end
end

never "two runs write to one log"
  for w in Written.all, v in Written.all if w.log == v.log
    w.run != v.run
  end
end

# One step line written: the run, its log, the step's number, and the number of the last step
# the log held before it.
struct Written
  run: String
  log: String
  n: UInt64
  after: UInt64
end

fn readied(fs: Fs, runs: String, ready: Readied, at: Moment) : Readied
  return ready if ready.opened
  case opened(fs, runs, at)
    Ok(shelf): Readied(shelf: shelf, opened: true, why: "")
    Error(why): Readied(shelf: ready.shelf, opened: false, why: why)
  end
end

# The shelf from the logs in the runs folder, which is made when it is not there, in the order of
# their ids; a run a log leaves running gets its end line, failed as restarted.
fn opened(fs: Fs, runs: String, at: Moment) : Result(Shelf, String)
  if fs.mkdir(runs, within: at.by) is Error(_)
    return Error("cannot make its folder #{runs}")
  end
  logs = try logs_in(fs, runs, at.by)
  var shelf = unready().shelf
  for name in logs
    shelf = try shelved(fs, runs, shelf, name, at)
  end
  Ok(shelf)
end

fn logs_in(fs: Fs, runs: String, by: Deadline) : Result(List(String), String)
  case fs.scoped(runs).list(within: by)
    Ok(names):
      logs = names.filter(fn(name) log_number(name) is Some(_) end)
      Ok(logs.sort_by(fn(name) log_number(name) or 0 end))
    Error(_): Error("cannot list its folder #{runs}")
  end
end

fn log_number(name: String) : Option(UInt64)
  return None if !name.ends_with?(".log")
  number_of(name.slice(0, name.size - 4))
end

fn shelved(fs: Fs, runs: String, shelf: Shelf, name: String, at: Moment) : Result(Shelf, String)
  replay = case fs.scoped(runs).fold_lines(name, unreplayed(), within: at.by,
    fn(r, line) replayed(r, line) end)
    Ok(done): Some(done)
    Error(_): None
  end
  var next = shelf
  next.next = max_of(shelf.next, (log_number(name) or 0) + 1)
  case replay
    Some(read):
      case read.run
        Some(run):
          restarted_into(fs, runs, next,
            Entry(run: run, steps: read.steps, lost_at: run.updated_at), at)
        None: Ok(next)
      end
    None: Error("cannot read #{runs}/#{name}")
  end
end

fn restarted_into(fs: Fs, runs: String, shelf: Shelf, entry: Entry, at: Moment) : Result(Shelf,
  String)
  var next = shelf
  if entry.run.status != Running
    next.entries = shelf.entries.set(entry.run.id, entry)
    return Ok(next)
  end
  # A new line first: a log a crash cut short may end in part of a line, which the end must not
  # join; the empty line it leaves otherwise is not the log's and is left out.
  line = "\n#{end_line(at.now, Failed, None, Some("restarted"))}"
  if fs.scoped(runs).append("#{entry.run.id}.log", line, within: at.by) is Error(_)
    return Error("cannot write #{log_of(runs, entry.run.id)}")
  end
  var failed = entry
  failed.run = settled_run(entry.run, ending(Failed, None, Some("restarted")), at.now)
  next.entries = shelf.entries.set(entry.run.id, failed)
  next.restarted = shelf.restarted + 1
  Ok(next)
end

# A new run in a folder that is there, once its first line is in its log; its id is spent either
# way, so no id is handed out twice.
fn created(fs: Fs, runs: String, ready: Readied, asked: Asked, at: Moment) : Change
  return unavailable(ready) if !ready.opened
  case fs.scoped(asked.order.folder).list(within: at.by)
    Ok(_): made(fs, runs, ready.shelf, asked, at)
    Error(Timeout):
      Change(shelf: ready.shelf,
        outcome: Unavailable(why: "the folder could not be looked at in time"))
    Error(Missing(_)) | Error(NotText): Change(shelf: ready.shelf, outcome: NoFolder)
  end
end

fn unavailable(ready: Readied) : Change
  Change(shelf: ready.shelf,
    outcome: Unavailable(why: "the book cannot open its logs: #{ready.why}"))
end

fn made(fs: Fs, runs: String, shelf: Shelf, asked: Asked, at: Moment) : Change
  id = id_of(shelf.next)
  run = record(id, asked.owner, asked.order.goal, at.now)
  var next = shelf
  next.next = shelf.next + 1
  if fs.scoped(runs).append("#{id}.log", header_line(run, asked.order), within: at.by) is Error(_)
    return Change(shelf: next, outcome: Unavailable(why: "the run could not be written"))
  end
  lost = at.now + asked.order.budget.wall_ms.to_i64.ms + grace()
  next.entries = shelf.entries.set(id, Entry(run: run, steps: 0, lost_at: lost))
  Change(shelf: next, outcome: Made(run: run))
end

# A client's run by id: none when it is another client's.
fn owned(shelf: Shelf, named: Named) : Option(Entry)
  entry = try shelf.entries.get(named.id)
  return None if entry.run.owner != named.owner
  Some(entry)
end

fn looked(ready: Readied, named: Named) : Outcome
  return unavailable(ready).outcome if !ready.opened
  case owned(ready.shelf, named)
    Some(entry): Found(run: entry.run)
    None: NoRun
  end
end

# A client's runs in a state, or in any, by id, at most 100.
fn listed(ready: Readied, owner: String, status: Option(Status)) : Outcome
  return unavailable(ready).outcome if !ready.opened
  mine = ready.shelf.entries.values.filter(fn(e)
    e.run.owner == owner and (status is None or status == Some(e.run.status))
  end)
  Listed(runs: mine.sort_by(fn(e) number_of(e.run.id) or 0 end).take(100).map(fn(e) e.run end))
end

fn transcribed(fs: Fs, runs: String, ready: Readied, named: Named, by: Deadline) : Outcome
  return unavailable(ready).outcome if !ready.opened
  return NoRun if owned(ready.shelf, named) is None
  case fs.scoped(runs).read_lines("#{named.id}.log", within: by)
    Ok(lines): Transcribed(steps: steps_of(lines))
    Error(_): Unavailable(why: "the transcript could not be read")
  end
end

# A client's running run cancelled, once its end is in its log; one already ended is left as it
# is.
fn cancelled(fs: Fs, runs: String, ready: Readied, named: Named, at: Moment) : Change
  return unavailable(ready) if !ready.opened
  shelf = ready.shelf
  case owned(shelf, named)
    Some(entry):
      return Change(shelf: shelf, outcome: NotRunning(run: entry.run)) if final?(entry.run.status)
      stop = Ended(id: named.id, ending: ending(Cancelled, None, None))
      settle = settled(fs, runs, shelf, stop, at)
      if settle.status != Cancelled
        return Change(shelf: shelf, outcome: Unavailable(why: "the cancel could not be written"))
      end
      Change(shelf: settle.shelf,
        outcome: Stopped(run: (settle.shelf.entries.get(named.id) or entry).run))
    None: Change(shelf: shelf, outcome: NoRun)
  end
end

# A step asked for by its run: one the log holds already is not written again, the next is
# written and then taken, and the answer says whether the run goes on.
fn put(fs: Fs, runs: String, ready: Readied, placed: Placed, at: Moment) : Put
  return Put(shelf: ready.shelf, verdict: Unrecorded) if !ready.opened
  case ready.shelf.entries.get(placed.id)
    Some(entry): stepped_in(fs, runs, ready.shelf, entry, placed, at)
    None: Put(shelf: ready.shelf, verdict: Stop(status: Failed))
  end
end

fn stepped_in(fs: Fs, runs: String, shelf: Shelf, entry: Entry, placed: Placed, at: Moment) : Put
  return Put(shelf: shelf, verdict: verdict_of(entry.run.status)) if placed.step.n <= entry.steps
  line = next_line(entry, placed.step, at.now)
  if fs.scoped(runs).append("#{placed.id}.log", line, within: at.by) is Error(_)
    return Put(shelf: shelf, verdict: Unrecorded)
  end
  written = Written(run: placed.id, log: log_of(runs, placed.id), n: placed.step.n,
    after: entry.steps)
  var after = entry
  after.steps = written.n
  after.run = counted(entry.run, placed.step, at.now)
  var next = shelf
  next.entries = shelf.entries.set(placed.id, after)
  Put(shelf: next, verdict: verdict_of(after.run.status))
end

# The step line that comes next in a run's log.
fn next_line(entry: Entry, step: Step, now: Time) : String
  requires step.n == entry.steps + 1

  step_line(now, step)
end

fn counted(run: Record, step: Step, now: Time) : Record
  var after = run
  after.updated_at = now
  return after if step.kind != "model"
  after.steps_taken = run.steps_taken + 1
  after.tokens_used = run.tokens_used + step.tokens
  after
end

fn finished(fs: Fs, runs: String, ready: Readied, ended: Ended, at: Moment) : Settled
  return Settled(shelf: ready.shelf, status: Running) if !ready.opened
  settled(fs, runs, ready.shelf, ended, at)
end

# The first end a run gets is its end, written to its log and then taken; a run already ended
# keeps its state, one whose end could not be written is still running, and a run the shelf does
# not hold is failed.
fn settled(fs: Fs, runs: String, shelf: Shelf, ended: Ended, at: Moment) : Settled
  case shelf.entries.get(ended.id)
    Some(entry):
      return Settled(shelf: shelf, status: entry.run.status) if final?(entry.run.status)
      e = ended.ending
      if fs.scoped(runs).append("#{ended.id}.log", end_line(at.now, e.status, e.answer, e.why),
        within: at.by) is Error(_)
        return Settled(shelf: shelf, status: Running)
      end
      var after = entry
      after.run = settled_run(entry.run, e, at.now)
      var next = shelf
      next.entries = shelf.entries.set(ended.id, after)
      Settled(shelf: next, status: e.status)
    None: Settled(shelf: shelf, status: Failed)
  end
end

# Every run still running past its wall budget and the grace after it, failed as lost.
fn swept(fs: Fs, runs: String, ready: Readied, at: Moment) : Swept
  return Swept(shelf: ready.shelf, lost: 0) if !ready.opened
  var shelf = ready.shelf
  var lost = 0
  for entry in ready.shelf.entries.values
    if entry.run.status == Running and at.now >= entry.lost_at
      gone = Ended(id: entry.run.id, ending: ending(Failed, None, Some("lost")))
      settle = settled(fs, runs, shelf, gone, at)
      shelf = settle.shelf
      lost += if settle.status == Failed
        1
      else
        0
      end
    end
  end
  Swept(shelf: shelf, lost: lost)
end

fn order_in(folder: String) : Order
  Order(goal: "count the notes", folder: folder, tools: ["now"], hosts: [],
    budget: default_budget())
end

fn step(n: UInt64, kind: String, tokens: UInt64) : Step
  Step(n: n, kind: kind, name: kind, args: Map.new(), output: "ok", tokens: tokens, took_ms: 1,
    refused: false)
end

fn made_on(fs: Fs, at: Moment) : Change
  ready = readied(fs, "runs", unready(), at)
  created(fs, "runs", ready, Asked(owner: "ada", order: order_in("work")), at)
end

# The shelf as a book that opened its logs holds it.
fn ready_on(shelf: Shelf) : Readied
  Readied(shelf: shelf, opened: true, why: "")
end

test "a run made, stepped, and ended is in its log in that order, and its record says so"
  fs = Fs.fixture()
  at = Moment(now: Time.fixture(), by: Deadline.fixture(1.minute))
  assert fs.mkdir("work", within: 1.minute) is Ok(_)
  change = made_on(fs, at)
  assert change.outcome is Made(run)
  assert run.id == "r_1" and run.status == Running
  first = put(fs, "runs", ready_on(change.shelf), Placed(id: "r_1", step: step(1, "model", 7)), at)
  assert first.verdict == Go
  again = put(fs, "runs", ready_on(first.shelf), Placed(id: "r_1", step: step(1, "model", 7)), at)
  assert again.verdict == Go and again.shelf == first.shelf
  second = put(fs, "runs", ready_on(first.shelf), Placed(id: "r_1", step: step(2, "tool", 0)), at)
  done = finished(fs, "runs", ready_on(second.shelf),
    Ended(id: "r_1", ending: ending(Done, Some("42"), None)), at)
  assert done.status == Done
  assert looked(ready_on(done.shelf), Named(owner: "ada", id: "r_1")) is Found(ended)
  assert ended.steps_taken == 1 and ended.tokens_used == 7 and ended.answer == Some("42")
  assert fs.read_lines("runs/r_1.log", within: 1.minute) is Ok(lines)
  assert lines.size == 4
  named = Named(owner: "ada", id: "r_1")
  assert transcribed(fs, "runs", ready_on(done.shelf), named,
    Deadline.fixture(1.minute)) is Transcribed(steps)
  assert steps.size == 2
  late = finished(fs, "runs", ready_on(done.shelf),
    Ended(id: "r_1", ending: ending(Failed, None, Some("x"))), at)
  assert late.status == Done and late.shelf == done.shelf
end

test "a client sees only its own runs, by id, and a folder that is not there is refused"
  fs = Fs.fixture()
  at = Moment(now: Time.fixture(), by: Deadline.fixture(1.minute))
  assert fs.mkdir("work", within: 1.minute) is Ok(_)
  change = made_on(fs, at)
  assert change.outcome is Made(_)
  ready = ready_on(change.shelf)
  assert looked(ready, Named(owner: "grace", id: "r_1")) == NoRun
  assert looked(ready, Named(owner: "ada", id: "r_9")) == NoRun
  assert listed(ready, "grace", None) == Listed(runs: [])
  assert listed(ready, "ada", Some(Running)) is Listed(runs)
  assert runs.size == 1
  assert listed(ready, "ada", Some(Done)) == Listed(runs: [])
  nowhere = created(fs, "runs", ready, Asked(owner: "ada", order: order_in("gone")), at)
  assert nowhere.outcome == NoFolder and nowhere.shelf == change.shelf
  assert transcribed(fs, "runs", ready, Named(owner: "grace", id: "r_1"),
    Deadline.fixture(1.minute)) == NoRun
end

test "a cancel is written once and stops the run at its next step, whose call is kept"
  fs = Fs.fixture()
  at = Moment(now: Time.fixture(), by: Deadline.fixture(1.minute))
  assert fs.mkdir("work", within: 1.minute) is Ok(_)
  change = made_on(fs, at)
  stop = cancelled(fs, "runs", ready_on(change.shelf), Named(owner: "ada", id: "r_1"), at)
  assert stop.outcome is Stopped(run)
  assert run.status == Cancelled
  assert cancelled(fs, "runs", ready_on(stop.shelf), Named(owner: "ada", id: "r_1"),
    at).outcome is NotRunning(_)
  assert cancelled(fs, "runs", ready_on(stop.shelf), Named(owner: "grace", id: "r_1"),
    at).outcome == NoRun
  flight = put(fs, "runs", ready_on(stop.shelf), Placed(id: "r_1", step: step(1, "model", 3)), at)
  assert flight.verdict == Stop(status: Cancelled)
  done = finished(fs, "runs", ready_on(flight.shelf),
    Ended(id: "r_1", ending: ending(Done, Some("x"), None)), at)
  assert done.status == Cancelled
  assert fs.read_lines("runs/r_1.log", within: 1.minute) is Ok(lines)
  assert lines.size == 3
end

test "logs opened again hold every run, and a run left running is failed as restarted"
  fs = Fs.fixture()
  at = Moment(now: Time.fixture(), by: Deadline.fixture(1.minute))
  assert fs.mkdir("work", within: 1.minute) is Ok(_)
  one = made_on(fs, at)
  two = created(fs, "runs", ready_on(one.shelf), Asked(owner: "ada", order: order_in("work")), at)
  stepped = put(fs, "runs", ready_on(two.shelf), Placed(id: "r_2", step: step(1, "model", 4)), at)
  done = finished(fs, "runs", ready_on(stepped.shelf),
    Ended(id: "r_1", ending: ending(Done, Some("42"), None)), at)
  assert done.status == Done
  again = readied(fs, "runs", unready(), at)
  assert again.opened and again.shelf.restarted == 1 and again.shelf.next == 3
  assert looked(again, Named(owner: "ada", id: "r_1")) is Found(first)
  assert first.status == Done and first.answer == Some("42")
  assert looked(again, Named(owner: "ada", id: "r_2")) is Found(second)
  assert second.status == Failed and second.why == Some("restarted") and second.steps_taken == 1
  assert transcribed(fs, "runs", again, Named(owner: "ada", id: "r_2"),
    Deadline.fixture(1.minute)) is Transcribed(steps)
  assert steps.size == 1
  third = readied(fs, "runs", unready(), at)
  assert third.shelf.restarted == 0 and third.shelf.entries == again.shelf.entries
end

test "a run past its wall budget and the grace after it is lost, and a book that cannot open says why"
  fs = Fs.fixture()
  at = Moment(now: Time.fixture(), by: Deadline.fixture(1.minute))
  assert fs.mkdir("work", within: 1.minute) is Ok(_)
  change = made_on(fs, at)
  ready = ready_on(change.shelf)
  early = swept(fs, "runs", ready, at)
  assert early.lost == 0
  late = Moment(now: Time.fixture() + 60_000.ms + grace(), by: Deadline.fixture(1.minute))
  gone = swept(fs, "runs", ready, late)
  assert gone.lost == 1
  assert looked(ready_on(gone.shelf), Named(owner: "ada", id: "r_1")) is Found(lost)
  assert lost.status == Failed and lost.why == Some("lost")
  slow = Moment(now: Time.fixture(), by: Deadline.fixture(100.ms))
  shut = readied(Fs.fixture(delay: 1.minute), "runs", unready(), slow)
  assert !shut.opened and opened_answer(shut) is Unready(_)
  assert looked(shut, Named(owner: "ada", id: "r_1")) is Unavailable(_)
  assert put(fs, "runs", shut, Placed(id: "r_1", step: step(1, "model", 1)),
    at).verdict == Unrecorded
end

test rejects "a step that skips the one before it"
  run = record("r_1", "ada", "g", Time.fixture())
  next_line(Entry(run: run, steps: 0, lost_at: Time.fixture()), step(2, "tool", 0), Time.fixture())
end

verified: types, contracts, tests (6), property (0 seeds), sim (not run)
          proven: not run
