# run: check data/demo data/script.txt data/runs.txt
# run: run data/solo --model 127.0.0.1:1 --folder work say what the folder holds
# exit: 3
# run: mock data/nowhere.txt
# exit: 1
# run: serve
# exit: 2
# run: serve data/nowhere --model 127.0.0.1:1
# exit: 1
# run: client 127.0.0.1 1 ada GET /runs
# exit: 1
module Agent.Main
expose Task, Spot, Solo, Said, Problem, Words, task, serving?, main

use Agent.Api{Command, Want}
use Agent.Application{Application, Launch}
use Agent.Book{Book}
use Agent.Check{Place, checked}
use Agent.Client{Trip, Sleeper, request_of, shown}
use Agent.CodingFixture{Fixture, Config, fixture_deadline}
use Agent.Mock{Cursor, MockServer}
use Agent.Model{Model}
use Agent.Operator{Operator}
use Agent.Record{Order, Record, Status, default_budget, order, goal?, folder?, tools?, tool_names, status_name}
use Agent.Registry{Registry}
use Agent.Server{Acceptor}
use Agent.Shelf{Opened, Outcome}

intent "Run agent: serve a folder's runs over HTTP against a model, play a script as the model, make one run and print its transcript, send one request as a client, or check a folder by serving it with the scripted model on free ports and playing a runs file through the client; a usage error exits 2, a folder or port that cannot be had exits 1, and one run exits 0 done, 4 over budget, and 3 otherwise."

# Where to serve: the folder, the model, the port, and the operator's view's port, 0 for none.
struct Spot
  dir: String
  model: Model
  port: UInt16
  surface: UInt16
end

# One run: the service's folder, the model, and the order.
struct Solo
  dir: String
  model: Model
  order: Order
end

# What a command printed, and the code it exits with.
struct Said
  text: String
  code: UInt8
end

# A command's words, and the value after each --flag.
struct Words
  plain: List(String)
  flags: Map(String, String)
end

enum Task
  Serving(spot: Spot)
  Mocking(script: String, port: UInt16)
  Soloing(solo: Solo)
  Asking(trip: Trip)
  Checking(place: Place)
end

enum Problem
  Usage(detail: String)
  Unopened(dir: String, why: String)
  Unbound(port: UInt16)
  Unreached(host: String, port: UInt16)
end

fn usage() : String
  "usage: agent serve <dir> --model host:port [--port N] [--surface PORT] | agent mock <script> [--port N] | agent run <dir> --model host:port <goal> [--tools a,b] [--folder p] | agent client <host> <port> <token> <method> <path> [<json>] | agent check <dir> <script> <runs>"
end

fn task(args: List(String)) : Result(Task, Problem)
  rest = args.drop(1)
  case args.first or ""
    "serve": serving(rest)
    "mock": mocking(rest)
    "run": soloing(rest)
    "client": asking(rest)
    "check": checking(rest)
    "": Error(Usage(detail: "no command given"))
    _: Error(Usage(detail: "unknown command #{args.first or ""}"))
  end
end

# The words of a command, each --flag taking the word after it.
fn words_of(args: List(String), so_far: Words) : Result(Words, Problem)
  return Ok(so_far) if args.size == 0
  word = args.first or ""
  if !word.starts_with?("--")
    return words_of(args.drop(1), Words(plain: so_far.plain.push(word), flags: so_far.flags))
  end
  value = args.get(1) or ""
  return Error(Usage(detail: "#{word} takes a value")) if args.size < 2 or value.starts_with?("--")
  return Error(Usage(detail: "#{word} is given twice")) if so_far.flags.has?(word)
  words_of(args.drop(2), Words(plain: so_far.plain, flags: so_far.flags.set(word, value)))
end

fn words(args: List(String), allowed: List(String)) : Result(Words, Problem)
  found = try words_of(args, Words(plain: [], flags: Map.new()))
  unknown = found.flags.keys.filter(fn(flag) !allowed.contains?(flag) end)
  return Error(Usage(detail: "#{unknown.first or ""} is not a flag here")) if unknown.size > 0
  Ok(found)
