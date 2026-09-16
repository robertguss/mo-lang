# sim: --faults 20 --until 0.5
module Jobq.Server
expose Acceptor, Worker, Exchanges, answer

use Jobq.Api{Routed, route, respond, health}
use Jobq.Books{Place}
use Jobq.Job{Job, State, id_of, shown}
use Jobq.Moves{Call, Command, Outcome}
use Jobq.Queue{Service}

intent "Serve jobq over HTTP: the runtime serves the listener into an acceptor, which starts a worker per exchange and turns the listener's Idle into an ask for a sweep of the leases run out; a worker reads its request into a route, asks the queue service, and replies, so a change's reply goes out only once the service has answered, which it does only once the change is in the log."

# The mailbox is 4,096, not the default 1,000: the runtime counts connections that have sent no
# whole request against it, so 1,200 silent clients would otherwise stop the accepting until
# idle closes them.
# Idle comes only when no client came for a while, so the acceptor can wait for the sweep: 10
# seconds, which bounds every file call the sweep makes.
process Acceptor(service: Handle(Service)) mailbox: 4_096
  state
    accepted: UInt64
    quiet: UInt64
    ended: UInt64
  end

  message Accepted(exchange: Exchange)
  message Idle

  fn update(state, message)
    case message
      Accepted(exchange):
        worker = Worker.start(exchange, service)
        worker.send(Answer)
        state.accepted += 1
      Idle:
        state.quiet += 1
        state.ended = state.ended + ended_by(service)
    end
  end
end

# Answers one exchange and ends.
process Worker(exchange: Exchange, service: Handle(Service))
  state
    answered: Bool
  end

  message Answer

  fn update(state, message)
    case message
      Answer:
        response = answer(service, exchange.request)
        state.answered = exchange.reply(response, within: 30_000.ms) is Ok(_)
    end
  end
end

supervisor Exchanges(exchange: Exchange, service: Handle(Service))
  child Acceptor(service), restart: :always
  child Worker(exchange, service), restart: :never
end

# The response to one request. The ask waits 60 seconds, and every file call the service makes
# for it waits only on what remains of them, so a service that could not write in time answers
# 503 itself; a timed-out ask is 503 too, and the change may still land, as the failure model
# says.
fn answer(service: Handle(Service), request: Request) : Response
  case route(request)
    Answered(response): response
    Checkup:
      case service.ask(Tally, within: 60_000.ms)
        Ok(counts): health(counts)
        Error(_): respond(Unavailable(reason: "the service did not answer in time"))
      end
    Asked(call):
      case service.ask(Serve(call: call), within: 60_000.ms)
        Ok(outcome): respond(outcome)
        Error(_): respond(Unavailable(reason: "the service did not answer in time"))
      end
  end
end

fn ended_by(service: Handle(Service)) : UInt64
  case service.ask(Sweep, within: 10_000.ms)
    Ok(ended): ended
    Error(_): 0
  end
end

fn tried(jobs: List(Job)) : List((UInt64, UInt64))
  jobs.map(fn(one) (one.number, one.attempts) end)
end

fn place() : Place
  Place(dir: "d", log: "jobq.log")
end

fn sent(http: Http, port: UInt16, request: Request) : Result(Response, HttpError)
  http.send(request, host: "127.0.0.1", port: port, within: 1.minute)
end

fn by(worker: String, method: String, path: String, body: String) : Request
  Request(method: method, path: path, headers: Map.new().set("authorization", "Bearer #{worker}"),
    body: body)
end

fn status_in?(got: Result(Response, HttpError), statuses: List(UInt16)) : Bool
  case got
    Ok(response): statuses.contains?(response.status)
    Error(_): true
  end
end

# Every job the service holds, as it holds them, asked directly and not over the wire.
fn snapshot(service: Handle(Service)) : Option(List(Job))
  looking = Call(worker: "check", command: Listing(queue: None, status: None))
  case service.ask(Serve(call: looking), within: 60_000.ms)
    Ok(Listed(jobs)): Some(jobs)
    Ok(_): None
    Error(_): None
  end
end

fn open_jobs(jobs: List(Job)) : List(Job)
  jobs.filter(fn(one) one.state != Done and one.state != Dead end)
end

# One worker's turn over the wire: when the service shows it holding a job, whether or not its
# lease's response arrived, an ack, or a fail on an odd job's first attempt; otherwise a lease.
# Nothing when every response was right, and otherwise what was not.
fn turn(http: Http, service: Handle(Service), port: UInt16, n: UInt64) : String
  case snapshot(service)
    Some(before):
      case before.find(fn(one) held_by_w?(one) end)
        Some(held): settled(http, service, port, held, n, before)
        None: took(http, service, port, before)
      end
    None: ""
  end
