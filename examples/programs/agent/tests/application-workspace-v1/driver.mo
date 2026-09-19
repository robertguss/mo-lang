module Agent.Tests.ApplicationWorkspaceV1.Driver

use Agent.Application{Application, Launch, Output, application_order, loaded, made, owner}
use Agent.Book{Book}
use Agent.Client{Sleeper}
use Agent.Model{Model}
use Agent.Record{fixture_tools}
use Agent.Run{Run}
use Agent.Steps{Setup}
use Agent.Tools{Call}
use Agent.WorkspaceAdapter{Settings, sent, tools}

intent "Real-socket probes of the application for both runtimes: one adapter call on a short deadline; a whole launch on a short outer deadline; the production watcher over an operator's Book and Run, cancelled during command collection or never begun; each prints one JSON line."

# A probe's words after its mode and configuration path.
struct Words
  root: String
  model_port: UInt16
  ms: Int64
  goal: String
end

# The operator's binding and a probe's words, together.
struct Bind
  bound: Settings
  words: Words
end

process Probe(fs: Fs, http: Http, clock: Clock)
  state
    calls: UInt64
  end

  message Go(args: List(String)) : String

  fn update(state, message)
    case message
      Go(args):
        state.calls += 1
        probed(fs, http, clock, args, reply_by)
    end
  end
end

supervisor Probes(fs: Fs, http: Http, clock: Clock)
  child Probe(fs, http, clock), restart: :never
end

fn words_of(args: List(String)) : Words
  Words(root: args.get(2) or "", model_port: ((args.get(3) or "0").to_u64 or 0).checked_to_u16 or 0,
    ms: (args.get(4) or "0").to_i64 or 0, goal: String.join(args.drop(5), " "))
end

fn probed(fs: Fs, http: Http, clock: Clock, args: List(String), by: Deadline) : String
  path = args.get(1) or ""
  bound = case loaded(fs.read_only, path, by)
    Ok(found): found
    Error(why):
      return "{\"error\": #{Json.encode(why)}}"
  end
  words = words_of(args)
  case args.first or ""
    "near":
      near(http, bound, (args.get(3) or "0").to_u64 or 0,
        by.at_most(((args.get(2) or "0").to_i64 or 0).ms))
    "launch": launched(fs, http, clock, path, words)
    "cancel": cancelled(fs, http, clock, bound, words, by)
    "unbegun": unbegun(fs, http, clock, bound, words, by)
    _: "{\"error\": \"unknown_mode\"}"
  end
end

# One command sent on a short deadline, with the deadline's remainder before and after.
fn near(http: Http, bound: Settings, bytes: UInt64, by: Deadline) : String
  before = by.remaining.ms
  call = Call(tool: "command", args: Map.new().set("command", "x".repeat(bytes)), granted: tools(),
    hosts: [])
  output = sent(http, bound, call, "1", by)
  "{\"before_ms\": #{before}, \"after_ms\": #{by.remaining.ms}, \"output\": #{Json.encode(output)}}"
end

# A whole launch on the given outer deadline, then its answer and poll counts.
fn launched(fs: Fs, http: Http, clock: Clock, path: String, words: Words) : String
  launch = Launch(version: "mo-application-workspace-v1", dir: words.root,
    model_port: words.model_port, config: path, goal: words.goal)
  worker = Application.start(fs, http, clock)
  output = case worker.ask(Launched(launch: launch, me: worker), within: words.ms.ms)
    Ok(found): found
    Error(_): Output(text: "", code: 255)
  end
  "{\"code\": #{output.code}, \"output\": #{Json.encode(output.text)}, #{settled(worker, Sleeper.start(http))}}"
end

# An operator's Book and application Run over a fresh root, as a launch makes them, begun or not.
fn begun_run(book: Handle(Book), root: Fs, http: Http, clock: Clock, bind: Bind,
  by: Deadline) : Option(Handle(Run))
  bound = bind.bound
  words = bind.words
  if !(book.ask(Open, within: by.at_most(2_000.ms)) is Ok(Ready(runs: 0, restarted: 0)))
    return None
  end
  order = application_order(words.goal)
  id = case made(book, order, bound, by)
    Ok(found): found
    Error(_):
      return None
  end
  model = Model(host: "127.0.0.1", port: words.model_port, tools: fixture_tools())
  run = Run.start(book, root.scoped("work").read_only, None, http, clock,
    Setup(id: id, order: order, model: model))
  if run.ask(ConfigureApplication(settings: bound), within: by) != Ok(true)
    return None
  end
  Some(run)
