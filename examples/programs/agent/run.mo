module Agent.Run
expose Run, Runs, began?, report_grace_ms

use Agent.Book{Book}
use Agent.CommandAdapter{Endpoint, dispatched, terminal?, refused?, failure}
use Agent.Model{Model, complete, body}
use Agent.Record{Order, Status, default_budget}
use Agent.Shelf{Verdict, Ending, ending}
use Agent.Steps{Setup, Phase, Counting, Progress, fresh, begun, asked, using, stopped, advanced, asks?, uses?, budget_end, not_begun, request_of, call_ms, ran_of, call_for, model_step, tool_step, model_outcome}
use Agent.Tools{Writer, Used, Call, used}
use Agent.Transcript{Step}
use Agent.WorkspaceAdapter{Settings, sent, stops?, refusal?, tools}

intent "A run as a process: its budget's deadline taken from the ask that begins it, then a loop of messages it sends itself (a model call, its step written, the tool the model named, that step written), every call on what remains of the deadline tightened by tool_ms; each step is in the book before the next call, the book's answer says whether the run goes on, and the run ends by asking the book to write its end."

# A run's reads go through its folder read-only; a run granted write_file also holds a writer, the
# process that holds the folder writable, and a run not granted it holds none (step 25). A crash ends the run where it is; the
# book fails it as lost once its wall budget and grace have passed.
struct Turn
  setup: Setup
  run: Progress
  counting: Counting
  fixture: Option(Endpoint)
  application: Option(Settings)
end

# How a profiled step is recorded: on what is left of the report allowance, and judged by the
# application adapter or by the fixture's rule.
struct Recording
  by: Option(Deadline)
  application: Bool
end

struct Identity
  run: String
  call: String
end

process Run(book: Handle(Book), reads: Fs, writer: Option(Handle(Writer)), http: Http, clock: Clock,
  setup: Setup)
  state
    run: Progress = fresh(setup.id)
    fixture: Option(Endpoint)
    application: Option(Settings)
    report_by: Option(Deadline)
    grace_ms: Int64 = report_grace_ms()
    counting: Counting = ModelCalls
  end

  invariant "a run's deadline is taken once"
    old(state.run.by) is None or state.run.by == old(state.run.by)
  end

  invariant "a stopped run stays stopped"
    old(state.run.phase) != Stopped or state.run.phase == Stopped
  end

  message ConfigureFixture(endpoint: Endpoint) : Bool
  message ConfigureApplication(settings: Settings) : Bool
  message Begin(me: Handle(Run)) : Bool
  message Think(me: Handle(Run))
  message Thought(me: Handle(Run))
  message Act(me: Handle(Run))
  message Acted(me: Handle(Run))
  message Close(me: Handle(Run))
  message Look : Phase
  message ReportDeadline : Deadline

  fn update(state, message)
    case message
      ConfigureFixture(endpoint):
        if state.run.phase == Ready and state.fixture is None and state.application is None
          state.fixture = Some(endpoint)
          state.report_by = Some(reply_by)
          state.counting = RecordedSteps
          true
        else
          false
        end
      # Application mode, once and only while Ready: the asker's deadline is the whole run's,
      # from which recording and the report keep their allowance.
      ConfigureApplication(settings):
        if state.run.phase == Ready and state.fixture is None and state.application is None
          state.application = Some(settings)
          state.report_by = Some(reply_by)
          state.counting = RecordedSteps
          true
        else
          false
        end
      Begin(me):
        state.run = begun(state.run, reply_by)
        me.send(Think(me: me))
        true
      Think(me):
        state.run = thinking(me, http, clock,
          Turn(setup: setup, run: state.run, counting: state.counting, fixture: state.fixture,
          application: state.application))
      Thought(me):
        remaining = remaining_ms(state.report_by)
        began = clock.now
        state.run = recorded_profile(me, book, setup, state.run, model_step(state.run, began),
          Recording(by: capped(state.report_by, state.grace_ms),
          application: state.application is Some(_)))
        state.grace_ms = grace_left(state.grace_ms, remaining, remaining_ms(state.report_by))
      Act(me):
        state.run = acting(me, reads, writer, http, clock,
          Turn(setup: setup, run: state.run, counting: state.counting, fixture: state.fixture,
          application: state.application))
      Acted(me):
        remaining = remaining_ms(state.report_by)
        began = clock.now
        state.run = recorded_profile(me, book, setup, state.run, tool_step(state.run, began),
          Recording(by: capped(state.report_by, state.grace_ms),
          application: state.application is Some(_)))
        state.grace_ms = grace_left(state.grace_ms, remaining, remaining_ms(state.report_by))
      Close(me):
        remaining = remaining_ms(state.report_by)
        state.run = case state.report_by
          Some(by):
            case book.ask(End(id: setup.id, ending: state.run.ending or not_begun()),
              within: by.at_most(state.grace_ms.ms))
              Ok(_) | Error(_): stopped(state.run)
            end
          None: closed(me, book, setup, state.run)
        end
        state.grace_ms = grace_left(state.grace_ms, remaining, remaining_ms(state.report_by))
      Look: state.run.phase
      ReportDeadline: reply_by.at_most(state.grace_ms.ms)
    end
  end