end

# A lease over the wire, and what was not right about its answer: a lease the service could not
# show beforehand is no evidence, so a turn with no snapshot says nothing.
fn took(http: Http, service: Handle(Service), port: UInt16, before: List(Job)) : String
  case sent(http, port, by("w", "POST", "/queues/q/lease", "{\"lease_ms\": 60000}"))
    Ok(response):
      return "" if response.status == 200 or response.status == 204
      unchanged(response, before, snapshot(service), [503])
    Error(_): ""
  end
end

fn held_by_w?(job: Job) : Bool
  job.state == Leased and job.worker == Some("w")
end

fn unknown() : Job
  Job(number: 0, queue: "q", state: Queued, payload: "", attempts: 0, max_attempts: 1,
    created_at: Time.from_parts(2026, 1, 1, 0, 0, 0),
    updated_at: Time.from_parts(2026, 1, 1, 0, 0, 0), worker: None, lease_until: None, reason: None)
end

fn settled(http: Http, service: Handle(Service), port: UInt16, held: Job, n: UInt64,
  before: List(Job)) : String
  giving_up = held.number % 2 == 1 and held.attempts == 1
  verb = if giving_up: "fail" else: "ack"
  body = if giving_up: "{\"reason\": \"turn #{n}\"}" else: ""
  case sent(http, port, by("w", "POST", "/jobs/#{id_of(held.number)}/#{verb}", body))
    Ok(response):
      return "" if response.status == 200
      unchanged(response, before, snapshot(service), [409, 503])
    Error(_): ""
  end
end

# A response that is not a success: one of the statuses allowed, or a 503 that left every job as
# it was.
fn unchanged(response: Response, before: List(Job), after: Option(List(Job)),
  allowed: List(UInt16)) : String
  return "status #{response.status} is not one of #{allowed}" if !allowed.contains?(response.status)
  return "" if response.status != 503
  case after
    Some(jobs): if tried(jobs) == tried(before): "" else: "a 503 changed the jobs"
    None: ""
  end
end

test "each status comes back over the wire, unless a call fails"
  http = Http.fixture()
  assert http.listen(0, within: 1.ms) is Ok(listener)
  fs = Fs.fixture()
  made = fs.mkdir("d", within: 1.minute) is Ok(_)
  service = Service.start(fs, Clock.fixture(), place(), Time.fixture())
  assert made or snapshot(service) is None
  listener.serve(into: Acceptor.start(service), idle: 5_000.ms)
  port = listener.port
  job = "{\"queue\": \"q\", \"payload\": \"p\", \"max_attempts\": 1}"
  assert status_in?(sent(http, port, Request(method: "GET", path: "/health")), [200, 503])
  assert status_in?(sent(http, port, Request(method: "GET", path: "/jobs")), [401])
  assert status_in?(sent(http, port, by("w", "PATCH", "/jobs", "")), [405])
  assert status_in?(sent(http, port, by("w", "GET", "/nowhere", "")), [404])
  assert status_in?(sent(http, port, by("w", "POST", "/jobs", "{\"queue\": 1}")), [400])
  assert status_in?(sent(http, port, by("w", "POST", "/jobs", job)), [201, 503])
  assert status_in?(sent(http, port, by("w", "GET", "/jobs/j_77", "")), [404, 503])
  assert status_in?(sent(http, port, by("w", "POST", "/jobs/j_77/ack", "")), [404, 503])
  assert status_in?(sent(http, port, by("w", "POST", "/queues/empty/lease", "")), [204, 503])
end

# Run with --faults 20 --until 0.5: while fixture calls fail, every response is right or a 503
# that changed nothing, and no job is ever held twice (the nevers); once they stop, the worker
# ends every job done or dead.
test "under faults every answer is right or a 503 that changed nothing, and after them every job ends"
  http = Http.fixture()
  assert http.listen(0, within: 1.ms) is Ok(listener)
  fs = Fs.fixture()
  made = fs.mkdir("d", within: 1.minute) is Ok(_)
  service = Service.start(fs, Clock.fixture(), place(), Time.fixture())
  assert made or snapshot(service) is None
  listener.serve(into: Acceptor.start(service), idle: 5_000.ms)
  port = listener.port
  for i in 0..4
    body = "{\"queue\": \"q\", \"payload\": \"job #{i}\", \"max_attempts\": 2}"
    assert status_in?(sent(http, port, by("p", "POST", "/jobs", body)), [201, 503])
  end
  for n in 0..40
    if open_jobs(snapshot(service) or [unknown()]).size == 0
      break
    end
    assert turn(http, service, port, n) == ""
  end
  assert open_jobs(snapshot(service) or []) == []
end

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs)
          proven: not run
