module Processes.HeldSend
expose Worker, Acceptor, Acceptors, handed, fetched, hello?, requested

intent "An acceptor that hands each exchange to a worker of its own must end its update to let the worker answer, since the sends of an update are held until it ends: one accept per message serves, and a second accept in the same update waits for a client the held worker is keeping waiting, which the runtime crashes with a report naming the held send instead of hanging."

process Worker(exchange: Exchange)
  state
    answered: Bool
  end

  message Answer

  fn update(state, message)
    case message
      Answer:
        state.answered = exchange.reply(Response(status: 200, body: "hello"),
          within: 1.minute) is Ok(_)
    end
  end
end

process Acceptor(listener: HttpListener)
  state
    accepted: UInt64
  end

  message Serve
  message ServeFour

  # Four accepts in one update, so a seeded run whose faults time one out still reaches a
  # second after a first that handed its exchange on.
  fn update(state, message)
    case message
      Serve:
        state.accepted += handed(listener)
      ServeFour:
        state.accepted += handed(listener)
        state.accepted += handed(listener)
        state.accepted += handed(listener)
        state.accepted += handed(listener)
    end
  end
end

supervisor Acceptors(listener: HttpListener, exchange: Exchange)
  child Acceptor(listener), restart: :always
  child Worker(exchange), restart: :always
end

# The next exchange, handed to a worker of its own: 1, or 0 when none came.
fn handed(listener: HttpListener) : UInt64
  if listener.accept(within: 1.minute) is Ok(exchange)
    Worker.start(exchange).send(Answer)
    return 1
  end
  0
end

fn fetched(http: Http, acceptor: Handle(Acceptor), port: UInt16) : Result(Response, HttpError)
  acceptor.send(Serve)
  http.send(Request(method: "GET", path: "/"), host: "localhost", port: port, within: 1.minute)
end

fn hello?(got: Result(Response, HttpError)) : Bool
  case got
    Ok(response): response.status == 200 and response.body == "hello"
    Error(_): true
  end
end

fn requested(http: Http, port: UInt16) : Bool
  http.send(Request(method: "GET", path: "/"), host: "localhost", port: port,
    within: 1.minute) is Ok(_)
end

test "one accept in an update: the worker answers once the update ends, unless a call fails and says so"
  http = Http.fixture()
  assert http.listen(0, within: 1.ms) is Ok(listener)
  acceptor = Acceptor.start(listener)
  assert hello?(fetched(http, acceptor, listener.port))
end

test rejects "a second accept in the same update waits on a client its held send to the worker keeps waiting"
  http = Http.fixture()
  assert http.listen(0, within: 1.ms) is Ok(listener)
  var unanswered = 0
  for _ in 0..5
    if !requested(http, listener.port)
      unanswered += 1
    end
  end
  assert unanswered == 5
  acceptor = Acceptor.start(listener)
  acceptor.send(ServeFour)
end

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs)
          proven: not run
