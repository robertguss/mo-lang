# sim: --faults 20 --until 0.5
module Jobq.Server
expose Acceptor, Acceptors, Client, Clients, serving

use Jobq.Board{Call, board}
use Jobq.Queue{Opening, Queue, Worker, stamp}
use Jobq.Store{Table, blank}

intent "Serve jobq over HTTP: the runtime serves the listener into an acceptor, which starts a worker per exchange and tells it to go, and turns each quiet spell into a sweep of the leases that ran out and the scheduled jobs that have come due; the listener's idle time is 10 seconds, so a connection that sends no whole request is closed within 10 seconds, and the acceptor's mailbox of 4,096 leaves room for 1,200 of them at once."

process Acceptor(queue: Handle(Queue)) mailbox: 4_096
  state
    accepted: UInt64
    quiet: UInt64
  end

  message Accepted(exchange: Exchange)
  message Idle

  fn update(state, message)
    case message
      Accepted(exchange):
        worker = Worker.start(exchange, queue)
        worker.send(Go(me: worker))
        state.accepted += 1
      Idle:
        queue.send(Sweep)
        state.quiet += 1
    end
  end
end

supervisor Acceptors(queue: Handle(Queue), exchange: Exchange)
  child Acceptor(queue), restart: :always
  child Worker(exchange, queue), restart: :never
end

# The queue, told its own handle, and the acceptor the listener is served into from here on.
fn serving(listener: HttpListener, fs: Fs, clock: Clock, opening: Opening) : Handle(Queue)
  queue = Queue.start(fs, clock, opening)
  queue.send(Begin(me: queue))
  listener.serve(into: Acceptor.start(queue), idle: 10_000.ms)
  queue
end

# A client that sends one request when told, and keeps the status it got, 0 for none.
process Client(http: Http, port: UInt16, request: Request)
  state
    status: UInt16
    body: String
  end

  message Go
  message Status : UInt16
  message Body : String

  fn update(state, message)
    case message
      Go:
        case http.send(request, host: "localhost", port: port, within: 1.minute)
          Ok(response):
            state.status = response.status
            state.body = response.body
          Error(_):
            state.status = 1
        end
      Status: state.status
      Body: state.body
    end
  end
end

supervisor Clients(http: Http, port: UInt16, request: Request)
  child Client(http, port, request), restart: :never
end

fn fresh() : Table
  blank("d")
end

fn by(method: String, path: String, token: String, body: String) : Request
  Request(method: method, path: path, headers: Map.new().set("authorization", "Bearer #{token}"),
    body: body)
end

fn sent(http: Http, port: UInt16, request: Request) : Result(Response, HttpError)
  http.send(request, host: "localhost", port: port, within: 1.minute)
end

# The status that came back, 503 for a queue that could not take the change, or 0 when the
# wire failed.
fn status(got: Result(Response, HttpError)) : UInt16
  case got
    Ok(response): response.status
    Error(_): 0
  end
end

fn in?(got: Result(Response, HttpError), statuses: List(UInt16)) : Bool
  statuses.push(0).contains?(status(got))
end

fn started(http: Http, fs: Fs, clock: Clock) : UInt16
  case http.listen(0, within: 1.minute)
    Ok(listener):
      queue = serving(listener, fs, clock, Opening(board: board(stamp(clock), 1), table: fresh()))
      if queue.ask(Serve(call: Call(worker: "", command: Health)), within: 1.minute) is Ok(_)
        return listener.port
      end
      listener.port
    Error(_): 0
  end
end

fn create(payload: String) : String
  "{\"queue\": \"q\", \"payload\": #{Json.encode(payload)}, \"max_tries\": 2}"
end

# A job made to wait: a delay before it is queued at all, and a backoff after each fail.
fn waiting(payload: String, delay_ms: UInt64, backoff_ms: UInt64) : String
  "{\"queue\": \"q\", \"payload\": #{Json.encode(payload)}, \"max_tries\": 2, \"delay_ms\": #{delay_ms}, \"backoff_ms\": #{backoff_ms}}"
end

# The status of a client once it has one, asking up to 200 times.
fn heard(client: Handle(Client)) : UInt16
  var got = 0
  for _ in 0..200
    got = case client.ask(Status, within: 1.minute)
      Ok(s): s
      Error(_): 0
    end
    if got != 0
      break
    end
  end
  got
end

fn job_id(body: String) : String
  case Json.decode(body)
    Ok(Object(fields)): text_of(fields.get("id") or Null)
    Ok(_): ""
    Error(_): ""
  end
end

fn text_of(value: Json) : String
  case value
    String(text): text
    Object(_) | Array(_) | Number(_) | Bool(_) | Null: ""
  end
end

# Every job still leased acked by the worker its record names: a lease granted whose response was
# lost under faults is finished this way.
fn recovered(http: Http, port: UInt16)
  listing = Request(method: "GET", path: "/jobs", query: Map.new().set("state", "leased"),
    headers: Map.new().set("authorization", "Bearer p"))
  for pair in leased_pairs(sent(http, port, listing))
    if status(sent(http, port, by("POST", "/jobs/#{pair.0}/ack", pair.1, ""))) == 503
      break
    end
  end
end

# Every dead job put back in its queue, so the run ends with every job done.
fn revived(http: Http, port: UInt16)
  listing = Request(method: "GET", path: "/jobs", query: Map.new().set("state", "dead"),
    headers: Map.new().set("authorization", "Bearer p"))
  for pair in leased_pairs(sent(http, port, listing))
    if status(sent(http, port, by("POST", "/jobs/#{pair.0}/retry", "p", ""))) == 503
      break
    end
  end
end