end

# What a profiled run keeps past its wall budget for recording its steps and its end.
fn report_grace_ms() : Int64
  15_000
end

fn capped(by: Option(Deadline), ms: Int64) : Option(Deadline)
  case by
    Some(deadline): Some(deadline.at_most(ms.ms))
    None: None
  end
end

fn remaining_ms(by: Option(Deadline)) : Int64
  case by
    Some(deadline): deadline.remaining.ms
    None: 0
  end
end

fn grace_left(ms: Int64, before: Int64, after: Int64) : Int64
  spent = if before > after: before - after else: 0
  if spent >= ms: 0 else: ms - spent
end

fn thinking(me: Handle(Run), http: Http, clock: Clock, turn: Turn) : Progress
  setup = turn.setup
  run = turn.run
  profiled = turn.fixture is Some(_) or turn.application is Some(_)
  by = case run.by
    Some(by): by
    None:
      return closing(me, run, not_begun())
  end
  if profiled and body(request_of(setup, run)).byte_size > 65_536
    return closing(me, run, ending(OverBudget, None, Some("context_bytes")))
  end
  return held(me, run, setup, by, turn.counting) if !asks?(run, setup, by, turn.counting)
  began = clock.now
  reply = complete(http, setup.model, request_of(setup, run), setup.order.budget.retries,
    by.at_most(call_ms(setup)))
  next = asked(run, reply, if profiled: began else: clock.now)
  me.send(Thought(me: me))
  next
end

fn acting(me: Handle(Run), reads: Fs, writer: Option(Handle(Writer)), http: Http, clock: Clock,
  turn: Turn) : Progress
  setup = turn.setup
  run = turn.run
  fixture = turn.fixture
  profiled = fixture is Some(_) or turn.application is Some(_)
  by = case run.by
    Some(by): by
    None:
      return closing(me, run, not_begun())
  end
  return held(me, run, setup, by, turn.counting) if !uses?(run, setup, by, turn.counting)
  call = call_for(setup, run, ran_of(run, setup, by))
  began = clock.now
  tool = case turn.application
    Some(settings): remote(http, settings, call, "#{run.n + 1}", by)
    None:
      case fixture
        Some(endpoint):
          if call.tool == "command" or call.tool == "exact_edit"
            fixture_used(writer, http, call, endpoint,
              Identity(run: setup.id, call: "#{run.n + 1}"), by.at_most(call_ms(setup)))
          else
            used(reads, writer, http, clock, call, by.at_most(call_ms(setup)))
          end
        None: used(reads, writer, http, clock, call, by.at_most(call_ms(setup)))
      end
  end
  next = using(run, tool, if profiled: began else: clock.now)
  me.send(Acted(me: me))
  next
end

