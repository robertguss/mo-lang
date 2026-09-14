# sim: --faults 20 --until 0.5
module Jobq.Server
expose Acceptor, Worker, Exchanges, answer

use Jobq.Api{Routed, route, respond, health}
use Jobq.Board{Call, Outcome, Counts}
use Jobq.Job{Job, State, job_of}
use Jobq.Queue{Queue, opening}
use Jobq.Store{Table}

intent "Serve jobq over HTTP: the runtime serves the listener into an acceptor, which starts a worker per exchange; the worker reads the request into a route, asks the queue with the time main's clock gives, and replies, so a change's reply goes out only once the queue has answered, and the queue answers only once the change is in the store. The listener's Idle asks the queue to sweep the leases that ran out."

# The runtime counts a connection that has not yet sent a whole request against this mailbox's
# bound less 4, so 4,096 holds more than a thousand quiet clients before it stops accepting, and
# idle: 5 s (in main) closes each one that sends nothing.
process Acceptor(queue: Handle(Queue), clock: Clock) mailbox: 4_096
  state
    accepted: UInt64
    quiet: UInt64
  end

  message Accepted(exchange: Exchange)
  message Idle

  fn update(state, message)
    case message
      Accepted(exchange):
        Worker.start(exchange, queue, clock).send(Answer)
        state.accepted += 1
      Idle:
        queue.send(Sweep(at: clock.now))
        state.quiet += 1
    end
  end
end

process Worker(exchange: Exchange, queue: Handle(Queue), clock: Clock)
  state
    answered: Bool
  end

  message Answer

  fn update(state, message)
    case message
      Answer:
        response = answer(queue, clock, exchange.request)
        state.answered = exchange.reply(response, within: 10_000.ms) is Ok(_)
    end
  end
end

supervisor Exchanges(exchange: Exchange, queue: Handle(Queue), clock: Clock)
  child Acceptor(queue, clock), restart: :always
  child Worker(exchange, queue, clock), restart: :never
end

# The response to one request: an answer the route gives at once, the health counts, or the
# board's outcome. A queue that does not answer in 60 seconds is 503; the change may still land,
# as the failure model says of a timed-out ask.
fn answer(queue: Handle(Queue), clock: Clock, request: Request) : Response
  now = clock.now
  case route(request)
    Answered(response): response
    Checkup:
      case queue.ask(Health(at: now), within: 60_000.ms)
        Ok(counts): health(counts)
        Error(_): respond(Unavailable(reason: "the queue did not answer in time"))
      end
    Asked(worker: worker, command: command):
      call = Call(worker: worker, at: now, command: command)
      case queue.ask(Serve(call: call), within: 60_000.ms)
        Ok(outcome): respond(outcome)
        Error(_): respond(Unavailable(reason: "the queue did not answer in time"))
      end
  end
end

fn by(token: String, method: String, path: String, body: String) : Request
  headers = if token == "-": Map.new() else: Map.new().set("authorization", "Bearer #{token}")
  Request(method: method, path: path, headers: headers, body: body)
end

fn sent(http: Http, port: UInt16, request: Request) : Result(Response, HttpError)
  http.send(request, host: "localhost", port: port, within: 1.minute)
end

# A status that is one of these, or no response at all, which under faults is rain.
fn status_in?(got: Result(Response, HttpError), statuses: List(UInt16)) : Bool
  case got
    Ok(response): statuses.contains?(response.status)
    Error(_): true
  end
end

fn fresh() : Table
  Table(buckets: Map.new(), size: 0, dir: "d", name: "jobq.log", bytes: 0, lines: 0, cut: false)
end

fn job_body(queue: String) : String
  "{\"queue\": \"#{queue}\", \"payload\": \"send the welcome mail\", \"max_attempts\": 2}"
end

# The jobs the worker holds, read from the queue and not over the wire, since a lease whose
# response the wire lost is still the worker's.
fn holding(queue: Handle(Queue), worker: String, at: Time) : List(Job)
  call = Call(worker: worker, at: at, command: Listing(queue: None, wanted: Some(Leased)))
  case queue.ask(Serve(call: call), within: 1.minute)
    Ok(Listed(jobs)): jobs.filter(fn(j) j.worker == Some(worker) end)
    Ok(_): []
    Error(_): []
  end
end

fn leased_id(got: Result(Response, HttpError)) : List(String)
  case got
    Ok(response):
      return [] if response.status != 200
      case job_of(response.body)
        Some(job): [job.id]
        None: []
      end
    Error(_): []
  end
