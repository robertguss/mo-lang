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
    # body gone; regenerate
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
    # body gone; regenerate
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
  # body gone; regenerate
end

fn collected(journal: Handle(Journal), ticket: UInt64) : Response
  # body gone; regenerate
end

fn unavailable() : Response
  # body gone; regenerate
end

fn started(http: Http, fs: Fs, clock: Clock) : (Handle(Journal), UInt16)
  # body gone; regenerate
end

fn by(method: String, path: String, key: String, body: String) : Request
  # body gone; regenerate
end

fn status(http: Http, port: UInt16, request: Request) : UInt16
  # body gone; regenerate
end

fn in?(got: UInt16, statuses: List(UInt16)) : Bool
  # body gone; regenerate
end

# An account's balance as the journal holds it, asked directly and not over the wire; None when the
# ask failed.
fn balance_of(journal: Handle(Journal), id: String) : Option(String)
  # body gone; regenerate
end

fn transfer_body(amount: UInt64) : String
  # body gone; regenerate
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
