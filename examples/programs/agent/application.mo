module Agent.Application
expose Application, Applications, Launch, Output, owner, reserve_ms, poll_ms, margin_ms, report_cap, application_order, profile, loaded, preflight, made, failed

use Agent.Book{Book}
use Agent.Model{Model}
use Agent.Record{Order, Status, budget, fixture_tools}
use Agent.Report{application_report, application_error}
use Agent.Run{Run}
use Agent.Steps{Setup}
use Agent.WorkspaceAdapter{Settings, settings, config_cap, file_ms, command_ms, candidate_ms, candidate_floor_ms, request_cap, response_cap, wire_version}

intent "One operator-launched application run: a private bridge configuration read within its bound, a fresh operator-owned Book root bound to the bridge's external run, Run started with no local writer and every tool routed to the workspace bridge, all inside one outer deadline that keeps the report's reserve; the start's reply is kept and answered once, by delayed self-polls, when the Book is terminal and Run has stopped, or with a versioned reporting error."

# What the operator gives: the fresh root holding work/, the scripted model's loopback port, the
# private bridge configuration's path, and the goal. No capability is ever part of it.
struct Launch
  version: String
  dir: String
  model_port: UInt16
  config: String
  goal: String
end

struct Output
  text: String
  code: UInt8
end

fn owner() : String
  "application-workspace"
end

# The report's reserve inside the outer deadline; work gets the rest.
fn reserve_ms() : Int64
  15_000
end

fn poll_ms() : Int64
  20
end

# Time kept at the end of the outer deadline so a reporting error can still reach the asker.
fn margin_ms() : Int64
  500
end

# The most bytes a model reply can be: the runtime's HTTP body limit, past which a reply is
# TooLarge and never becomes a step.
fn model_reply_cap() : UInt64
  1_048_576
end

# The most transcript bytes a report renders: every step the budget allows carrying a whole
# request and a whole response, and a whole model reply besides. A run of this profile stays far
# below it, since the context bound ends a run at its first model request over 64 KiB, so a
# larger transcript is not one this profile made and is a reporting error, not a report.
fn report_cap() : UInt64
  application_order("").budget.steps * (request_cap() + response_cap()) + model_reply_cap()
end

fn application_order(goal: String) : Order
  Order(goal: goal, folder: "work", tools: fixture_tools(), hosts: [],
    budget: budget(16, 4_096, 900_000, 0, 2_000))
end

# The fixed caps the legacy log header cannot show, as the report's first line.
fn profile() : String
  caps = "\"steps\": 16, \"tokens\": 4096, \"wall_ms\": 900000, \"retries\": 0, \"tool_ms\": 2000, \"grants\": #{Json.encode(fixture_tools())}"
  waits = "\"report_reserve_ms\": #{reserve_ms()}, \"model_wait_ms\": 2000, \"file_wait_ms\": #{file_ms()}, \"command_wait_ms\": #{command_ms()}, \"candidate_ms\": #{candidate_ms()}, \"candidate_floor_ms\": #{candidate_floor_ms()}"
  bounds = "\"request_bytes\": #{request_cap()}, \"response_bytes\": #{response_cap()}, \"config_bytes\": #{config_cap()}, \"report_bytes\": #{report_cap()}, \"wire\": #{Json.encode(wire_version())}"
  "{#{caps}, #{waits}, #{bounds}}"
end

fn failed(id: String, why: String) : Output
  Output(text: application_error(id, why, "proved"), code: 3)
end

fn uncertain(id: String, why: String) : Output
  Output(text: application_error(id, why, "uncertain"), code: 3)
end