end

fn serving(args: List(String)) : Result(Task, Problem)
  given = try words(args, ["--model", "--port", "--surface"])
  return Error(Usage(detail: "serve takes a folder")) if given.plain.size != 1
  dir = try dir_of(given.plain.first or "")
  model = try model_of(given.flags.get("--model") or "")
  port = try port_or(given, "--port", 7_950)
  surface = try port_or(given, "--surface", 0)
  Ok(Serving(spot: Spot(dir: dir, model: model, port: port, surface: surface)))
end

fn mocking(args: List(String)) : Result(Task, Problem)
  given = try words(args, ["--port"])
  return Error(Usage(detail: "mock takes a script")) if given.plain.size != 1
  Ok(Mocking(script: given.plain.first or "", port: try port_or(given, "--port", 7_951)))
end

fn soloing(args: List(String)) : Result(Task, Problem)
  given = try words(args, ["--model", "--tools", "--folder"])
  return Error(Usage(detail: "run takes a folder and a goal")) if given.plain.size < 2
  dir = try dir_of(given.plain.first or "")
  model = try model_of(given.flags.get("--model") or "")
  goal = String.join(given.plain.drop(1), " ")
  folder = given.flags.get("--folder") or "work"
  tools = (given.flags.get("--tools") or "").split(",").filter(fn(t) t != "" end)
  return Error(Usage(detail: "a goal is 1 byte to 4 KiB")) if !goal?(goal)
  return Error(Usage(detail: "#{folder} is not a folder a run may use")) if !folder?(folder)
  return Error(Usage(detail: "--tools names tools the harness has, each once")) if !tools?(tools)
  run_order = order(goal, folder, tools, [], default_budget())
  Ok(Soloing(solo: Solo(dir: dir, model: model, order: run_order)))
end

fn asking(args: List(String)) : Result(Task, Problem)
  if args.size < 5
    return Error(Usage(detail: "client takes a host, a port, a token, a method, and a path"))
  end
  port = try port_of(args.get(1) or "")
  Ok(Asking(trip: Trip(host: args.first or "", port: port, token: args.get(2) or "",
    method: args.get(3) or "", path: args.get(4) or "", json: String.join(args.drop(5), " "))))
end

fn checking(args: List(String)) : Result(Task, Problem)
  return Error(Usage(detail: "check takes a folder, a script, and a runs file")) if args.size != 3
  dir = try dir_of(args.first or "")
  Ok(Checking(place: Place(dir: dir, script: args.get(1) or "", runs: args.get(2) or "")))
end

fn dir_of(text: String) : Result(String, Problem)
  return Error(Usage(detail: "no folder given")) if text == "" or text.starts_with?("-")
  Ok(text)
end

# A model's address, host:port.
fn model_of(text: String) : Result(Model, Problem)
  at = text.index_of(":") or text.size
  host = text.slice(0, at)
  return Error(Usage(detail: "--model host:port is needed")) if host == "" or at == text.size
  port = try port_of(text.slice(at + 1, text.size))
  Ok(Model(host: host, port: port, tools: tool_names()))
end

fn port_or(given: Words, flag: String, otherwise: UInt16) : Result(UInt16, Problem)
  case given.flags.get(flag)
    Some(text): port_of(text)
    None: Ok(otherwise)
  end
end

fn port_of(text: String) : Result(UInt16, Problem)
  ensures result is Ok(port) implies port >= 1

  n = text.to_u64 or 0
  return Error(Usage(detail: "a port is a number from 1 to 65535, not #{text}")) if n < 1 or n > 65_535
  Ok(n.to_u16)
end

