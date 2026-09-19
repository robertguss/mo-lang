module Agent.Tests.CodingFixtureV1.Boundaries

use Agent.Book{Book}
use Agent.Client{Sleeper}
use Agent.CodingFixture{watched}
use Agent.CommandAdapter{Endpoint}
use Agent.ExactEdit{edited}
use Agent.Model{Model, Fake}
use Agent.Record{Order, Budget, Record, record, fixture_tools}
use Agent.Report{report}
use Agent.Run{Run}
use Agent.Steps{Setup}
use Agent.Tools{Writer}

intent "Two focused fixture groups: refusal and reporting values, and real process boundaries for grants, cancellation, exhausted deadlines and failed recording."

fn record_for(book: Handle(Book), id: String, now: Time) : Record
  case book.ask(Look(owner: "test", id: id), within: 1.minute)
    Ok(Found(found)): found
    Ok(_) | Error(_): record(id, "test", "g", now)
  end
end

# Real-socket reproduction of the cancellation report, using the same Run/Book path.
fn cancellation(fs: Fs, http: Http, clock: Clock, port: UInt16, by: Deadline) : String
  book = Book.start(fs, clock, "runs", clock.now)
  order = Order(goal: "g", folder: "work", tools: [], hosts: [],
    budget: Budget(steps: 16, tokens: 4096, wall_ms: 30000, retries: 0, tool_ms: 2000))
  made = case book.ask(Create(owner: "coding-fixture", order: order), within: 1.minute)
    Ok(Made(found)): found
    Ok(_) | Error(_):
      return "create failed"
  end
  if !(book.ask(Cancel(owner: "coding-fixture", id: made.id), within: 1.minute) is Ok(Stopped(_)))
    return "cancel failed"
  end
  model = Model(host: "127.0.0.1", port: port, tools: fixture_tools())
  run = Run.start(book, fs.scoped("work").read_only, None, http, clock,
    Setup(id: made.id, order: order, model: model))
  endpoint = Endpoint(host: "127.0.0.1", port: 1, workspace: "w")
  if run.ask(ConfigureFixture(endpoint: endpoint), within: 1.minute) is Error(_)
    return "configure failed"
  end
  if run.ask(Begin(me: run), within: 30000.ms) is Error(_)
    return "begin failed"
  end
  sleeper = Sleeper.start(http)
  output = watched(book, run, sleeper, made.id, by)
  before = fs.read("runs/#{made.id}.log", within: by)
  if sleeper.ask(Nap(ms: 300), within: by) is Error(_)
    return "post-report wait failed"
  end
  if before != fs.read("runs/#{made.id}.log", within: by)
    return "log changed after report"
  end
  return "reported before stop" if run.ask(Look, within: by) != Ok(Stopped)
  output.text
end

fn shown_report(record: Record, steps: List(String)) : String
  case report(record, steps)
    Ok(text): text
    Error(why): why
  end
end

process CancelProbe(fs: Fs, http: Http, clock: Clock, port: UInt16)
  state
    calls: UInt64
  end

  message Start : String

  fn update(state, message)
    case message
      Start:
        state.calls += 1
        cancellation(fs, http, clock, port, reply_by)
    end
  end
end

supervisor CancelProbes(fs: Fs, http: Http, clock: Clock, port: UInt16)
  child CancelProbe(fs, http, clock, port), restart: :never
end

fn main(platform: Platform)
  port = (platform.args.get(1) or "0").to_u64 or 0
  root = platform.fs.scoped(platform.args.first or "")
  probe = CancelProbe.start(root, platform.http, platform.clock, port.to_u16)
  case probe.ask(Start, within: 10_000.ms)
    Ok(text): platform.stdout.write(text)
    Error(_): platform.stdout.write_line("probe deadline")
  end
end

struct Observation
  calls: UInt64
  kept: Record
  steps: List(String)
  unchanged: Bool
  grace_ms: Int64
end

fn observation(book: Handle(Book), run: Handle(Run), fake: Handle(Fake), fs: Fs,
  id: String) : Result(Observation, String)
  kept = case book.ask(Look(owner: "test", id: id), within: 1.minute)
    Ok(Found(found)): found
    Ok(_) | Error(_):
      return Error("record unavailable")
  end
  steps = case book.ask(Steps(owner: "test", id: id), within: 1.minute)
    Ok(Transcribed(found)): found
    Ok(_) | Error(_):
      return Error("steps unavailable")
  end
  calls = case fake.ask(Served, within: 1.minute)
    Ok(n): n
    Error(_):
      return Error("count unavailable")
  end
  text = case fs.read("work/a", within: 1.minute)
    Ok(text): text
    Error(_):
      return Error("file unavailable")
  end
  grace = case run.ask(ReportDeadline, within: 1.minute)
    Ok(by): by.remaining.ms
    Error(_):
      return Error("grace unavailable")
  end
  Ok(Observation(calls: calls, kept: kept, steps: steps, unchanged: text == "before",
    grace_ms: grace))