# Fixture recording is sent once. A failed acknowledgement stops dispatch and requests
# a recorded failure, without replaying the uncertain step or its effect. In application mode
# every tool's recorded outcome is judged by the adapter's field-based decision.
fn recorded_profile(me: Handle(Run), book: Handle(Book), setup: Setup, run: Progress, step: Step,
  recording: Recording) : Progress
  case recording.by
    None: recorded(me, book, setup, run, step)
    Some(by):
      return run if run.phase != Recording
      case book.ask(Write(id: setup.id, step: step), within: by)
        Ok(Go):
          next = advanced(run, step)
          stops = if recording.application
            step.kind == "tool" and stops?(step.output)
          else
            step.kind == "tool" and (step.name == "command" or step.name == "exact_edit") and terminal?(step.output)
          end
          if stops
            return closing(me, next, ending(Failed, None, Some("uncertain_or_terminal_tool")))
          end
          went_on(me, next, setup, step)
        Ok(Stop(_)): stopped(run)
        Ok(Unrecorded) | Error(_): closing(me, run, ending(Failed, None, Some("recording_failure")))
      end
  end
end

fn fixture_used(writer: Option(Handle(Writer)), http: Http, call: Call, endpoint: Endpoint,
  id: Identity, by: Deadline) : Used
  if !call.granted.contains?(call.tool)
    return Used(output: failure("refusal", "grant", "not_started"), refused: true, allowed: false)
  end
  if call.tool == "command" and !call.args.has?("command")
    return Used(output: failure("refusal", "arguments", "not_started"), refused: true,
      allowed: false)
  end
  output = if call.tool == "command"
    dispatched(http, endpoint, id.run, id.call, call.args.get("command") or "", by)
  else
    edit_handed(writer, call, by)
  end
  Used(output: output, refused: refused?(output), allowed: true)
end

# Application mode: every tool goes to the workspace bridge and never to a local tool. The next
# Book step number names the call; the model's arguments are recorded unchanged.
fn remote(http: Http, settings: Settings, call: Call, id: String, by: Deadline) : Used
  output = sent(http, settings, call, id, by)
  Used(output: output, refused: refusal?(output),
    allowed: call.granted.contains?(call.tool) and tools().contains?(call.tool))
end

fn edit_handed(writer: Option(Handle(Writer)), call: Call, by: Deadline) : String
  if !call.args.has?("path") or !call.args.has?("old_text") or !call.args.has?("new_text")
    return failure("refusal", "arguments", "not_started")
  end
  case writer
    Some(w):
      case w.ask(ExactEdit(path: call.args.get("path") or "",
        old_text: call.args.get("old_text") or "", new_text: call.args.get("new_text") or ""),
        within: by)
        Ok(output): output
        Error(_): failure("timeout", "write_timeout", "unknown")
      end
    None: failure("refusal", "grant", "not_started")
  end
end

supervisor Runs(book: Handle(Book), reads: Fs, writer: Option(Handle(Writer)), http: Http,
  clock: Clock, setup: Setup)
  child Run(book, reads, writer, http, clock, setup), restart: :never
end

# A run in its turn that may not go on ends over the budget it spent; a message out of turn
# changes nothing.
fn held(me: Handle(Run), run: Progress, setup: Setup, by: Deadline, counting: Counting) : Progress
  return run if run.phase != Asking and run.phase != Using
  closing(me, run, budget_end(run, setup, by, counting))
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
  run = Run.start(book, fs.read_only, None, Http.fixture(), Clock.fixture(), setup_nowhere())
  assert [began?(run, 1.minute), began?(run, 2.minute)].size == 2
end

test rejects "a run begun again once it has stopped"
  fs = Fs.fixture()
  book = Book.start(fs, Clock.fixture(), "runs", Time.fixture())
  run = Run.start(book, fs.read_only, None, Http.fixture(), Clock.fixture(), setup_nowhere())
  run.send(Think(me: run))
  for _ in 0..200
    if run.ask(Look, within: 1.minute) == Ok(Stopped)
      break
    end
  end
  assert [began?(run, 1.minute)].size == 1
end

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs, invariants (kept 2, tripped 2))
          proven: not run