fn ran(http: Http, fs: Fs, clock: Clock, err: Out, runtime: Option(Runtime),
  args: List(String)) : Result(Said, Problem)
  return coding_fixture(http, fs, clock, args.drop(1)) if args.first == Some("coding-fixture")
  if args.first == Some("application-workspace")
    return application_workspace(http, fs, clock, args.drop(1))
  end
  given = try task(args)
  case given
    Serving(spot): serve(http, fs, clock, err, runtime, spot)
    Mocking(script: script, port: port): mock(http, fs, script, port)
    Soloing(solo): run_once(http, fs, clock, err, solo)
    Asking(trip): client(http, trip)
    Checking(place):
      case checked(http, fs, clock, err, place)
        Ok(text): Ok(Said(text: text, code: 0))
        Error(why): Error(Unopened(dir: place.dir, why: why))
      end
  end
end

# The operator supplies ports, workspace identity and a disposable root containing work/.
fn coding_fixture(http: Http, fs: Fs, clock: Clock, args: List(String)) : Result(Said, Problem)
  given = try words(args, ["--model", "--command", "--workspace"])
  return Error(Usage(detail: "coding-fixture takes a disposable root and goal")) if given.plain.size < 2
  model = try model_of(given.flags.get("--model") or "")
  command = try model_of(given.flags.get("--command") or "")
  if model.host != "127.0.0.1" or command.host != "127.0.0.1"
    return Error(Usage(detail: "fixture endpoints must use 127.0.0.1"))
  end
  workspace = given.flags.get("--workspace") or ""
  return Error(Usage(detail: "--workspace needs an opaque identity")) if workspace == "" or workspace.byte_size > 256
  goal = String.join(given.plain.drop(1), " ")
  return Error(Usage(detail: "goal is 1 byte to 4 KiB")) if !goal?(goal)
  config = Config(dir: try dir_of(given.plain.first or ""), model_port: model.port,
    command_port: command.port, workspace: workspace, goal: goal)
  worker = Fixture.start(fs, http, clock)
  case worker.ask(Start(config: config), within: fixture_deadline())
    Ok(output): Ok(Said(text: output.text, code: output.code))
    Error(_):
      Ok(Said(text: "{\"schema\":\"mo-coding-fixture-v1\",\"run_id\":\"\",\"event\":\"reporting_error\",\"step_number\":0,\"payload\":{\"error\":\"fixture_deadline\"}}\n",
        code: 3))
  end
end

# The operator supplies a fresh root holding work/, the scripted model's loopback port and the
# path of the private bridge configuration; no capability is ever a flag or a word here.
fn application_workspace(http: Http, fs: Fs, clock: Clock, args: List(String)) : Result(Said,
  Problem)
  given = try words(args, ["--model", "--config"])
  if given.plain.size < 2
    return Error(Usage(detail: "application-workspace takes a fresh root and a goal"))
  end
  model = try model_of(given.flags.get("--model") or "")
  return Error(Usage(detail: "the model endpoint must use 127.0.0.1")) if model.host != "127.0.0.1"
  config = given.flags.get("--config") or ""
  if config == "" or config.byte_size > 1_024
    return Error(Usage(detail: "--config names the private bridge configuration"))
  end
  goal = String.join(given.plain.drop(1), " ")
  return Error(Usage(detail: "goal is 1 byte to 4 KiB")) if !goal?(goal)
  launch = Launch(version: "mo-application-workspace-v1", dir: try dir_of(given.plain.first or ""),
    model_port: model.port, config: config, goal: goal)
  worker = Application.start(fs, http, clock)
  case worker.ask(Launched(launch: launch, me: worker), within: 900_000.ms)
    Ok(output): Ok(Said(text: output.text, code: output.code))
    Error(_):
      Ok(Said(text: "{\"schema\": \"mo-application-workspace-v1\", \"run_id\": \"\", \"event\": \"reporting_error\", \"step_number\": 0, \"payload\": {\"error\": \"application_deadline\", \"persistence\": \"uncertain\"}}\n",
        code: 3))
  end
end