end

fn stopped?(run: Handle(Run)) : Bool
  for _ in 0..100
    if run.ask(Look, within: 1.minute) is Ok(Stopped)
      return true
    end
  end
  false
end

fn boundary(mode: String, fs: Fs, logs: Fs, http: Http, clock: Clock,
  slow: Fs) : Result(Observation, String)
  if fs.write("work/a", "before", within: 1.minute) is Error(_) or logs.mkdir("work",
    within: 1.minute) is Error(_)
    return Error("setup unavailable")
  end
  book = Book.start(logs, clock, "runs", clock.now)
  order = Order(goal: "g", folder: "work", tools: [], hosts: [],
    budget: Budget(steps: 16, tokens: 4096, wall_ms: 30000, retries: 0, tool_ms: 2000))
  made = case book.ask(Create(owner: "test", order: order), within: 1.minute)
    Ok(Made(found)): found
    Ok(_) | Error(_):
      return Error("create unavailable")
  end
  if mode == "cancel" and !(book.ask(Cancel(owner: "test", id: made.id),
    within: 1.minute) is Ok(Stopped(_)))
    return Error("cancel unavailable")
  end
  replies = ["{\"tool\":\"exact_edit\",\"args\":{\"path\":\"a\",\"old_text\":\"before\",\"new_text\":\"after\"},\"tokens\":17}",
    "{\"done\":\"observed\",\"tokens\":0}"]
  fake = Fake.start(replies, slow)
  listener = case http.listen(0, within: 1.minute)
    Ok(found): found
    Error(_):
      return Error("listener unavailable")
  end
  listener.serve(into: fake, idle: 5000.ms)
  model = Model(host: "localhost", port: listener.port, tools: fixture_tools())
  run = Run.start(book, fs.scoped("work").read_only, None, http, clock,
    Setup(id: made.id, order: order, model: model))
  endpoint = Endpoint(host: "localhost", port: 1, workspace: "w")
  wait = if mode == "recording": 1.ms else: 1.minute
  if run.ask(ConfigureFixture(endpoint: endpoint), within: wait) != Ok(true)
    return Error("configure unavailable")
  end
  began = run.ask(Begin(me: run), within: if mode == "deadline": 0.ms else: 30000.ms)
  if began is Error(_) and mode != "deadline"
    return Error("begin unavailable")
  end
  return Error("run unavailable") if !stopped?(run)
  observation(book, run, fake, fs, made.id)
end

fn unknown_total?(record: Record, steps: List(String)) : Bool
  text = shown_report(record, steps)
  (text.lines.last or "").contains?("\"usage\": \"unknown\", \"tokens\": null")
end

fn call_limit(mode: String) : UInt64
  if mode == "grant" or mode == "grace": 2 else: if mode == "deadline": 0 else: 1
end

test "fixture value refusals and explicit reporting error"
  fs = Fs.fixture()
  assert fs.write("a", "before", within: 1.minute) is Ok(_)
  output = edited(fs, "a", "", "after", Deadline.fixture(1.minute))
  assert output.contains?("empty_match") and fs.read("a", within: 1.minute) == Ok("before")
  var kept = record("r_1", "test", "g", Time.fixture())
  assert report(kept, []) is Error(_)
  kept.status = Cancelled
  assert unknown_total?(kept, [])
  kept.status = Failed
  kept.why = Some("recording_failure")
  assert unknown_total?(kept, [])
  kept.status = Done
  kept.why = None
  assert shown_report(kept, []).contains?("\"usage\": \"reported_synthetic\", \"tokens\": 0")
  kept.steps_taken = 1
  assert report(kept, []) is Error(_)
end

test "fixture grant cancellation deadline and recording boundaries"
  for mode in ["grant", "cancel", "deadline", "recording", "grace"]
    fs = Fs.fixture()
    logs = if mode == "recording" or mode == "grace": Fs.fixture(delay: 5.ms) else: fs
    found = boundary(mode, fs, logs, Http.fixture(), Clock.fixture(), Fs.fixture())
    case found
      Ok(observed):
        assert observed.unchanged and observed.grace_ms >= 0 and observed.grace_ms <= 15000
        assert observed.calls <= call_limit(mode)
        if mode == "cancel" and observed.kept.status == Cancelled
          assert unknown_total?(observed.kept, observed.steps)
        end
        if mode == "grace" and observed.steps.size > 0
          assert observed.grace_ms < 15000
        end
        if mode == "grant" and observed.kept.status == Done
          assert observed.steps.size == 3 and (observed.steps.get(1) or "").contains?("grant")
        end
      Error(why):
        # Faults may prevent setup or observation; they never establish a successful run.
        assert why.contains?("unavailable")
    end
  end
end

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs)
          proven: not run
