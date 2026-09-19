module Agent.Tests.ApplicationWorkspaceV1.Boundaries

use Agent.Application{Application, Launch, Output, application_order, owner}
use Agent.Book{Book}
use Agent.Model{Model, Fake}
use Agent.Record{fixture_tools}
use Agent.Run{Run}
use Agent.Steps{Setup}
use Agent.WorkspaceAdapter{Settings}

intent "The application watcher under simulated faults: a launch that fails at startup and a watch that reaches its deadline are each answered at most once, with a versioned reporting error, and no poll is scheduled afterwards."

# What a watch came to: its answer, the answers counted, and its poll count read twice across a
# wait, which must not grow once it has answered.
struct Watch
  output: Output
  answers: UInt64
  before: UInt64
  after: UInt64
end

fn bound(port: UInt16) : Settings
  Settings(port: port, run: "r_1", workspace: "0123456789abcdef0123456789abcdef",
    token: "ab".repeat(32))
end

fn model_port(http: Http, fs: Fs, replies: List(String)) : Result(UInt16, String)
  case http.listen(0, within: 1.minute)
    Ok(listener):
      listener.serve(into: Fake.start(replies, fs), idle: 5000.ms)
      Ok(listener.port)
    Error(_): Error("listener unavailable")
  end
end

# The poll count and answers after the watch has answered, across a simulated wait.
fn watched(app: Handle(Application), output: Output, pause: Fs) : Result(Watch, String)
  before = case app.ask(Polls, within: 1.minute)
    Ok(n): n
    Error(_):
      return Error("polls unavailable")
  end
  waited = pause.list(within: 1.minute) is Ok(_)
  after = case app.ask(Polls, within: 1.minute)
    Ok(n): n
    Error(_):
      return Error("polls unavailable")
  end
  answers = case app.ask(Answers, within: 1.minute)
    Ok(n): n
    Error(_):
      return Error("answers unavailable")
  end
  Ok(Watch(output: output, answers: answers, before: before, after: if waited: after else: before))
end

# An application Run over the fixture filesystem, configured with the given wait and not begun.
fn configured(fs: Fs, http: Http, clock: Clock, book: Handle(Book), port: UInt16,
  wait: Duration) : Result(Handle(Run), String)
  order = application_order("g")
  id = case book.ask(Create(owner: owner(), order: order), within: 1.minute)
    Ok(Made(found)): found.id
    Ok(_) | Error(_):
      return Error("create unavailable")
  end
  run = Run.start(book, fs.scoped("work").read_only, None, http, clock,
    Setup(id: id, order: order,
    model: Model(host: "localhost", port: port, tools: fixture_tools())))
  if run.ask(ConfigureApplication(settings: bound(0)), within: wait) != Ok(true)
    return Error("configure unavailable")
  end
  Ok(run)
end

fn poller(mode: String, fs: Fs, http: Http, clock: Clock, pause: Fs) : Result(Watch, String)
  app = Application.start(fs, http, clock)
  if mode == "startup"
    launch = Launch(version: "mo-application-workspace-v1", dir: ".", model_port: 1,
      config: "missing.json", goal: "g")
    return case app.ask(Launched(launch: launch, me: app), within: 1.minute)
      Ok(output): watched(app, output, pause)
      Error(_): Error("answer unavailable")
    end
  end
  return Error("setup unavailable") if fs.mkdir("work", within: 1.minute) is Error(_)
  book = Book.start(fs, clock, "runs", clock.now)
  port = try model_port(http, fs, ["{\"done\":\"observed\",\"tokens\":0}"])
  run = try configured(fs, http, clock, book, port, 1.minute)
  case app.ask(Watched(book: book, run: run, id: "r_1", me: app), within: 2000.ms)
    Ok(output): watched(app, output, pause)
    Error(_): Error("answer unavailable")
  end
end

test "the watcher answers once and stops scheduling for a startup error and a deadline"
  for mode in ["startup", "deadline"]
    case poller(mode, Fs.fixture(), Http.fixture(), Clock.fixture(), Fs.fixture(delay: 200.ms))
      Ok(watch):
        assert watch.answers <= 1 and watch.before == watch.after
        assert watch.output.text.contains?("\"schema\": \"mo-application-workspace-v1\"")
        if mode == "startup"
          assert watch.before == 0 and watch.output.text.contains?("config_unreadable")
        end
        if mode == "deadline"
          assert watch.output.text.contains?("report_deadline") and watch.output.code == 3
        end
      Error(why):
        # Faults may prevent setup or the answer; they never establish a second answer.
        assert why.contains?("unavailable")
    end
  end
end
