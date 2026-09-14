# run: 2000
module Workers.Main
expose Worker, Acceptor, Exchanges, answer, main

intent "Serve HTTP on 127.0.0.1 with a worker process per exchange, the shape of effects/http.mo, and send it as many requests as the first argument says, one at a time: a worker that has answered is freed, so the count does not change the memory the program needs."

process Worker(exchange: Exchange)
  state
    answered: Bool
  end

  message Answer

  fn update(state, message)
    case message
      Answer:
        state.answered = exchange.reply(answer(exchange.request), within: 5_000.ms) is Ok(_)
    end
  end
end

process Acceptor()
  state
    accepted: UInt64
    quiet: UInt64
  end

  message Accepted(exchange: Exchange)
  message Idle

  fn update(state, message)
    case message
      Accepted(exchange):
        Worker.start(exchange).send(Answer)
        state.accepted += 1
      Idle:
        state.quiet += 1
    end
  end
end

supervisor Exchanges(exchange: Exchange)
  child Acceptor, restart: :always
  child Worker(exchange), restart: :always
end

fn answer(request: Request) : Response
  Response(status: 200, body: "hello, #{request.query.get("n") or "nobody"}")
end

fn answered?(got: Result(Response, HttpError), n: UInt64) : Bool
  case got
    Ok(response): response.body == "hello, #{n}"
    Error(_): false
  end
end

fn served(http: Http, port: UInt16, requests: UInt64) : UInt64
  var answered = 0
  for n in 0..requests
    request = Request(method: "GET", path: "/hello", query: Map.new().set("n", "#{n}"))
    if answered?(http.send(request, host: "127.0.0.1", port: port, within: 5_000.ms), n)
      answered += 1
    end
  end
  answered
end

fn main(platform: Platform)
  requests = (platform.args.first or "1000").to_u64 or 1000
  case platform.http.listen(0, within: 5_000.ms)
    Ok(listener):
      listener.serve(into: Acceptor.start(), idle: 5_000.ms)
      answered = served(platform.http, listener.port, requests)
      platform.stdout.write_line("#{answered} of #{requests} requests answered, each by a worker of its own")
      # The listener would be served on, so the program ends here.
      platform.exit(0)
    Error(e):
      platform.stderr.write_line("workers failed: #{e}")
      platform.exit(1)
  end
end

test "a worker answers with the n its request's query gives"
  named = Request(method: "GET", path: "/hello", query: Map.new().set("n", "7"))
  assert answer(named) == Response(status: 200, body: "hello, 7")
  assert answered?(Ok(answer(named)), 7)
  assert !answered?(Ok(answer(Request(method: "GET", path: "/hello"))), 7)
end

verified: types, contracts, tests (1), property (0 seeds), sim (not run)
          proven: not run
