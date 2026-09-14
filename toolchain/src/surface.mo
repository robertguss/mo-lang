module Mo.Surface
expose Surface, Surfaces, serve_surface

intent "The runtime surface over HTTP on 127.0.0.1, which mo run --surface PORT and a binary built with --surface start before main: each request is answered as JSON from a Runtime's rows, by a process whose updates run between the program's."

process Surface(runtime: Runtime) mailbox: 256
  state
    answered: UInt64
  end

  message Accepted(exchange: Exchange)
  message Idle

  fn update(state, message)
    case message
      Accepted(exchange):
        if exchange.reply(answer(runtime, exchange.request), within: 5_000.ms) is Ok(_)
          state.answered += 1
        end
      Idle: state.answered
    end
  end
end

supervisor Surfaces(runtime: Runtime)
  child Surface(runtime), restart: :always
end

# Serves the surface at `port`, or at a free port when it is 0, and gives the port it listens on,
# or 0 when the port cannot be had.
fn serve_surface(runtime: Runtime, http: Http, port: UInt16) : UInt16
  case http.listen(port, within: 5_000.ms)
    Ok(listener):
      listener.serve(into: Surface.start(runtime), idle: 3_600_000.ms)
      listener.port
    Error(_): 0
  end
end

fn answer(runtime: Runtime, request: Request) : Response
  parts = request.path.split("/").drop(1)
  what = parts.first or ""
  id = (parts.get(1) or "").to_u64
  case request.method
    "GET": read(runtime, request, what, id)
    "POST": act(runtime, request, what, id)
    _: failed(405, "the surface takes GET and POST")
  end
end

fn read(runtime: Runtime, request: Request, what: String, id: Option(UInt64)) : Response
  n = count(request, 20)
  case what
    "processes": ok(Json.encode(runtime.processes(within: 1_000.ms)))
    "state": state_of(runtime, id)
    "recent": recent_of(runtime, id, n)
    "events":
      ok(Json.encode(runtime.events(since: since(request), n: count(request, 100),
        within: 1_000.ms)))
    "crashes": ok(Json.encode(runtime.crashes(n, within: 1_000.ms)))
    "sources": ok(Json.encode(runtime.sources(within: 1_000.ms)))
    "memory": ok(Json.encode(runtime.memory(within: 1_000.ms)))
    "slowest": ok(Json.encode(runtime.slowest(n, within: 1_000.ms)))
    _: failed(404, "no row is called #{what}")
  end
end

fn state_of(runtime: Runtime, id: Option(UInt64)) : Response
  case id
    Some(n): stated(runtime.state(n, within: 1_000.ms))
    None: failed(400, "state takes a process id, as in /state/3")
  end
end

fn recent_of(runtime: Runtime, id: Option(UInt64), n: UInt64) : Response
  case id
    Some(pid): ok(Json.encode(runtime.recent(pid, n, within: 1_000.ms)))
    None: failed(400, "recent takes a process id, as in /recent/3?n=10")
  end
end

fn act(runtime: Runtime, request: Request, what: String, id: Option(UInt64)) : Response
  case id
    Some(n):
      case what
        "send":
          case runtime.send(n, request.body, within: 1_000.ms)
            Ok(_): done()
            Error(e): refused(e)
          end
        "pause":
          case runtime.pause(n, within: 1_000.ms)
            Ok(_): done()
            Error(e): refused(e)
          end
        "resume":
          case runtime.resume(n, within: 1_000.ms)
            Ok(_): done()
            Error(e): refused(e)
          end
        _: failed(404, "no act is called #{what}")
      end
    None: failed(400, "#{what} takes a process id, as in /#{what}/3")
  end
end

fn stated(got: Result(String, RuntimeError)) : Response
  case got
    Ok(text): ok(Json.encode(text))
    Error(e): refused(e)
  end
end

fn done() : Response
  ok("\"done\"")
end

# A refusal: 404 for an id no process has, 403 for a read-only surface, and 409 otherwise.
fn refused(e: RuntimeError) : Response
  Response(status: refusal_status(e), headers: json_headers(), body: "#{Json.encode(e)}\n")
end

fn refusal_status(e: RuntimeError) : UInt16
  case e
    NoProcess: 404
    ReadOnly: 403
    Unparsed(_) | MailboxFull | Timeout: 409
  end
end

fn count(request: Request, default: UInt64) : UInt64
  case request.query.get("n")
    Some(text): text.to_u64 or default
    None: default
  end
end

fn since(request: Request) : Time
  epoch = Time.from_parts(1970, 1, 1, 0, 0, 0)
  case request.query.get("since")
    Some(text): Time.parse(text) or epoch
    None: epoch
  end
end

fn json_headers() : Map(String, String)
  Map.new().set("content-type", "application/json")
end

fn ok(body: String) : Response
  Response(status: 200, headers: json_headers(), body: "#{body}\n")
end

fn failed(status: UInt16, why: String) : Response
  Response(status: status, headers: json_headers(),
    body: "#{Json.encode(Map.new().set("error", why))}\n")
end
