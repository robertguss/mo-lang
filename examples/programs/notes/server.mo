module Notes.Server
expose Acceptor, Acceptors, Move, Checked, answer

use Notes.Api{Routed, route, respond, health}
use Notes.Note{Note, Outcome, Call, Command, note_of}
use Notes.Service{Service, opening}
use Notes.Store{Table}

intent "Serve notes over HTTP: the runtime serves the listener into an acceptor process, which reads each exchange's request into a route, asks the service, and replies; a change's reply goes out only once the service has answered, and the service answers only once the change's log line is on disk."

# Answers each exchange the runtime hands it itself, one at a time, as httpd does.
process Acceptor(service: Handle(Service))
  state
    answered: UInt64
    unsent: UInt64
    quiet: UInt64
  end

  message Accepted(exchange: Exchange)
  message Idle

  fn update(state, message)
    # body gone; regenerate
  end
end

supervisor Acceptors(service: Handle(Service))
  child Acceptor(service), restart: :always
end

# The response to one request: an answer the route gives at once, the health counts, or the
# service's outcome. A service that does not answer in 30 seconds, which is longer than its
# slowest change takes, is 503; the change may still land, as the failure model says of a
# timed-out ask.
fn answer(service: Handle(Service), request: Request) : Response
  # body gone; regenerate
end

# One step of a client's script against the server, over the wire.
enum Move
  Make(title: String)
  Read
  Rename(title: String)
  Drop
  Look
end

# After a move: the notes the client now holds, by id, as (id, title); a response that was
# not right; or an unknown the check cannot resolve.
enum Checked
  Next(held: List((String, String)))
  Wrong(why: String)
  Stopped
end

fn sent(http: Http, port: UInt16, request: Request) : Result(Response, HttpError)
  # body gone; regenerate
end

fn by(method: String, path: String, body: String) : Request
  # body gone; regenerate
end

fn draft(title: String) : String
  # body gone; regenerate
end

fn request_of(move: Move, held: List((String, String))) : Request
  # body gone; regenerate
end

# What the client holds after a response: the move applied when the response is the right one,
# the same notes after a 503, and Wrong for anything else.
fn after(move: Move, held: List((String, String)), response: Response) : Checked
  # body gone; regenerate
end

fn made(held: List((String, String)), response: Response, title: String) : Checked
  # body gone; regenerate
end

fn read_back(held: List((String, String)), response: Response) : Checked
  # body gone; regenerate
end

fn renamed(held: List((String, String)), response: Response, title: String) : Checked
  # body gone; regenerate
end

# What the service holds for the client, read by asking it and not over the wire.
fn holding(service: Handle(Service)) : Option(List((String, String)))
  # body gone; regenerate
end

# One move over the wire, checked against what the client held and against what the service
# holds. A request the wire lost may still reach the server later, as a timed-out call may
# still land, so nothing after it can be checked and the check stops there.
fn moved(http: Http, service: Handle(Service), port: UInt16, move: Move,
  held: List((String, String))) : Checked
  # body gone; regenerate
end

fn script() : List(Move)
  # body gone; regenerate
end

# Plays the script: nothing when every response was right, or a 503 that left the store as it
# was, and otherwise what was not.
fn unfaithful(http: Http, service: Handle(Service), port: UInt16) : String
  # body gone; regenerate
end

# An empty store over the log d/notes.log.
fn fresh() : Table
  # body gone; regenerate
end

fn status_in?(got: Result(Response, HttpError), statuses: List(UInt16)) : Bool
  # body gone; regenerate
end

test "every response over the wire is right, or a 503 that left the store as it was"
  http = Http.fixture()
  assert http.listen(0, within: 1.ms) is Ok(listener)
  service = Service.start(Fs.fixture(), Clock.fixture(), opening(fresh(), Time.fixture()))
  listener.serve(into: Acceptor.start(service), idle: 60_000.ms)
  assert unfaithful(http, service, listener.port) == ""
end

test "each status comes back over the wire, unless a call fails"
  http = Http.fixture()
  assert http.listen(0, within: 1.ms) is Ok(listener)
  service = Service.start(Fs.fixture(), Clock.fixture(), opening(fresh(), Time.fixture()))
  listener.serve(into: Acceptor.start(service), idle: 60_000.ms)
  port = listener.port
  assert status_in?(sent(http, port, Request(method: "GET", path: "/health")), [200])
  assert status_in?(sent(http, port, Request(method: "GET", path: "/notes")), [401])
  assert status_in?(sent(http, port, by("PATCH", "/notes", "")), [405])
  assert status_in?(sent(http, port, by("GET", "/nowhere", "")), [404])
  assert status_in?(sent(http, port, by("POST", "/notes", "{\"title\": 1}")), [400])
  assert status_in?(sent(http, port, by("POST", "/notes", draft("x"))), [201, 503])
  assert status_in?(sent(http, port, by("GET", "/notes/n_77", "")), [404])
  assert status_in?(sent(http, port, by("DELETE", "/notes/n_77", "")), [404])
end