process Application(fs: Fs, http: Http, clock: Clock)
  state
    waiting: List(Reply(Output))
    started: Bool
    outer: Option(Deadline)
    book: Option(Handle(Book))
    run: Option(Handle(Run))
    id: String
    polls: UInt64
    answers: UInt64
  end

  invariant "a launch is answered at most once"
    state.answers <= 1
  end

  message Launched(launch: Launch, me: Handle(Application)) : Output
  message Watched(book: Handle(Book), run: Handle(Run), id: String,
    me: Handle(Application)) : Output
  message Watching(book: Handle(Book), run: Handle(Run), id: String, me: Handle(Application))
  message Poll(me: Handle(Application))
  message Polls : UInt64
  message Answers : UInt64

  fn update(state, message)
    case message
      # The asker is kept whatever happens next; a start that fails answers it at once.
      Launched(launch: launch, me: me):
        state.waiting = state.waiting.push(reply_to)
        first = !state.started
        state.started = true
        if first
          state.outer = Some(reply_by)
        end
        startup = if first
          launched(fs, http, clock, launch, reply_by, me)
        else
          Some(failed("", "already_started"))
        end
        # One launch per process: a later one is answered alone, and the first keeps its watch.
        if startup is Some(output)
          if state.waiting.last is Some(held)
            held.answer(output)
          end
          state.waiting = state.waiting.take(state.waiting.size - 1)
          state.answers += if first: 1 else: 0
        end
      # An operator's own Book and Run, watched to their end on the asker's deadline.
      Watched(book: book, run: run, id: id, me: me):
        state.waiting = state.waiting.push(reply_to)
        if state.started
          if state.waiting.last is Some(late)
            late.answer(failed(id, "already_started"))
          end
          state.waiting = state.waiting.take(state.waiting.size - 1)
        else
          state.started = true
          state.outer = Some(reply_by)
          me.send(Watching(book: book, run: run, id: id, me: me))
        end
      Watching(book: book, run: run, id: id, me: me):
        state.book = Some(book)
        state.run = Some(run)
        state.id = id
        me.send(Poll(me: me))
      Poll(me):
        state.polls += 1
        found = watched(state.book, state.run, state.id, state.outer)
        if found is Some(output)
          for held in state.waiting
            held.answer(output)
          end
          state.answers += if state.waiting.size > 0: 1 else: 0
          state.waiting = []
          state.book = None
          state.run = None
        else
          me.send(Poll(me: me), delay: poll_ms().ms)
        end
      Polls: state.polls
      Answers: state.answers
    end
  end
end

supervisor Applications(fs: Fs, http: Http, clock: Clock)
  child Application(fs, http, clock), restart: :never
end

# Every startup check in order; on success the watch begins and nothing is answered yet.
fn launched(fs: Fs, http: Http, clock: Clock, launch: Launch, outer: Deadline,
  me: Handle(Application)) : Option(Output)
  return Some(failed("", "launch_version")) if launch.version != "mo-application-workspace-v1"
  bound = case loaded(fs.read_only, launch.config, outer)
    Ok(found): found
    Error(why):
      return Some(failed("", why))
  end
  return Some(failed("", "goal_capability")) if launch.goal.contains?(bound.token)
  root = fs.scoped(launch.dir)
  refused = preflight(root, outer)
  return Some(failed("", refused or "")) if refused is Some(_)
  book = Book.start(root, clock, "runs", clock.now)
  if book.ask(Open, within: outer.at_most(2_000.ms)) != Ok(Ready(runs: 0, restarted: 0))
    return Some(failed("", "book_open"))
  end
  order = application_order(launch.goal)
  id = case made(book, order, bound, outer)
    Ok(found): found
    Error(why):
      return Some(failed("", why))
  end
  model = Model(host: "127.0.0.1", port: launch.model_port, tools: fixture_tools())
  run = Run.start(book, root.scoped("work").read_only, None, http, clock,
    Setup(id: id, order: order, model: model))
  if run.ask(ConfigureApplication(settings: bound), within: outer) != Ok(true)
    return Some(failed(id, "application_setup"))
  end
  work = outer.remaining.ms - reserve_ms()
  return Some(failed(id, "work_deadline")) if work <= 0
  if run.ask(Begin(me: run), within: outer.at_most(work.ms)) is Error(_)
    return Some(failed(id, "begin_unacknowledged"))
  end
  me.send(Watching(book: book, run: run, id: id, me: me))
  None
