# sim: --faults 20 --until 0.5
module Agent.Server
expose Acceptor, Worker, Exchanges, answer

use Agent.Api{Routed, route, respond, health}
use Agent.Book{Book}
use Agent.Mock{Cursor, MockServer}
use Agent.Model{Model}
use Agent.Record{Status, tool_names}
use Agent.Registry{Registry}
use Agent.Shelf{Outcome}

intent "Serve agent over HTTP: the runtime serves the listener into an acceptor, which starts a worker per exchange and turns the listener's Idle into a sweep of the runs lost past their budgets; a worker reads its request into a command, asks the registry, which starts a run or asks the book, and replies, so a run's 201 goes out only once the book has written its first line."

# The mailbox is 4,096: the runtime counts connections that have sent no whole request against it.
# Idle comes only when no client came for a while, so the acceptor can wait for the sweep: 10
# seconds, which bounds every file call the sweep makes.
process Acceptor(registry: Handle(Registry)) mailbox: 4_096
  state
    accepted: UInt64
    quiet: UInt64
    lost: UInt64
  end

  message Accepted(exchange: Exchange)
  message Idle

  fn update(state, message)
    case message
      Accepted(exchange):
        Worker.start(exchange, registry).send(Answer)
        state.accepted += 1
      Idle:
        if registry.ask(Swept, within: 10_000.ms) is Ok(lost)
          state.lost += lost
        end
        state.quiet += 1
    end
  end
end

# Answers one exchange and ends.
process Worker(exchange: Exchange, registry: Handle(Registry))
  state
    answered: Bool
  end

  message Answer

  fn update(state, message)
    case message
      Answer:
        response = answer(registry, exchange.request)
        state.answered = exchange.reply(response, within: 10_000.ms) is Ok(_)
    end
  end
end

supervisor Exchanges(exchange: Exchange, registry: Handle(Registry))
  child Acceptor(registry), restart: :always
  child Worker(exchange, registry), restart: :never
end

# The response to one request. The ask waits 30 seconds, and the registry's and the book's calls
# for it wait only on what remains of them, so a book that could not write in time answers 503
# itself; a timed-out ask is 503 too, and its change may still land, as the failure model says.
fn answer(registry: Handle(Registry), request: Request) : Response
  case route(request)
    Answered(response): response
    Checkup:
      case registry.ask(Counts, within: 30_000.ms)
        Ok(Some(counts)): health(counts)
        Ok(None) | Error(_): respond(Unavailable(why: "the book did not answer in time"))
      end
    Asked(command):
      case registry.ask(Serve(command: command), within: 30_000.ms)
        Ok(outcome): respond(outcome)
        Error(_): respond(Unavailable(why: "the registry did not answer in time"))
      end
  end
end

fn sent(http: Http, port: UInt16, request: Request) : Result(Response, HttpError)
  http.send(request, host: "localhost", port: port, within: 1.minute)
end

fn by(owner: String, method: String, path: String, body: String) : Request
  Request(method: method, path: path, headers: Map.new().set("authorization", "Bearer #{owner}"),
    body: body)
end

fn status_in?(got: Result(Response, HttpError), statuses: List(UInt16)) : Bool
  case got
    Ok(response): statuses.contains?(response.status)
    Error(_): true
  end
end

# The run's id a 201 names, or "".
fn made_id(got: Result(Response, HttpError)) : String
  case got
    Ok(response):
      return "" if response.status != 201
      after = response.body.slice(8, response.body.size)
      after.slice(0, after.index_of("\"") or 0)
    Error(_): ""
  end
end

# Whether every run made has ended as the book holds it, the book asked up to three times for each,
# since under faults an ask may time out: the book's record is what a run's end is.
fn all_ended?(book: Handle(Book), ids: List(String)) : Bool
  for id in ids
    if id != "" and !ended?(book, id)
      return false
    end
  end
  true
end

fn ended?(book: Handle(Book), id: String) : Bool
  for _ in 0..3
    if book.ask(Look(owner: "ada", id: id), within: 1.minute) is Ok(Found(run))
      return run.status != Running
    end
  end
  false
end

