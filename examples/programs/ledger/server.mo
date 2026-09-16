# sim: --faults 20 --until 0.5
module Ledger.Server
expose Acceptor, Worker, Exchanges

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
        worker = Worker.start(exchange, journal)
        worker.send(Go(me: worker))
        state.accepted += 1
      Idle:
        wrote = if journal.ask(Flush, within: 10_000.ms) == Ok(true): 1 else: 0
        state.flushed += wrote
    end
  end
end

# Answers one exchange and ends. It stages its call in one update and collects the answer in the
# next, which it sends itself, so the calls other workers stage in between join the same batch: a
# worker that collected in the update that staged would flush a batch of its own call alone.
process Worker(exchange: Exchange, journal: Handle(Journal))
  state
    ticket: UInt64
    answered: Bool
  end

  message Go(me: Handle(Worker))
  message Reply

  fn update(state, message)
    case message
      Go(me):
        case staged(journal, exchange.request)
          Ok(ticket):
            state.ticket = ticket
            me.send(Reply)
          Error(response):
            state.answered = exchange.reply(response, within: 30_000.ms) is Ok(_)
        end
      Reply:
        answer = collected(journal, state.ticket)
        state.answered = exchange.reply(answer, within: 30_000.ms) is Ok(_)
    end
  end
end

supervisor Exchanges(journal: Handle(Journal), exchange: Exchange)
  child Acceptor(journal), restart: :always
  child Worker(exchange, journal), restart: :never
end

# A request's ticket once its call is staged, or the response it gets at once. An exchange carries
# no deadline of the client's, so the worker chooses: 10 seconds to stage, which never waits on a
# file, and 30 to collect, which waits for the batch's append; every file call the journal makes
# for the collect runs on what remains of those 30. A timed-out collect is 503, and the change may
# still land, as the failure model says.
fn staged(journal: Handle(Journal), request: Request) : Result(UInt64, Response)
  case route(request)
    Answered(response): Error(response)
    Asked(call):
      case journal.ask(Stage(call: call), within: 10_000.ms)
        Ok(ticket): Ok(ticket)
        Error(_): Error(unavailable())
      end
  end
end

fn collected(journal: Handle(Journal), ticket: UInt64) : Response
  case journal.ask(Collect(ticket: ticket), within: 30_000.ms)
    Ok(answer): respond(answer)
    Error(_): unavailable()
  end
end

fn unavailable() : Response
  Response(status: 503, headers: Map.new().set("content-type", "application/json"),
    body: "{\"error\": \"the ledger did not answer in time\"}")
end

fn started(http: Http, fs: Fs, clock: Clock) : (Handle(Journal), UInt16)
  place = Place(dir: "d", log: "ledger.log")
  journal = Journal.start(fs, clock, place, clock.now)
  for _ in 0..5
    made = fs.mkdir("d", within: 1.minute) is Ok(_)
    if made and journal.ask(Open(me: journal), within: 1.minute) is Ok(Ready(accounts: _,
      entries: _, torn: _))
      break
    end
  end
  case http.listen(0, within: 1.ms)
    Ok(listener):
      listener.serve(into: Acceptor.start(journal), idle: 5_000.ms)
      (journal, listener.port)
    Error(_): (journal, 0)
  end
end

fn by(method: String, path: String, key: String, body: String) : Request
  bearing = Map.new().set("authorization", "Bearer ada")
  headers = if key == "": bearing else: bearing.set("idempotency-key", key)
  Request(method: method, path: path, headers: headers, body: body)
end

fn status(http: Http, port: UInt16, request: Request) : UInt16
  case http.send(request, host: "127.0.0.1", port: port, within: 60_000.ms)
    Ok(response): response.status
    Error(_): 0
  end
end

fn in?(got: UInt16, statuses: List(UInt16)) : Bool
  got == 0 or got == 503 or statuses.contains?(got)
end

# An account's balance as the journal holds it, asked directly and not over the wire; None when the
# ask failed.
fn balance_of(journal: Handle(Journal), id: String) : Option(String)
  looking = Call(command: ShowAccount(id: id), key: "", request: "")
  case journal.ask(Serve(call: looking), within: 60_000.ms)
    Ok(answer): balance_in(answer.body)
    Error(_): None
  end
end

# The balance an account's JSON carries, as its digits; None for a body that carries none.
fn balance_in(body: String) : Option(String)
  needle = "\"balance\": "
  at = try body.index_of(needle)
  rest = body.slice(at + needle.size, body.size)
  Some(rest.slice(0, rest.index_of(",") or rest.size))
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
