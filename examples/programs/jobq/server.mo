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
    # body gone; regenerate
  end
end

# Answers one exchange and ends.
process Worker(exchange: Exchange, service: Handle(Service))
  state
    answered: Bool
  end

  message Answer

  fn update(state, message)
    # body gone; regenerate
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
  # body gone; regenerate
end

fn place() : Place
  # body gone; regenerate
end

fn sent(http: Http, port: UInt16, request: Request) : Result(Response, HttpError)
  # body gone; regenerate
end

fn by(worker: String, method: String, path: String, body: String) : Request
  # body gone; regenerate
end

fn status_in?(got: Result(Response, HttpError), statuses: List(UInt16)) : Bool
  # body gone; regenerate
end

# Every job the service holds, as it holds them, asked directly and not over the wire.
fn snapshot(service: Handle(Service)) : Option(List(Job))
  # body gone; regenerate
end

fn open_jobs(jobs: List(Job)) : List(Job)
  # body gone; regenerate
end

# One worker's turn over the wire: when the service shows it holding a job, whether or not its
# lease's response arrived, an ack, or a fail on an odd job's first attempt; otherwise a lease.
# Nothing when every response was right, and otherwise what was not.
fn turn(http: Http, service: Handle(Service), port: UInt16, n: UInt64) : String
  # body gone; regenerate
end

fn held_by_w?(job: Job) : Bool
  # body gone; regenerate
end

fn unknown() : Job
  # body gone; regenerate
end

fn settled(http: Http, service: Handle(Service), port: UInt16, held: Job, n: UInt64,
  before: List(Job)) : String
  # body gone; regenerate
end

# A response that is not a success: one of the statuses allowed, or a 503 that left every job as
# it was.
fn unchanged(response: Response, before: List(Job), after: Option(List(Job)),
  allowed: List(UInt16)) : String
  # body gone; regenerate
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
