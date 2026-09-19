module Agent.CodingFixture
expose Fixture, Fixtures, Config, Output, watched, fixture_deadline

use Agent.Book{Book}
use Agent.Client{Sleeper}
use Agent.CommandAdapter{Endpoint}
use Agent.Model{Model}
use Agent.Record{Order, Status, fixture_budget, fixture_tools}
use Agent.Registry{started_run}
use Agent.Report{report, reporting_error}
use Agent.Run{Run, report_grace_ms}
use Agent.Steps{Setup}

intent "An opt-in trusted disposable fixture starts the existing Book and Run, with operator-owned loopback addresses and one finite reporting deadline; command text is never executed locally."

struct Config
  dir: String
  model_port: UInt16
  command_port: UInt16
  workspace: String
  goal: String
end

struct Output
  text: String
  code: UInt8
end

process Fixture(fs: Fs, http: Http, clock: Clock)
  state
    calls: UInt64
  end

  message Start(config: Config) : Output

  fn update(state, message)
    case message
      Start(config):
        state.calls += 1
        started(fs, http, clock, config, reply_by)
    end
  end
end

supervisor Fixtures(fs: Fs, http: Http, clock: Clock)
  child Fixture(fs, http, clock), restart: :never
end

# The whole fixture's deadline, which the caller's ask gives it: the run's wall budget, the grace
# its recording and end keep past that, and 10 s for what lies outside both, opening the book and
# creating the run (2 s each) and the last looks at the record and the run and the ask for the
# report deadline (2 s each).
fn fixture_deadline() : Duration
  (fixture_budget().wall_ms.to_i64 + report_grace_ms() + 10_000).ms
end

fn failed(id: String, why: String) : Output
  Output(text: reporting_error(id, why), code: 3)
end

fn started(fs: Fs, http: Http, clock: Clock, config: Config, by: Deadline) : Output
  root = fs.scoped(config.dir)
  book = Book.start(root, clock, "runs", clock.now)
  if !(book.ask(Open, within: by.at_most(2_000.ms)) is Ok(Ready(runs: _, restarted: _)))
    return failed("", "book_open")
  end
  order = Order(goal: config.goal, folder: "work", tools: fixture_tools(), hosts: [],
    budget: fixture_budget())
  made = book.ask(Create(owner: "coding-fixture", order: order), within: by.at_most(2_000.ms))
  case made
    Ok(Made(record)):
      model = Model(host: "127.0.0.1", port: config.model_port, tools: fixture_tools())
      run = started_run(book, root, http, clock, Setup(id: record.id, order: order, model: model))
      endpoint = Endpoint(host: "127.0.0.1", port: config.command_port, workspace: config.workspace)
      if run.ask(ConfigureFixture(endpoint: endpoint), within: by) is Error(_)
        return failed(record.id, "fixture_setup")
      end
      if run.ask(Begin(me: run), within: by.at_most(order.budget.wall_ms.to_i64.ms)) is Error(_)
        return failed(record.id, "begin_unacknowledged")
      end
      watched(book, run, Sleeper.start(http), record.id, by)
    Ok(_) | Error(_): failed("", "create_failed")
  end
end

fn watched(book: Handle(Book), run: Handle(Run), sleeper: Handle(Sleeper), id: String,
  by: Deadline) : Output
  # Each look naps 20 ms, so the deadline, not the count, ends the watch.
  for _ in 0..(by.remaining.ms + 1)
    return failed(id, "report_deadline") if by.remaining == 0.ms
    case book.ask(Look(owner: "coding-fixture", id: id), within: by.at_most(2_000.ms))
      Ok(Found(record)):
        if record.status != Running and run.ask(Look, within: by.at_most(2_000.ms)) == Ok(Stopped)
          return final_report(book, run, id, record.status, by)
        end
      Ok(_) | Error(_):
        return failed(id, "record_unavailable")
    end
    if sleeper.ask(Nap(ms: 20), within: by.at_most(2_000.ms)) is Error(_)
      return failed(id, "sleeper")
    end
  end
  failed(id, "report_deadline")
end

fn final_report(book: Handle(Book), run: Handle(Run), id: String, status: Status,
  by: Deadline) : Output
  case run.ask(ReportDeadline, within: by.at_most(2_000.ms))
    Ok(report_by): finished(book, id, status, report_by)
    Error(_): failed(id, "report_deadline")
  end
end

fn finished(book: Handle(Book), id: String, status: Status, by: Deadline) : Output
  record = case book.ask(Look(owner: "coding-fixture", id: id), within: by)
    Ok(Found(record)): record
    Ok(_) | Error(_):
      return failed(id, "record_unavailable")
  end
  steps = case book.ask(Steps(owner: "coding-fixture", id: id), within: by)
    Ok(Transcribed(steps)): steps
    Ok(_) | Error(_):
      return failed(id, "transcript_unavailable")
  end
  case report(record, steps)
    Ok(text): Output(text: text, code: if status == Done: 0 else: 3)
    Error(why): failed(id, why)
  end
end

test "the fixture's deadline leaves room past the wall budget and the report grace for opening, creating and the report's reads"
  budget_ms = fixture_budget().wall_ms.to_i64 + report_grace_ms()
  # Opening the book and creating the run take up to 2 s each, and the last looks at the record
  # and the run and the ask for the report deadline up to 2 s each.
  assert fixture_deadline().ms - budget_ms >= 10_000
end

test "watching a run that never stops gives up only once its deadline is spent"
  fs = Fs.fixture()
  clock = Clock.fixture()
  http = Http.fixture()
  book = Book.start(fs, clock, "runs", clock.now)
  order = Order(goal: "g", folder: "work", tools: [], hosts: [], budget: fixture_budget())
  made = if fs.mkdir("work", within: 1.minute) is Ok(_)
    book.ask(Create(owner: "coding-fixture", order: order), within: 1.minute)
  else
    Error(Timeout)
  end
  if made is Ok(Made(record))
    model = Model(host: "127.0.0.1", port: 1, tools: fixture_tools())
    run = Run.start(book, fs.read_only, None, http, clock,
      Setup(id: record.id, order: order, model: model))
    by = Deadline.fixture(60_000.ms)
    output = watched(book, run, Sleeper.start(http), record.id, by)
    # A run never begun never stops; only faults may end the watch before the deadline.
    assert !output.text.contains?("report_deadline") or by.remaining == 0.ms
  end
end

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs)
          proven: not run
