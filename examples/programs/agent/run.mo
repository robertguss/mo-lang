module Agent.Run
expose Run, Runs, began?

use Agent.Book{Book}
use Agent.Model{Model, complete}
use Agent.Record{Order, Status, default_budget}
use Agent.Shelf{Verdict, Ending}
use Agent.Steps{Setup, Phase, Progress, fresh, begun, asked, using, stopped, advanced, asks?, uses?, budget_end, not_begun, request_of, call_ms, ran_of, call_for, model_step, tool_step, model_outcome}
use Agent.Tools{used}
use Agent.Transcript{Step}

intent "A run as a process: its budget's deadline taken from the ask that begins it, then a loop of messages it sends itself (a model call, its step written, the tool the model named, that step written), every call on what remains of the deadline tightened by tool_ms; each step is in the book before the next call, the book's answer says whether the run goes on, and the run ends by asking the book to write its end."

# A run's reads go through its folder read-only, and its writes through the same folder, writable
# only when the run was granted write_file. A crash ends the run where it is; the book fails it as
# lost once its wall budget and grace have passed.
process Run(book: Handle(Book), reads: Fs, writes: Fs, http: Http, clock: Clock, setup: Setup)
  state
    run: Progress = fresh(setup.id)
  end

  invariant "a run's deadline is taken once"
    old(state.run.by) is None or state.run.by == old(state.run.by)
  end

  invariant "a stopped run stays stopped"
    old(state.run.phase) != Stopped or state.run.phase == Stopped
  end

  message Begin(me: Handle(Run)) : Bool
  message Think(me: Handle(Run))
  message Thought(me: Handle(Run))
  message Act(me: Handle(Run))
  message Acted(me: Handle(Run))
  message Close(me: Handle(Run))
  message Look : Phase

  fn update(state, message)
    case message
      Begin(me):
        state.run = begun(state.run, reply_by)
        me.send(Think(me: me))
        true
      Think(me):
        case state.run.by
          Some(by):
            if asks?(state.run, setup, by)
              reply = complete(http, setup.model, request_of(setup, state.run),
                setup.order.budget.retries, by.at_most(call_ms(setup)))
              state.run = asked(state.run, reply, clock.now)
              me.send(Thought(me: me))
            else
              state.run = held(me, state.run, setup, by)
            end
          None:
            state.run = closing(me, state.run, not_begun())
        end
      Thought(me):
        state.run = recorded(me, book, setup, state.run, model_step(state.run, clock.now))
      Act(me):
        case state.run.by
          Some(by):
            if uses?(state.run, setup, by)
              call = call_for(setup, state.run, ran_of(state.run, setup, by))
              tool = used(reads, writes, http, clock, call, by.at_most(call_ms(setup)))
              state.run = using(state.run, tool, clock.now)
              me.send(Acted(me: me))
            else
              state.run = held(me, state.run, setup, by)
            end
          None:
            state.run = closing(me, state.run, not_begun())
        end
      Acted(me):
        state.run = recorded(me, book, setup, state.run, tool_step(state.run, clock.now))
      Close(me):
        state.run = closed(me, book, setup, state.run)
      Look: state.run.phase
    end
  end
end

supervisor Runs(book: Handle(Book), reads: Fs, writes: Fs, http: Http, clock: Clock, setup: Setup)
  child Run(book, reads, writes, http, clock, setup), restart: :never
end

# A run in its turn that may not go on ends over the budget it spent; a message out of turn
# changes nothing.
fn held(me: Handle(Run), run: Progress, setup: Setup, by: Deadline) : Progress
  return run if run.phase != Asking and run.phase != Using
  closing(me, run, budget_end(run, setup, by))
end

# A run on its way to its end: the end kept until the book has written it.
fn closing(me: Handle(Run), run: Progress, ending: Ending) : Progress
  return run if run.phase == Stopped or run.phase == Closing
  var next = run
  next.ending = Some(ending)
  next.phase = Closing
  next.missed = 0
  me.send(Close(me: me))
  next
end

# The step in hand written by the book before anything else happens: on its go the run goes on,
# on a stop it stops, and when the book did not write it the run asks again, at most ten times in
# a row.
fn recorded(me: Handle(Run), book: Handle(Book), setup: Setup, run: Progress, step: Step) : Progress
  return run if run.phase != Recording
  var held_step = run
  held_step.step = Some(step)
  case book.ask(Write(id: setup.id, step: step), within: 10_000.ms)
    Ok(Go): went_on(me, advanced(held_step, step), setup, step)
    Ok(Stop(_)): stopped(held_step)
    Ok(Unrecorded) | Error(_): again(me, held_step, step)
  end
end

# After a tool step the run asks the model again; after a model step it ends, or uses the tool.
fn went_on(me: Handle(Run), run: Progress, setup: Setup, step: Step) : Progress
  var next = run
  if step.kind == "tool"
    next.phase = Asking
    me.send(Think(me: me))
    return next
  end
  case model_outcome(run, setup)
    Some(ending): closing(me, run, ending)
    None:
      next.phase = Using
      me.send(Act(me: me))
      next
  end
end

fn again(me: Handle(Run), run: Progress, step: Step) : Progress
  var next = run
  next.missed = run.missed + 1
  return stopped(next) if next.missed > 10
  if step.kind == "model"
    me.send(Thought(me: me))
  else
    me.send(Acted(me: me))
  end
  next
end

# The end in hand written by the book; a run whose end the book did not write asks again, at
# most ten times in a row, and the book's answer is the run's state from then on.
fn closed(me: Handle(Run), book: Handle(Book), setup: Setup, run: Progress) : Progress
  return run if run.phase != Closing
  case book.ask(End(id: setup.id, ending: run.ending or not_begun()), within: 10_000.ms)
    Ok(Running) | Error(_):
      var next = run
      next.missed = run.missed + 1
      return stopped(next) if next.missed > 10
      me.send(Close(me: me))
      next
    Ok(Done) | Ok(Failed) | Ok(OverBudget) | Ok(Cancelled): stopped(run)
  end
end

# Whether an ask to begin the run was answered.
fn began?(run: Handle(Run), wait: Duration) : Bool
  run.ask(Begin(me: run), within: wait) is Ok(_)
end

fn setup_nowhere() : Setup
  order = Order(goal: "g", folder: "work", tools: [], hosts: [], budget: default_budget())
  Setup(id: "r_9", order: order, model: Model(host: "localhost", port: 1, tools: []))
end

test rejects "a run begun twice"
  fs = Fs.fixture()
  book = Book.start(fs, Clock.fixture(), "runs", Time.fixture())
  run = Run.start(book, fs.read_only, fs.read_only, Http.fixture(), Clock.fixture(),
    setup_nowhere())
  assert [began?(run, 1.minute), began?(run, 2.minute)].size == 2
end

test rejects "a run begun again once it has stopped"
  fs = Fs.fixture()
  book = Book.start(fs, Clock.fixture(), "runs", Time.fixture())
  run = Run.start(book, fs.read_only, fs.read_only, Http.fixture(), Clock.fixture(),
    setup_nowhere())
  run.send(Think(me: run))
  for _ in 0..200
    if run.ask(Look, within: 1.minute) == Ok(Stopped)
      break
    end
  end
  assert [began?(run, 1.minute)].size == 1
end

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs)
          proven: not run