# The book over a folder's runs, opened before anything is served, so a folder that cannot be read
# exits 1 and every log is replayed first; a run a log left running is failed as restarted.
fn opened_book(fs: Fs, clock: Clock, err: Out, dir: String) : Result(Handle(Book), Problem)
  book = Book.start(fs.scoped(dir), clock, "runs", clock.now)
  case book.ask(Open, within: 1_260_000.ms)
    Ok(Ready(runs: _, restarted: restarted)):
      if restarted > 0
        err.write_line("agent: #{restarted} runs left running in #{dir}/runs are failed as restarted")
      end
      Ok(book)
    Ok(Unready(why)): Error(Unopened(dir: dir, why: why))
    Error(_): Error(Unopened(dir: dir, why: "took longer than 21 minutes to open"))
  end
end

# Serves a folder's runs until agent is stopped; the runtime owns the loop.
fn serve(http: Http, fs: Fs, clock: Clock, err: Out, runtime: Option(Runtime),
  spot: Spot) : Result(Said, Problem)
  book = try opened_book(fs, clock, err, spot.dir)
  registry = Registry.start(book, fs.scoped(spot.dir), http, clock, spot.model)
  case http.listen(spot.port, within: 5_000.ms)
    Ok(listener):
      listener.serve(into: Acceptor.start(registry), idle: 5_000.ms)
      view = try surfaced(http, clock, runtime, spot.surface)
      Ok(Said(text: "agent: serving #{spot.dir} on 127.0.0.1:#{listener.port} with the model at #{spot.model.host}:#{spot.model.port}#{view}\n",
        code: 0))
    Error(_): Error(Unbound(port: spot.port))
  end
end

# The operator's view on its port, over the runtime surface held read-only; a binary built without
# the surface has none to give.
fn surfaced(http: Http, clock: Clock, runtime: Option(Runtime), port: UInt16) : Result(String,
  Problem)
  return Ok("") if port == 0
  case runtime
    Some(surface):
      case http.listen(port, within: 5_000.ms)
        Ok(listener):
          listener.serve(into: Operator.start(surface.read_only, clock), idle: 60_000.ms)
          Ok(", and the operator's view on 127.0.0.1:#{listener.port}")
        Error(_): Error(Unbound(port: port))
      end
    None:
      Error(Unopened(dir: "--surface",
        why: "needs the runtime surface, and this binary was built without it (mo build --surface)"))
  end
end

fn mock(http: Http, fs: Fs, script: String, port: UInt16) : Result(Said, Problem)
  cursor = Cursor.start(try script_lines(fs, script))
  case http.listen(port, within: 5_000.ms)
    Ok(listener):
      listener.serve(into: MockServer.start(cursor, http), idle: 60_000.ms)
      Ok(Said(text: "agent: the scripted model plays #{script} on 127.0.0.1:#{listener.port}\n",
        code: 0))
    Error(_): Error(Unbound(port: port))
  end
end

fn script_lines(fs: Fs, script: String) : Result(List(String), Problem)
  case fs.read_only.read_lines(script, within: 10_000.ms)
    Ok(found): Ok(found)
    Error(_): Error(Unopened(dir: script, why: "is not a script agent can read"))
  end
end

# One run, made through the registry as agent serve makes one, watched to its end.
fn run_once(http: Http, fs: Fs, clock: Clock, err: Out, solo: Solo) : Result(Said, Problem)
  book = try opened_book(fs, clock, err, solo.dir)
  registry = Registry.start(book, fs.scoped(solo.dir), http, clock, solo.model)
  case registry.ask(Serve(command: Command(owner: "agent", want: WantNew(order: solo.order))),
    within: 60_000.ms)
    Ok(Made(run)): Ok(watched(http, book, run.id, solo.order))
    Ok(NoFolder): Error(Unopened(dir: "#{solo.dir}/#{solo.order.folder}", why: "is not a folder"))
    Ok(_) | Error(_): Error(Unopened(dir: solo.dir, why: "could not make the run"))
  end
end