end

# The bridge configuration: its size checked before it is read, and its text again after.
fn loaded(fs: Fs, path: String, by: Deadline) : Result(Settings, String)
  size = case fs.size(path, within: by.at_most(2_000.ms))
    Ok(n): n
    Error(_):
      return Error("config_unreadable")
  end
  return Error("config_size") if size > config_cap()
  text = case fs.read(path, within: by.at_most(2_000.ms))
    Ok(found): found
    Error(_):
      return Error("config_unreadable")
  end
  settings(text)
end

# A fresh root: its work/ placeholder there, and nothing at all in its runs folder, since an
# empty, cut short or unrecognized log still moves the Book's ids or its restart records.
fn preflight(root: Fs, by: Deadline) : Option(String)
  return Some("work_missing") if root.scoped("work").list(within: by.at_most(2_000.ms)) is Error(_)
  case root.scoped("runs").list(within: by.at_most(2_000.ms))
    Ok(names): if names.size == 0: None else: Some("root_not_fresh")
    Error(Missing(_)): None
    Error(Timeout) | Error(NotText): Some("root_unreadable")
  end
end

# The Book makes the run and chooses its id, which must be the bridge's external run.
fn made(book: Handle(Book), order: Order, bound: Settings, by: Deadline) : Result(String, String)
  case book.ask(Create(owner: owner(), order: order), within: by.at_most(2_000.ms))
    Ok(Made(record)):
      return Error("run_binding") if record.id != bound.run
      Ok(record.id)
    Ok(_) | Error(_): Error("create_failed")
  end
end

# The watch in hand, or none: a watch whose handles are gone has ended.
fn watched(book: Option(Handle(Book)), run: Option(Handle(Run)), id: String,
  outer: Option(Deadline)) : Option(Output)
  case book
    Some(b):
      case run
        Some(r):
          case outer
            Some(by): polled(b, r, id, by)
            None: Some(failed(id, "watch_unavailable"))
          end
        None: Some(failed(id, "watch_unavailable"))
      end
    None: Some(failed(id, "watch_unavailable"))
  end
end

# One look: nothing yet while Run has not stopped (a Run in a long command does not answer in
# time, which is not an end); once it has, the Book's record and transcript on the allowance
# Run gives from the outer deadline.
fn polled(book: Handle(Book), run: Handle(Run), id: String, outer: Deadline) : Option(Output)
  return Some(failed(id, "report_deadline")) if outer.remaining.ms <= margin_ms()
  case run.ask(Look, within: outer.at_most(file_ms().ms))
    Ok(Stopped): Some(reported(book, run, id, outer))
    Ok(_) | Error(Timeout): None
    Error(Down): Some(uncertain(id, "run_down"))
  end
end

fn reported(book: Handle(Book), run: Handle(Run), id: String, outer: Deadline) : Output
  by = case run.ask(ReportDeadline, within: outer)
    Ok(found): found
    Error(_):
      return uncertain(id, "report_deadline")
  end
  record = case book.ask(Look(owner: owner(), id: id), within: by)
    Ok(Found(found)): found
    Ok(_) | Error(_):
      return uncertain(id, "record_unavailable")
  end
  # Run stopped with the Book still running: its end was not written, and nothing is invented.
  return uncertain(id, "book_unsettled") if record.status == Running
  return uncertain(id, "recording_failure") if record.why == Some("recording_failure")
  steps = case book.ask(Steps(owner: owner(), id: id), within: by)
    Ok(Transcribed(found)): found
    Ok(_) | Error(_):
      return uncertain(id, "transcript_unavailable")
  end
  if steps.reduce(0.to_u64, fn(n, step) n + step.byte_size end) > report_cap()
    return failed(id, "transcript_too_large")
  end
  case application_report(record, steps, profile())
    Ok(text): Output(text: text, code: if record.status == Done: 0 else: 3)
    Error(why): uncertain(id, why)
  end
end

verified: types, contracts, tests (0), property (0 seeds), sim (not run)
          proven: not run