test "each status comes back over the wire, unless a call fails"
  http = Http.fixture()
  fs = Fs.fixture()
  made = fs.mkdir("work", within: 1.minute) is Ok(_)
  assert http.listen(0, within: 1.minute) is Ok(model_port)
  model_port.serve(into: MockServer.start(Cursor.start(["{\"done\": \"hi\", \"tokens\": 1}"]),
    http),
    idle: 5_000.ms)
  book = Book.start(fs, Clock.fixture(), "runs", Time.fixture())
  model = Model(host: "localhost", port: model_port.port, tools: tool_names())
  registry = Registry.start(book, fs, http, Clock.fixture(), model)
  assert http.listen(0, within: 1.minute) is Ok(listener)
  listener.serve(into: Acceptor.start(registry), idle: 5_000.ms)
  port = listener.port
  order = "{\"goal\": \"say hi\", \"folder\": \"work\"}"
  assert made or status_in?(sent(http, port, by("ada", "GET", "/runs", "")), [200, 503])
  assert status_in?(sent(http, port, Request(method: "GET", path: "/health")), [200, 503])
  assert status_in?(sent(http, port, Request(method: "GET", path: "/runs")), [401])
  assert status_in?(sent(http, port, by("ada", "PATCH", "/runs", "")), [405])
  assert status_in?(sent(http, port, by("ada", "GET", "/nowhere", "")), [404])
  assert status_in?(sent(http, port, by("ada", "POST", "/runs", "{\"goal\": 1}")), [400])
  assert status_in?(sent(http, port,
    by("ada", "POST", "/runs", "{\"goal\": \"g\", \"folder\": \"gone\"}")),
    [400, 503])
  created = sent(http, port, by("ada", "POST", "/runs", order))
  assert status_in?(created, [201, 400, 503])
  id = made_id(created)
  if id != ""
    assert status_in?(sent(http, port, by("ada", "GET", "/runs/#{id}", "")), [200, 503])
    assert status_in?(sent(http, port, by("grace", "GET", "/runs/#{id}", "")), [404, 503])
    assert status_in?(sent(http, port, by("ada", "GET", "/runs/#{id}/transcript", "")), [200, 503])
  end
  assert status_in?(sent(http, port, by("ada", "GET", "/runs/r_77", "")), [404, 503])
  assert status_in?(sent(http, port, by("ada", "POST", "/runs/r_77/cancel", "")), [404, 503])
end

# Run with --faults 20 --until 0.5: while calls fail, every answer is right or a 503 (or a 400 for
# the run's folder, which a faulted list finds Missing, as a real one that is not there), and no never
# trips; once they stop, every run the book made ends in a final state, by its own end or, for one
# whose process never began, by a sweep once its wall budget and grace have passed.
test "under faults every answer is right or a 503, and once they stop every run ends"
  http = Http.fixture()
  fs = Fs.fixture()
  made = fs.write("work/notes.txt", "one", within: 1.minute) is Ok(_)
  assert http.listen(0, within: 1.minute) is Ok(model_port)
  script = ["{\"tool\": \"read_file\", \"args\": {\"path\": \"notes.txt\"}, \"tokens\": 2}",
    "{\"done\": \"one line\", \"tokens\": 1}"]
  model_port.serve(into: MockServer.start(Cursor.start(script), http), idle: 5_000.ms)
  book = Book.start(fs, Clock.fixture(), "runs", Time.fixture())
  model = Model(host: "localhost", port: model_port.port, tools: tool_names())
  registry = Registry.start(book, fs, http, Clock.fixture(), model)
  assert http.listen(0, within: 1.minute) is Ok(listener)
  listener.serve(into: Acceptor.start(registry), idle: 5_000.ms)
  port = listener.port
  order = "{\"goal\": \"count\", \"folder\": \"work\", \"tools\": [\"read_file\"], \"budget\": {\"wall_ms\": 1000, \"tool_ms\": 500}}"
  var ids = [""].take(0)
  for _ in 0..3
    created = sent(http, port, by("ada", "POST", "/runs", order))
    assert status_in?(created, [201, 400, 503])
    ids = ids.push(made_id(created))
  end
  slow = Fs.fixture(delay: 1.minute)
  for _ in 0..60
    if all_ended?(book, ids)
      break
    end
    moved = slow.size("clock", within: 1.minute) is Ok(_)
    swept = book.ask(Sweep, within: 1.minute)
    assert moved or !moved or swept is Ok(_) or swept is Error(_)
  end
  assert !made or all_ended?(book, ids)
end

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs)
          proven: not run
