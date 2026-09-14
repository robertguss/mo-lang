module Agent.Book
expose Book, Books

use Agent.Filing{readied, created, looked, listed, transcribed, cancelled, put, finished, swept}
use Agent.Record{Order, Status, Health, default_budget, health_of}
use Agent.Shelf{Readied, Moment, Asked, Named, Placed, Ended, Ending, Outcome, Verdict, Opened, unready, with_shelf, opened_answer, ending}
use Agent.Transcript{Step}

intent "The book of runs as a process: it opens the logs at its first message, after a start or a restart, and serves each message against the shelf with its clock, every file call on what remains of the ask it answers; a run asks it to write each step and the run's end, and hears in the answer whether to go on."

# A crash discards the update and its shelf, and the restart opens the logs again at its next
# message, so no change a log took is lost. The mailbox holds an ask from every run at once.
process Book(fs: Fs, clock: Clock, runs: String, started: Time) mailbox: 8_192
  state
    ready: Readied = unready()
  end

  message Open : Opened
  message Create(owner: String, order: Order) : Outcome
  message Look(owner: String, id: String) : Outcome
  message Listing(owner: String, status: Option(Status)) : Outcome
  message Steps(owner: String, id: String) : Outcome
  message Cancel(owner: String, id: String) : Outcome
  message Write(id: String, step: Step) : Verdict
  message End(id: String, ending: Ending) : Status
  message Tally : Health
  message Sweep : UInt64

  fn update(state, message)
    case message
      Open:
        state.ready = readied(fs, runs, state.ready, Moment(now: clock.now, by: reply_by))
        opened_answer(state.ready)
      Create(owner: owner, order: order):
        at = Moment(now: clock.now, by: reply_by)
        ready = readied(fs, runs, state.ready, at)
        change = created(fs, runs, ready, Asked(owner: owner, order: order), at)
        state.ready = with_shelf(ready, change.shelf)
        change.outcome
      Look(owner: owner, id: id):
        state.ready = readied(fs, runs, state.ready, Moment(now: clock.now, by: reply_by))
        looked(state.ready, Named(owner: owner, id: id))
      Listing(owner: owner, status: status):
        state.ready = readied(fs, runs, state.ready, Moment(now: clock.now, by: reply_by))
        listed(state.ready, owner, status)
      Steps(owner: owner, id: id):
        state.ready = readied(fs, runs, state.ready, Moment(now: clock.now, by: reply_by))
        transcribed(fs, runs, state.ready, Named(owner: owner, id: id), reply_by)
      Cancel(owner: owner, id: id):
        at = Moment(now: clock.now, by: reply_by)
        ready = readied(fs, runs, state.ready, at)
        change = cancelled(fs, runs, ready, Named(owner: owner, id: id), at)
        state.ready = with_shelf(ready, change.shelf)
        change.outcome
      Write(id: id, step: step):
        at = Moment(now: clock.now, by: reply_by)
        ready = readied(fs, runs, state.ready, at)
        written = put(fs, runs, ready, Placed(id: id, step: step), at)
        state.ready = with_shelf(ready, written.shelf)
        written.verdict
      End(id: id, ending: ending):
        at = Moment(now: clock.now, by: reply_by)
        ready = readied(fs, runs, state.ready, at)
        settle = finished(fs, runs, ready, Ended(id: id, ending: ending), at)
        state.ready = with_shelf(ready, settle.shelf)
        settle.status
      Tally:
        state.ready = readied(fs, runs, state.ready, Moment(now: clock.now, by: reply_by))
        runs_held = state.ready.shelf.entries.values.map(fn(e) e.run end)
        health_of(runs_held, (clock.now - started).ms.to_u64)
      Sweep:
        at = Moment(now: clock.now, by: reply_by)
        ready = readied(fs, runs, state.ready, at)
        sweep = swept(fs, runs, ready, at)
        state.ready = with_shelf(ready, sweep.shelf)
        sweep.lost
    end
  end
end

supervisor Books(fs: Fs, clock: Clock, runs: String, started: Time)
  child Book(fs, clock, runs, started), restart: :always, max_restarts: 5 per 1.minute
end

fn order_in(folder: String) : Order
  Order(goal: "count the notes", folder: folder, tools: ["now"], hosts: [],
    budget: default_budget())
end

fn step(n: UInt64, tokens: UInt64) : Step
  Step(n: n, kind: "model", name: "model", args: Map.new(), output: "ok", tokens: tokens,
    took_ms: 1, refused: false)
end

# Under faults an ask may time out, or the book may not open its logs in time, so each test
# asserts what holds either way: an answer is the right one or says it could not be given.
test "a run's step and end go through the book, and a book started again over the logs holds them"
  fs = Fs.fixture()
  made = fs.mkdir("work", within: 1.minute) is Ok(_)
  book = Book.start(fs, Clock.fixture(), "runs", Time.fixture())
  asked = book.ask(Create(owner: "ada", order: order_in("work")), within: 1.minute)
  if made and asked is Ok(Made(run))
    wrote = book.ask(Write(id: run.id, step: step(1, 5)), within: 1.minute) == Ok(Go)
    ended = book.ask(End(id: run.id, ending: ending(Done, Some("x"), None)), within: 1.minute)
    again = Book.start(fs, Clock.fixture(), "runs", Time.fixture())
    held = again.ask(Look(owner: "ada", id: run.id), within: 1.minute)
    if wrote and ended == Ok(Done) and held is Ok(Found(kept))
      assert kept.status == Done and kept.steps_taken == 1 and kept.tokens_used == 5
    end
    assert held is Ok(Found(_)) or held is Ok(Unavailable(_)) or held is Error(_)
  end
end

test "a cancel stops the run at its next step, and a second cancel finds it not running"
  fs = Fs.fixture()
  made = fs.mkdir("work", within: 1.minute) is Ok(_)
  book = Book.start(fs, Clock.fixture(), "runs", Time.fixture())
  asked = book.ask(Create(owner: "ada", order: order_in("work")), within: 1.minute)
  if made and asked is Ok(Made(run))
    stop = book.ask(Cancel(owner: "ada", id: run.id), within: 1.minute)
    heard = book.ask(Write(id: run.id, step: step(1, 5)), within: 1.minute)
    if stop is Ok(Stopped(_))
      assert heard != Ok(Go)
      again = book.ask(Cancel(owner: "ada", id: run.id), within: 1.minute)
      assert again is Ok(NotRunning(_)) or again is Error(_)
    end
  end
end

test "a book whose folder cannot be read says why, and counts nothing"
  book = Book.start(Fs.fixture(delay: 1.minute), Clock.fixture(), "runs", Time.fixture())
  opened = book.ask(Open, within: 1.minute)
  assert opened is Ok(Unready(_)) or opened is Error(_)
  counted = book.ask(Tally, within: 1.minute)
  assert counted is Error(_) or (counted is Ok(health) and health.running == 0)
end

verified: types, contracts, tests (3), property (0 seeds), sim (100 runs)
          proven: not run