# The run's transcript once it ends, looking every 20 ms for as long as its wall budget and the
# book's grace allow.
fn watched(http: Http, book: Handle(Book), id: String, run_order: Order) : Said
  sleeper = Sleeper.start(http)
  for _ in 0..(run_order.budget.wall_ms / 20 + 6_000)
    if book.ask(Look(owner: "agent", id: id), within: 10_000.ms) is Ok(Found(record))
      return told(book, record) if record.status != Running
    end
    if sleeper.ask(Nap(ms: 20), within: 10_000.ms) is Error(_)
      return Said(text: "agent: the sleeper did not wake\n", code: 3)
    end
  end
  Said(text: "agent: #{id} is still running\n", code: 3)
end

# Each step on a line, then how the run ended.
fn told(book: Handle(Book), record: Record) : Said
  steps = case book.ask(Steps(owner: "agent", id: record.id), within: 10_000.ms)
    Ok(Transcribed(found)): found
    Ok(_) | Error(_): []
  end
  ending = "#{status_name(record.status)}: #{record.answer or (record.why or "")}"
  lines = steps.map(fn(step) step_line(step) end).push(ending)
  Said(text: "#{String.join(lines, "\n")}\n", code: exit_of(record.status))
end

fn exit_of(status: Status) : UInt8
  case status
    Done: 0
    OverBudget: 4
    Running | Failed | Cancelled: 3
  end
end

# A step as one line: its number, its kind and name, whether it was refused, a model call's
# tokens, and its result as JSON.
fn step_line(step: String) : String
  fields = case Json.decode(step)
    Ok(Object(found)): found
    Ok(_) | Error(_): Map.new()
  end
  n = (fields.get("n") or Null).to_i64 or 0
  kind = text_in(fields, "kind")
  marks = if fields.get("refused") == Some(Bool(value: true)): " (refused)" else: ""
  tokens = if kind == "model": " (#{(fields.get("tokens") or Null).to_i64 or 0} tokens)" else: ""
  "#{n} #{kind} #{text_in(fields, "name")}#{marks}#{tokens}: #{Json.encode(text_in(fields, "result"))}"
end

fn text_in(fields: Map(String, Json), name: String) : String
  case fields.get(name)
    Some(String(text)): text
    Some(_) | None: ""
  end
end

fn client(http: Http, trip: Trip) : Result(Said, Problem)
  case http.send(request_of(trip), host: trip.host, port: trip.port, within: 10_000.ms)
    Ok(response): Ok(Said(text: shown(response), code: 0))
    Error(_): Error(Unreached(host: trip.host, port: trip.port))
  end
end

fn said(problem: Problem) : String
  case problem
    Usage(detail): "#{detail}; #{usage()}"
    Unopened(dir: dir, why: why): "#{dir} #{why}"
    Unbound(port): "cannot listen on 127.0.0.1:#{port}"
    Unreached(host: host, port: port): "no agent answered at #{host}:#{port}"
  end
end

fn code_of(problem: Problem) : UInt8
  case problem
    Usage(_): 2
    Unopened(dir: _, why: _) | Unbound(_) | Unreached(host: _, port: _): 1
  end
end

# Whether the arguments say to serve, as agent serve and agent mock do until they are stopped.
fn serving?(args: List(String)) : Bool
  task(args) is Ok(Serving(_)) or task(args) is Ok(Mocking(script: _, port: _))
end

fn main(platform: Platform)
  args = platform.args
  case ran(platform.http, platform.fs, platform.clock, platform.stderr, platform.runtime, args)
    Ok(done):
      platform.stdout.write(done.text)
      platform.stdout.flush
      if !serving?(args)
        platform.exit(done.code)
      end
    Error(problem):
      platform.stderr.write_line("agent: #{said(problem)}")
      platform.exit(code_of(problem))
  end
end

