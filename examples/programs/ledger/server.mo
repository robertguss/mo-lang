# sim: --faults 20 --until 0.5
module Ledger.Server
expose Acceptor, Worker, Exchanges, answer

use Ledger.Api{Routed, route, respond}
use Ledger.Journal{Journal, Readiness}
use Ledger.Records{Place}
use Ledger.Teller{Command, Call, Answer}

intent "Serve the ledger over HTTP: the runtime serves the listener into an acceptor, which starts a worker per exchange and turns each quiet spell into a flush; a worker reads its request into a route and, for a call, stages it with the journal and collects its answer, which the journal hands out only once the batch holding it is on disk, so a response is written only after its entry is durable."

# The mailbox is 4,096: the runtime counts connections that have sent no whole request against it.
# Idle asks the journal to write what an Expire staged; nothing waits on that flush but the
# acceptor, so it waits 10 seconds.
process Acceptor(journal: Handle(Journal)) mailbox: 4_096
  state
    accepted: UInt64
    flushed: UInt64
  end

  message Accepted(exchange: Exchange)
  message Idle

  fn update(state, message)
    case message
      Accepted(exchange):
        Worker.start(exchange, journal).send(Go)
        state.accepted += 1
      Idle:
        if journal.ask(Flush, within: 10_000.ms) == Ok(true)
          state.flushed += 1
        end
    end
  end
end

# Answers one exchange and ends.
process Worker(exchange: Exchange, journal: Handle(Journal))
  state
    answered: Bool
  end

  message Go

  fn update(state, message)
    case message
      Go:
        response = answer(journal, exchange.request)
        state.answered = exchange.reply(response, within: 10_000.ms) is Ok(_)
    end
  end
end

supervisor Exchanges(journal: Handle(Journal), exchange: Exchange)
  child Acceptor(journal), restart: :always
  child Worker(exchange, journal), restart: :never
end

# The response to one request. An exchange carries no deadline of the client's, so the worker
# chooses: 10 seconds to stage, which never waits on a file, and 30 to collect, which waits for the
# batch's append; every file call the journal makes for the collect runs on what remains of those
# 30. A timed-out collect is 503, and the change may still land, as the failure model says.
fn answer(journal: Handle(Journal), request: Request) : Response
  case route(request)
    Answered(response): response
    Asked(call):
      case journal.ask(Stage(call: call), within: 10_000.ms)
        Ok(ticket):
          case journal.ask(Collect(ticket: ticket), within: 30_000.ms)
            Ok(answered): respond(answered)
            Error(_): unavailable()
          end
        Error(_): unavailable()
      end
  end
end

fn unavailable() : Response
  respond(Answer(status: 503, body: "{\"error\": \"the ledger did not answer in time\"}"))
end

fn started(http: Http, fs: Fs, clock: Clock) : (Handle(Journal), UInt16)
  made = fs.mkdir("d", within: 1.minute) is Ok(_)
  journal = Journal.start(fs, clock, Place(dir: "d", log: "ledger.log"), clock.now)
  opened = made and journal.ask(Open(me: journal),
    within: 1.minute) is Ok(Ready(accounts: _, entries: _, torn: _))
  case http.listen(0, within: 1.minute)
    Ok(listener):
      listener.serve(into: Acceptor.start(journal), idle: 5_000.ms)
      (journal, if opened: listener.port else: 0)
    Error(_): (journal, 0)
  end
end

fn by(method: String, path: String, key: String, body: String) : Request
  headers = Map.new().set("authorization", "Bearer ada").set("idempotency-key", key)
  Request(method: method, path: path, headers: headers, body: body)
end

fn status(http: Http, port: UInt16, request: Request) : UInt16
  case http.send(request, host: "localhost", port: port, within: 1.minute)
    Ok(response): response.status
    Error(_): 0
  end
end

fn in?(got: UInt16, statuses: List(UInt16)) : Bool
  statuses.push(0).push(503).contains?(got)
end

# An account's balance as the journal holds it, asked directly and not over the wire; None when the
# ask failed.
fn balance_of(journal: Handle(Journal), id: String) : Option(String)
  shown = Call(command: ShowAccount(id: id), key: "", request: "")
  case journal.ask(Serve(call: shown), within: 1.minute)
    Ok(Answer(status: 200, body: body)):
      at = body.index_of("\"balance\": ") or 0
      rest = body.slice(at + 11, body.size)
      Some(rest.slice(0, rest.index_of(",") or 0))
    Ok(_) | Error(_): None
  end
end

fn transfer_body(amount: UInt64) : String
  "{\"from\": \"a_1\", \"to\": \"a_2\", \"amount\": #{amount}}"
end

test "each status comes back over the wire, unless a call fails"
  http = Http.fixture()
  up = started(http, Fs.fixture(), Clock.fixture())
  port = up.1
  if port != 0
    assert in?(status(http, port, Request(method: "GET", path: "/health")), [200])
    assert in?(status(http, port, Request(method: "GET", path: "/accounts/a_1")), [401])
    assert in?(status(http, port, by("PATCH", "/transfers", "k", "")), [405])
    assert in?(status(http, port, by("GET", "/nowhere", "k", "")), [404])
    assert in?(status(http, port, by("POST", "/transfers", "k", "{\"amount\": 1}")), [400])
    ada = by("POST", "/accounts", "o1", "{\"name\": \"ada\", \"currency\": \"USD\"}")
    assert in?(status(http, port, ada), [201])
    assert in?(status(http, port, by("GET", "/accounts/a_9", "", "")), [404])
    assert in?(status(http, port, by("POST", "/transfers", "t", transfer_body(5))), [422, 404])
  end
end

# Run with --faults 20 --until 0.5: while fixture calls fail, a transfer answered 503 moved nothing
# and one answered 201 moved its amount once; each is retried under its key until it is 201, and
# once faults stop every one of them has landed exactly once.
test "under faults every transfer is right or a 503 that moved nothing, and each key lands once"
  http = Http.fixture()
  up = started(http, Fs.fixture(), Clock.fixture())
  journal = up.0
  port = up.1
  opened = [by("POST", "/accounts", "o1",
    "{\"name\": \"ada\", \"currency\": \"USD\", \"overdraft\": 100000}"),
    by("POST", "/accounts", "o2", "{\"name\": \"grace\", \"currency\": \"USD\"}")]
  var ready = port != 0
  for request in opened
    for _ in 0..40
      got = status(http, port, request)
      if got == 201
        break
      end
    end
  end
  ready = ready and balance_of(journal, "a_2") is Some(_)
  var landed = 0
  for i in 0..8
    request = by("POST", "/transfers", "t#{i}", transfer_body(100))
    for _ in 0..40
      if !ready
        break
      end
      before = balance_of(journal, "a_2")
      got = status(http, port, request)
      after = balance_of(journal, "a_2")
      if got == 503 and before is Some(b) and after is Some(a)
        assert a == b
      end
      if got == 201
        landed += 1
        break
      end
    end
  end
  if ready
    assert landed == 8 and balance_of(journal, "a_2") == Some("800")
  end
end

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs)
          proven: not run
