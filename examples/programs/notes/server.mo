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
    case message
      Accepted(exchange):
        if exchange.reply(answer(service, exchange.request), within: 10_000.ms) is Ok(_)
          state.answered += 1
        else
          state.unsent += 1
        end
      Idle:
        state.quiet += 1
    end
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
  case route(request)
    Answered(response): response
    Checkup:
      case service.ask(Health, within: 30_000.ms)
        Ok(counts): health(counts)
        Error(_): respond(Unavailable(reason: "the service did not answer in time"))
      end
    Asked(call):
      case service.ask(Serve(call: call), within: 30_000.ms)
        Ok(outcome): respond(outcome)
        Error(_): respond(Unavailable(reason: "the service did not answer in time"))
      end
  end
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
  http.send(request, host: "localhost", port: port, within: 1.minute)
end

fn by(method: String, path: String, body: String) : Request
  Request(method: method, path: path, headers: Map.new().set("authorization", "Bearer ada"),
    body: body)
end

fn draft(title: String) : String
  "{\"title\": \"#{title}\", \"body\": \"said over the wire\"}"
end

fn request_of(move: Move, held: List((String, String))) : Request
  first = (held.first or ("n_0", "")).0
  last = (held.last or ("n_0", "")).0
  case move
    Make(title): by("POST", "/notes", draft(title))
    Read: by("GET", "/notes/#{first}", "")
    Rename(title): by("PUT", "/notes/#{first}", draft(title))
    Drop: by("DELETE", "/notes/#{last}", "")
    Look: by("GET", "/notes", "")
  end
end

# What the client holds after a response: the move applied when the response is the right one,
# the same notes after a 503, and Wrong for anything else.
fn after(move: Move, held: List((String, String)), response: Response) : Checked
  if response.status == 503 and !(move is Read) and !(move is Look)
    return Next(held: held)
  end
  case move
    Make(title): made(held, response, title)
    Read: read_back(held, response)
    Rename(title): renamed(held, response, title)
    Drop:
      expected = if held.size == 0: 404 else: 204
      return Wrong(why: "DELETE gave #{response.status}") if response.status != expected
      Next(held: held.take(held.size.saturating_sub(1)))
    Look:
      return Wrong(why: "GET /notes gave #{response.status}") if response.status != 200
      Next(held: held)
  end
end

fn made(held: List((String, String)), response: Response, title: String) : Checked
  case note_of(response.body)
    Some(kept):
      return Wrong(why: "POST gave #{response.status}") if response.status != 201
      return Wrong(why: "POST made #{kept.title}") if kept.title != title
      Next(held: held.push((kept.id, kept.title)))
    None: Wrong(why: "POST gave #{response.status} #{response.body}")
  end
end

fn read_back(held: List((String, String)), response: Response) : Checked
  case held.first
    Some(first):
      return Wrong(why: "GET gave #{response.status}") if response.status != 200
      case note_of(response.body)
        Some(kept):
          return Wrong(why: "GET read #{kept.title}") if kept.title != first.1
          Next(held: held)
        None: Wrong(why: "GET gave #{response.body}")
      end
    None:
      return Wrong(why: "GET of nothing gave #{response.status}") if response.status != 404
      Next(held: held)
  end
end

fn renamed(held: List((String, String)), response: Response, title: String) : Checked
  case held.first
    Some(first):
      return Wrong(why: "PUT gave #{response.status}") if response.status != 200
      Next(held: [(first.0, title)].concat(held.drop(1)))
    None:
      return Wrong(why: "PUT of nothing gave #{response.status}") if response.status != 404
      Next(held: held)
  end
end

# What the service holds for the client, read by asking it and not over the wire.
fn holding(service: Handle(Service)) : Option(List((String, String)))
  call = Call(owner: "ada", command: Listing(prefix: ""))
  case service.ask(Serve(call: call), within: 1.minute)
    Ok(Listed(notes)): Some(notes.map(fn(n) (n.id, n.title) end))
    Ok(_): None
    Error(_): None
  end
end

# One move over the wire, checked against what the client held and against what the service
# holds. A request the wire lost may still reach the server later, as a timed-out call may
# still land, so nothing after it can be checked and the check stops there.
fn moved(http: Http, service: Handle(Service), port: UInt16, move: Move,
  held: List((String, String))) : Checked
  case sent(http, port, request_of(move, held))
    Ok(response):
      checked = after(move, held, response)
      if checked is Next(now)
        seen = holding(service)
        return Wrong(why: "after #{response.status} the store holds #{seen} but the answers say #{now}") if seen != Some(now)
      end
      checked
    Error(_): Stopped
  end
end

fn script() : List(Move)
  [Make(title: "one"),
    Make(title: "two"),
    Read,
    Rename(title: "uno"),
    Look,
    Drop,
    Make(title: "three"),
    Read,
    Drop,
    Drop,
    Read,
    Rename(title: "none left"),
    Make(title: "four")]
end

# Plays the script: nothing when every response was right, or a 503 that left the store as it
# was, and otherwise what was not.
fn unfaithful(http: Http, service: Handle(Service), port: UInt16) : String
  var held = [("", "")].take(0)
  for move in script()
    case moved(http, service, port, move, held)
      Next(now):
        held = now
      Wrong(why):
        return why
      Stopped:
        return ""
    end
  end
  ""
end

# An empty store over the log d/notes.log.
fn fresh() : Table
  Table(buckets: Map.new(), size: 0, dir: "d", name: "notes.log", bytes: 0, lines: 0, cut: false)
end

fn status_in?(got: Result(Response, HttpError), statuses: List(UInt16)) : Bool
  case got
    Ok(response): statuses.contains?(response.status)
    Error(_): true
  end
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

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs)
          proven: not run
