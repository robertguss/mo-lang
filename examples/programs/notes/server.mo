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
        response = answer(service, exchange.request)
        replied = exchange.reply(response, within: 30_000.ms) is Ok(_)
        if replied
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
  http.send(request, host: "127.0.0.1", port: port, within: 1.minute)
end

fn by(method: String, path: String, body: String) : Request
  Request(method: method, path: path, headers: Map.new().set("authorization", "Bearer ada"),
    body: body)
end

fn draft(title: String) : String
  "{\"title\": #{Json.encode(title)}, \"body\": \"\"}"
end

fn request_of(move: Move, held: List((String, String))) : Request
  case move
    Make(title): by("POST", "/notes", draft(title))
    Read: by("GET", "/notes/#{first_id(held)}", "")
    Rename(title): by("PUT", "/notes/#{first_id(held)}", draft(title))
    Drop: by("DELETE", "/notes/#{first_id(held)}", "")
    Look: by("GET", "/notes", "")
  end
end

# The id of the note a move works on: the lowest the client holds, or one no client holds.
fn first_id(held: List((String, String))) : String
  case held.first
    Some(first): first.0
    None: "n_0"
  end
end

# What the client holds after a response: the move applied when the response is the right one,
# the same notes after a 503, and Wrong for anything else.
fn after(move: Move, held: List((String, String)), response: Response) : Checked
  return Next(held: held) if response.status == 503
  case move
    Make(title): made(held, response, title)
    Read: read_back(held, response)
    Rename(title): renamed(held, response, title)
    Drop: let_go(held, response)
    Look: looked_over(held, response)
  end
end

fn made(held: List((String, String)), response: Response, title: String) : Checked
  return Wrong(why: "a create answered #{response.status}") if response.status != 201
  case note_of(response.body)
    Some(kept):
      return Wrong(why: "a create gave back the title #{kept.title}") if kept.title != title
      Next(held: held.push((kept.id, title)))
    None: Wrong(why: "a create gave back no note")
  end
end

fn read_back(held: List((String, String)), response: Response) : Checked
  case held.first
    Some(first):
      return Wrong(why: "a read answered #{response.status}") if response.status != 200
      case note_of(response.body)
        Some(kept):
          return Wrong(why: "a read gave back #{kept.id}, not #{first.0}") if kept.id != first.0
          return Wrong(why: "a read gave back the title #{kept.title}") if kept.title != first.1
          Next(held: held)
        None: Wrong(why: "a read gave back no note")
      end
    None:
      return Next(held: held) if response.status == 404
      Wrong(why: "a read of a note no client holds answered #{response.status}")
  end
end

fn renamed(held: List((String, String)), response: Response, title: String) : Checked
  case held.first
    Some(first):
      return Wrong(why: "a rename answered #{response.status}") if response.status != 200
      case note_of(response.body)
        Some(kept):
          return Wrong(why: "a rename gave back the title #{kept.title}") if kept.title != title
          Next(held: [(first.0, title)].concat(held.drop(1)))
        None: Wrong(why: "a rename gave back no note")
      end
    None:
      return Next(held: held) if response.status == 404
      Wrong(why: "a rename of a note no client holds answered #{response.status}")
  end
end

fn let_go(held: List((String, String)), response: Response) : Checked
  case held.first
    Some(_):
      return Wrong(why: "a delete answered #{response.status}") if response.status != 204
      Next(held: held.drop(1))
    None:
      return Next(held: held) if response.status == 404
      Wrong(why: "a delete of a note no client holds answered #{response.status}")
  end
end

fn looked_over(held: List((String, String)), response: Response) : Checked
  return Wrong(why: "a list answered #{response.status}") if response.status != 200
  Next(held: held)
end

# What the service holds for the client, read by asking it and not over the wire.
fn holding(service: Handle(Service)) : Option(List((String, String)))
  case service.ask(Serve(call: Call(owner: "ada", command: Listing(prefix: ""))),
    within: 1.minute)
    Ok(Listed(notes)): Some(notes.map(fn(kept) (kept.id, kept.title) end))
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
      case after(move, held, response)
        Next(now):
          case holding(service)
            Some(kept):
              return Next(held: now) if kept == now
              Wrong(why: "the service holds #{kept.size} notes, not the #{now.size} it answered")
            None: Stopped
          end
        Wrong(reason): Wrong(why: reason)
        Stopped: Stopped
      end
    Error(_): Stopped
  end
end

fn script() : List(Move)
  [Make(title: "one"), Look, Read, Rename(title: "two"), Read, Make(title: "three"), Look, Drop,
    Read, Look]
end

fn kept_of(step: Checked, held: List((String, String))) : List((String, String))
  case step
    Next(now): now
    Wrong(_) | Stopped: held
  end
end

fn why_of(step: Checked, wrong: String) : String
  case step
    Wrong(reason): reason
    Next(_) | Stopped: wrong
  end
end

# Plays the script: nothing when every response was right, or a 503 that left the store as it
# was, and otherwise what was not.
fn unfaithful(http: Http, service: Handle(Service), port: UInt16) : String
  var held = [("", "")].take(0)
  var wrong = ""
  var going = true
  for move in script()
    if going
      step = moved(http, service, port, move, held)
      held = kept_of(step, held)
      wrong = why_of(step, wrong)
      going = step is Next(_)
    end
  end
  wrong
end

# An empty store over the log d/notes.log.
fn fresh() : Table
  Table(buckets: Map.new(), size: 0, dir: "d", name: "notes.log", bytes: 0, lines: 0,
    cut: false)
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

verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run