fn leased_pairs(got: Result(Response, HttpError)) : List((String, String))
  body = case got
    Ok(response): response.body
    Error(_): ""
  end
  case Json.decode(body)
    Ok(Object(fields)): items_of(fields.get("jobs") or Null).map(fn(item) pair_of(item) end)
    Ok(_): []
    Error(_): []
  end
end

fn items_of(value: Json) : List(Json)
  case value
    Array(items): items
    Object(_) | String(_) | Number(_) | Bool(_) | Null: []
  end
end

fn pair_of(item: Json) : (String, String)
  case item
    Object(fields): (text_of(fields.get("id") or Null), text_of(fields.get("worker") or Null))
    Array(_) | String(_) | Number(_) | Bool(_) | Null: ("", "")
  end
end

test "each status comes back over the wire, unless a call fails or the log did not take it"
  http = Http.fixture()
  port = started(http, Fs.fixture(), Clock.fixture())
  assert port != 0
  assert in?(sent(http, port, Request(method: "GET", path: "/health")), [200])
  assert in?(sent(http, port, Request(method: "GET", path: "/jobs")), [401])
  assert in?(sent(http, port, by("PATCH", "/jobs", "p", "")), [405])
  assert in?(sent(http, port, by("GET", "/nowhere", "p", "")), [404])
  assert in?(sent(http, port, by("POST", "/jobs", "p", "{\"queue\": 1}")), [400])
  assert in?(sent(http, port, by("POST", "/jobs", "p",
    "{\"queue\": \"q\", \"payload\": \"\", \"max_attempts\": 2}")), [400])
  made = sent(http, port, by("POST", "/jobs", "p", create("hello")))
  assert in?(made, [201, 503])
  assert in?(sent(http, port, by("GET", "/jobs/j_77", "p", "")), [404, 503])
  assert in?(sent(http, port, by("POST", "/jobs/j_77/retry", "p", "")), [404, 503])
  assert in?(sent(http, port, by("GET", "/jobs/j_1/retry", "p", "")), [405])
  if status(made) == 201
    assert in?(sent(http, port, by("POST", "/jobs/j_1/retry", "p", "")), [409, 503])
    assert in?(sent(http, port, by("POST", "/queues/q/lease", "w1", "{\"lease_ms\": 60000}")),
      [200, 503])
    assert in?(sent(http, port, by("DELETE", "/jobs/j_1", "p", "")), [409, 204, 503])
    assert in?(sent(http, port, by("POST", "/jobs/j_1/ack", "w2", "")), [409, 404, 503])
  end
  later = sent(http, port, by("POST", "/jobs", "p", waiting("later", 3_600_000, 1_000)))
  assert in?(later, [201, 503])
  if status(later) == 201
    assert in?(sent(http, port, by("GET", "/jobs?state=scheduled", "p", "")), [200, 503])
  end
  health = sent(http, port, Request(method: "GET", path: "/health"))
  if health is Ok(answer) and answer.status == 200
    assert answer.body.contains?("\"scheduled\":")
  end
  assert in?(sent(http, port, by("POST", "/queues/q/lease", "w3", "")), [200, 204, 503])
end

test "two workers race over the wire for one job, and at most one of them holds it"
  http = Http.fixture()
  port = started(http, Fs.fixture(), Clock.fixture())
  made = sent(http, port, by("POST", "/jobs", "p", create("only one")))
  lease = "{\"lease_ms\": 60000}"
  first = Client.start(http, port, by("POST", "/queues/q/lease", "w1", lease))
  second = Client.start(http, port, by("POST", "/queues/q/lease", "w2", lease))
  first.send(Go)
  second.send(Go)
  statuses = [heard(first), heard(second)]
  assert statuses.count(fn(s) s == 200 end) <= 1
  if status(made) == 201 and !statuses.contains?(503) and !statuses.contains?(1)
    assert statuses.count(fn(s) s == 200 end) == 1 and statuses.count(fn(s) s == 204 end) == 1
  end
end

test "1,200 connections that send nothing do not stop a producer's request from being answered"
  net = Net.fixture()
  http = Http.fixture()
  port = started(http, Fs.fixture(), Clock.fixture())
  var crowd = [0].take(0)
  var quiet = 0
  for _ in 0..1_200
    if net.connect("localhost", port, within: 1.minute) is Ok(_)
      quiet += 1
    end
    crowd = crowd.push(quiet)
  end
  assert crowd.size == 1_200
  made = sent(http, port, by("POST", "/jobs", "p", create("past the crowd")))
  assert in?(made, [201, 503])
end

test "over the wire, every answer is right or 503, and every job ends done once faults stop"
  http = Http.fixture()
  fs = Fs.fixture()
  port = started(http, fs, Clock.fixture())
  for i in 0..4
    assert in?(sent(http, port, by("POST", "/jobs", "p", create("job #{i}"))), [201, 503])
  end
  var ended = false
  for round in 0..300
    worker = "w#{round % 2}"
    lent = sent(http, port, by("POST", "/queues/q/lease", worker, "{\"lease_ms\": 3600000}"))
    assert in?(lent, [200, 204, 503])
    if lent is Ok(response) and response.status == 200
      path = "/jobs/#{job_id(response.body)}/#{if round % 3 == 0: "fail" else: "ack"}"
      assert in?(sent(http, port, by("POST", path, worker, "{\"reason\": \"retry\"}")), [200, 503])
    end
    if status(lent) == 204
      recovered(http, port)
      if round < 150
        revived(http, port)
      end
    end
    health = sent(http, port, Request(method: "GET", path: "/health"))
    if health is Ok(answer) and answer.body.contains?("\"queued\": 0, \"scheduled\": 0, \"leased\": 0,")
      ended = status(lent) == 204
    end
    if ended
      break
    end
  end
  assert ended
end

verified: types, contracts, tests (4), property (0 seeds), sim (100 runs)
          proven: not run