test "serve takes a folder and a model, and a port and the operator's port when given"
  model = Model(host: "127.0.0.1", port: 7_951, tools: tool_names())
  assert task(["serve",
    "d",
    "--model",
    "127.0.0.1:7951"]) == Ok(Serving(spot: Spot(dir: "d", model: model, port: 7_950, surface: 0)))
  assert task(["serve",
    "d",
    "--model",
    "127.0.0.1:7951",
    "--port",
    "8000",
    "--surface",
    "8001"]) == Ok(Serving(spot: Spot(dir: "d", model: model, port: 8_000, surface: 8_001)))
  assert task(["mock", "s.txt"]) == Ok(Mocking(script: "s.txt", port: 7_951))
  assert serving?(["mock", "s.txt"]) and !serving?(["check", "a", "b", "c"])
end

test "run takes a folder, a model, and a goal of the words left, and its tools and folder when given"
  given = task(["run", "d", "count", "--model", "h:1", "the", "notes", "--tools", "read_file,now"])
  assert given is Ok(Soloing(solo))
  assert solo.order.goal == "count the notes" and solo.order.tools == ["read_file", "now"]
  assert solo.order.folder == "work" and solo.model.host == "h" and solo.model.port == 1
  assert task(["run", "d", "g", "--model", "h:1", "--folder", "../x"]) is Error(Usage(_))
  assert task(["run", "d", "g", "--model", "h:1", "--tools", "rm"]) is Error(Usage(_))
  assert task(["run", "d", "--model", "h:1"]) is Error(Usage(_))
end

test "a missing folder, model, or port, a flag out of place, or an unknown command is a usage error"
  assert task([]) is Error(Usage(_))
  assert task(["serve"]) is Error(Usage(_))
  assert task(["serve", "d"]) is Error(Usage(_))
  assert task(["serve", "d", "--model", "h"]) is Error(Usage(_))
  assert task(["serve", "d", "--model", "h:0"]) is Error(Usage(_))
  assert task(["serve", "d", "--model", "h:1", "--port"]) is Error(Usage(_))
  assert task(["serve", "d", "--model", "h:1", "--tools", "now"]) is Error(Usage(_))
  assert task(["serve", "d", "--model", "h:1", "--model", "h:2"]) is Error(Usage(_))
  assert task(["mock"]) is Error(Usage(_))
  assert task(["client", "h", "1", "ada", "GET"]) is Error(Usage(_))
  assert task(["check", "d", "s"]) is Error(Usage(_))
  assert task(["stop"]) is Error(Usage(_))
end

test "application-workspace takes a loopback model, a configuration path and a goal, and no capability flag"
  http = Http.fixture()
  fs = Fs.fixture()
  clock = Clock.fixture()
  bare = application_workspace(http, fs, clock, ["root"])
  assert bare is Error(Usage(_))
  away = application_workspace(http, fs, clock, ["root", "g", "--model", "h:1", "--config", "c"])
  assert away is Error(Usage(_))
  token = application_workspace(http, fs, clock,
    ["root", "g", "--model", "127.0.0.1:1", "--config", "c", "--token", "t"])
  assert token is Error(Usage(_))
  unnamed = application_workspace(http, fs, clock, ["root", "g", "--model", "127.0.0.1:1"])
  assert unnamed is Error(Usage(_))
end

test "a step prints on one line, and a usage error exits 2 where a folder or port exits 1"
  step = "{\"n\": 2, \"kind\": \"tool\", \"name\": \"read_file\", \"args\": {}, \"result\": \"a\\nb\", \"tokens\": 0, \"took_ms\": 1, \"refused\": true}"
  assert step_line(step) == "2 tool read_file (refused): \"a\\nb\""
  assert step_line("{\"n\": 1, \"kind\": \"model\", \"name\": \"model\", \"result\": \"x\", \"tokens\": 7}") == "1 model model (7 tokens): \"x\""
  assert exit_of(Done) == 0 and exit_of(OverBudget) == 4 and exit_of(Failed) == 3
  assert code_of(Usage(detail: "x")) == 2 and code_of(Unbound(port: 1)) == 1
  assert code_of(Unopened(dir: "d", why: "w")) == 1 and code_of(Unreached(host: "h", port: 1)) == 1
end

verified: types, contracts, tests (5), property (0 seeds), sim (not run)
          proven: not run
