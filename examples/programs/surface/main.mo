# run: 1
module Surface.Main
expose Tally, Tallies, asked, main

use Surface.Wire{spelled}

intent "Ask a program's own runtime surface over HTTP: main starts a tally, then sends the surface at the port it is given a GET of the processes, a state, the recent events, a message to deliver, and a route that does not exist, printing what each answer says; with nothing listening at the port, each says so."

process Tally()
  state
    votes: UInt64
  end

  message Vote(n: UInt64)
  message Total : UInt64

  fn update(state, message)
    case message
      Vote(n):
        state.votes += n
      Total: state.votes
    end
  end
end

supervisor Tallies
  child Tally, restart: :always
end

# One request to the surface at `port`: its status and body, or that nothing answered.
fn asked(http: Http, port: UInt16, method: String, path: String, body: String) : Result(Response,
  String)
  case http.send(Request(method: method, path: path, body: body), host: "127.0.0.1", port: port,
    within: 5_000.ms)
    Ok(response): Ok(response)
    Error(_): Error("the surface at 127.0.0.1:#{port} did not answer #{method} #{path}")
  end
end

# What an answer says, in words that are the same in both runtimes.
fn said(got: Result(Response, String), expect: String) : String
  case got
    Ok(response):
      found = if response.body.contains?(expect)
        "holds #{expect}"
      else
        "does not hold #{expect}"
      end
      "#{response.status}, #{found}"
    Error(why): why
  end
end

fn main(platform: Platform)
  out = platform.stdout
  port = ((platform.args.first or "1").to_u64 or 1).to_u16
  http = platform.http
  tally = Tally.start()
  tally.send(Vote(n: 2))
  if tally.ask(Total, within: 5_000.ms) is Ok(2)
    out.write_line(said(asked(http, port, "GET", "/processes", ""), "\"name\": \"Tally\""))
    out.write_line(said(asked(http, port, "GET", "/processes", ""), "Surface"))
    out.write_line(said(asked(http, port, "GET", "/state/1", ""), "Tally(votes: 2)"))
    out.write_line(said(asked(http, port, "GET", "/recent/1?n=2", ""), "\"taking\": \"Vote\""))
    out.write_line(said(asked(http, port, "POST", "/send/1", "Vote(n: 3)"), "done"))
    out.write_line(said(asked(http, port, "POST", "/send/1", "Vote(n: -1)"), "Unparsed"))
    out.write_line(said(asked(http, port, "GET", "/nothing", ""), "no row"))
  end
  case tally.ask(Total, within: 5_000.ms)
    Ok(n): out.write_line(spelled(n))
    Error(_): out.write_line("the tally did not answer")
  end
end

verified: types, contracts, tests (0), property (0 seeds), sim (not run)
          proven: not run