end

# Cancellation while a command is being collected: the Book is cancelled after a nap, the
# production watcher reports, and the log must not change for 300 ms afterwards.
fn cancelled(fs: Fs, http: Http, clock: Clock, bound: Settings, words: Words, by: Deadline) : String
  root = fs.scoped(words.root)
  book = Book.start(root, clock, "runs", clock.now)
  run = case begun_run(book, root, http, clock, Bind(bound: bound, words: words), by)
    Some(found): found
    None:
      return "{\"error\": \"setup\"}"
  end
  if run.ask(Begin(me: run), within: by.at_most(45_000.ms)) is Error(_)
    return "{\"error\": \"begin\"}"
  end
  sleeper = Sleeper.start(http)
  napped = sleeper.ask(Nap(ms: words.ms.to_u64), within: by) is Ok(_)
  stop = book.ask(Cancel(owner: owner(), id: bound.run), within: by.at_most(2_000.ms))
  watcher = Application.start(fs, http, clock)
  output = case watcher.ask(Watched(book: book, run: run, id: bound.run, me: watcher),
    within: by.at_most(30_000.ms))
    Ok(found): found
    Error(_): Output(text: "", code: 255)
  end
  log = "runs/#{bound.run}.log"
  before = root.read(log, within: by)
  stable = sleeper.ask(Nap(ms: 300), within: by) is Ok(_) and before == root.read(log, within: by)
  stopped = run.ask(Look, within: by.at_most(2_000.ms)) == Ok(Stopped)
  "{\"napped\": #{napped}, \"cancelled\": #{stop is Ok(Stopped(_))}, \"stable\": #{stable}, \"stopped\": #{stopped}, \"code\": #{output.code}, \"output\": #{Json.encode(output.text)}}"
end

# A watch whose Run never begins ends at its deadline, answered once, and polls no more.
fn unbegun(fs: Fs, http: Http, clock: Clock, bound: Settings, words: Words, by: Deadline) : String
  root = fs.scoped(words.root)
  book = Book.start(root, clock, "runs", clock.now)
  run = case begun_run(book, root, http, clock, Bind(bound: bound, words: words), by)
    Some(found): found
    None:
      return "{\"error\": \"setup\"}"
  end
  watcher = Application.start(fs, http, clock)
  output = case watcher.ask(Watched(book: book, run: run, id: bound.run, me: watcher),
    within: by.at_most(words.ms.ms))
    Ok(found): found
    Error(_): Output(text: "", code: 255)
  end
  "{\"code\": #{output.code}, \"output\": #{Json.encode(output.text)}, #{settled(watcher, Sleeper.start(http))}}"
end

# How many answers the watcher gave and whether it stopped polling: its poll count read twice,
# 300 ms apart.
fn settled(watcher: Handle(Application), sleeper: Handle(Sleeper)) : String
  first = counted(watcher.ask(Polls, within: 2_000.ms))
  napped = sleeper.ask(Nap(ms: 300), within: 2_000.ms) is Ok(_)
  second = counted(watcher.ask(Polls, within: 2_000.ms))
  answers = counted(watcher.ask(Answers, within: 2_000.ms))
  "\"answers\": #{answers}, \"polls\": [#{first}, #{second}], \"napped\": #{napped}"
end

fn counted(asked: Result(UInt64, AskError)) : Int64
  case asked
    Ok(n): n.to_i64
    Error(_): -1
  end
end

fn main(platform: Platform)
  probe = Probe.start(platform.fs, platform.http, platform.clock)
  case probe.ask(Go(args: platform.args), within: 900_000.ms)
    Ok(line): platform.stdout.write_line(line)
    Error(_): platform.stdout.write_line("{\"error\": \"probe_deadline\"}")
  end
end

verified: types, contracts, tests (0), property (0 seeds), sim (not run)
          proven: not run