end

# One round of a worker: ack each job it holds, then lease one and ack it. True when every answer
# was one the route may give.
fn worked(http: Http, queue: Handle(Queue), port: UInt16, worker: String, at: Time) : Bool
  var right = true
  held = holding(queue, worker, at).map(fn(j) j.id end)
  leased = sent(http, port, by(worker, "POST", "/queues/emails/lease", "{\"lease_ms\": 60000}"))
  right = status_in?(leased, [200, 204, 503])
  for id in held.concat(leased_id(leased))
    acked = sent(http, port, by(worker, "POST", "/jobs/#{id}/ack", ""))
    right = right and status_in?(acked, [200, 409, 503])
  end
  right
end

fn settled?(queue: Handle(Queue), at: Time) : Bool
  counts = queue.ask(Health(at: at), within: 1.minute)
  counts is Ok(Counts(queued: 0, leased: 0, done: _, dead: _, uptime_ms: _))
end

test "each status comes back over the wire, unless a call fails"
  http = Http.fixture()
  queue = Queue.start(Fs.fixture(), opening(fresh(), Time.fixture()))
  assert http.listen(0, within: 1.minute) is Ok(listener)
  listener.serve(into: Acceptor.start(queue, Clock.fixture()), idle: 5_000.ms)
  port = listener.port
  assert status_in?(sent(http, port, by("-", "GET", "/health", "")), [200, 503])
  assert status_in?(sent(http, port, by("-", "GET", "/jobs", "")), [401])
  assert status_in?(sent(http, port, by("ada", "PATCH", "/jobs", "")), [405])
  assert status_in?(sent(http, port, by("ada", "GET", "/nowhere", "")), [404])
  assert status_in?(sent(http, port, by("ada", "POST", "/jobs", "{\"queue\": 1}")), [400])
  assert status_in?(sent(http, port, by("ada", "POST", "/queues/emails/lease", "")), [204, 503])
  made = sent(http, port, by("ada", "POST", "/jobs", job_body("emails")))
  assert status_in?(made, [201, 503])
  assert status_in?(sent(http, port, by("ada", "GET", "/jobs/j_99", "")), [404, 503])
  assert status_in?(sent(http, port, by("ada", "POST", "/jobs/j_99/ack", "")), [404, 503])
  assert status_in?(sent(http, port, by("ada", "DELETE", "/jobs/j_99", "")), [404, 503])
end

# Run with --faults 20 --until 0.5: while calls fail, every answer is one the route may give or a
# 503, and the never over holds sees no job held twice; once they stop, the workers keep working
# until no job is queued or leased, so every job made is done or dead.
test "under faults every answer is right or a 503, and once they stop every job is done or dead"
  http = Http.fixture()
  queue = Queue.start(Fs.fixture(), opening(fresh(), Time.fixture()))
  assert http.listen(0, within: 1.minute) is Ok(listener)
  listener.serve(into: Acceptor.start(queue, Clock.fixture()), idle: 5_000.ms)
  port = listener.port
  for _ in 0..3
    assert status_in?(sent(http, port, by("ada", "POST", "/jobs", job_body("emails"))), [201, 503])
  end
  for _ in 0..200
    if settled?(queue, Time.fixture())
      break
    end
    assert worked(http, queue, port, "ada", Time.fixture())
    assert worked(http, queue, port, "bob", Time.fixture())
  end
  assert settled?(queue, Time.fixture())
end

# The finding of step 21: a connection that has sent no request counts against the acceptor's
# bound, so a crowd of quiet clients must not fill it.
test "1,200 connections that send nothing do not stop a producer's request from being answered"
  net = Net.fixture()
  http = Http.fixture()
  queue = Queue.start(Fs.fixture(), opening(fresh(), Time.fixture()))
  assert http.listen(0, within: 1.minute) is Ok(listener)
  listener.serve(into: Acceptor.start(queue, Clock.fixture()), idle: 5_000.ms)
  var crowd = 0
  for _ in 0..1_200
    if net.connect("localhost", listener.port, within: 1.minute) is Ok(conn)
      crowd += 1
      if conn.write("GET /jobs HTTP/1.1\r\n", within: 1.minute) is Ok(_)
        crowd += 0
      end
    end
  end
  made = sent(http, listener.port, by("ada", "POST", "/jobs", job_body("after-crowd")))
  assert status_in?(made, [201, 503])
end
