module PlainEcho

intent "Step 36's baseline: the same line echo as examples/effects/tls-echo.mo with no handshake between the socket and the reader, so bulk.py and idle.py can put the same program's records against the same program's plain bytes and read the difference as the record layer's cost."

process Echo(conn: Conn)
  state
    lines: UInt32
  end

  message Line(text: String)
  message LineTooLong
  message Closed
  message Idle

  fn update(state, message)
    case message
      Line(text):
        if conn.write("#{text}\n", within: 1.minute) is Ok(_)
          state.lines += 1
        end
      LineTooLong | Closed | Idle: conn.close
    end
  end
end

process EchoServer()
  state
    seen: UInt32
    quiet: UInt32
    waiting: List(Reply(UInt32))
  end

  message Accepted(conn: Conn)
  message Idle
  message Quiet : UInt32

  fn update(state, message)
    case message
      Accepted(conn):
        conn.lines(into: Echo.start(conn), idle: 1.minute)
        state.seen += 1
      Idle:
        state.quiet += 1
        for held in state.waiting
          held.answer(state.seen)
        end
        state.waiting = []
      Quiet:
        state.waiting = state.waiting.push(reply_to)
    end
  end
end

supervisor Echoes(conn: Conn)
  child EchoServer, restart: :always
  child Echo(conn), restart: :always
end

struct Options
  port: UInt16
  idle: Duration
end

fn options(args: List(String)) : Options
  port = ((args.get(0) or "0").to_u64 or 0).checked_to_u16 or 0
  Options(port: port, idle: ((args.get(1) or "200").to_u64 or 200).ms)
end

fn listen(net: Net, out: Out, given: Options) : Result(Handle(EchoServer), NetError)
  listener = try net.listen(given.port, within: 1.minute)
  serving = EchoServer.start()
  listener.serve(into: serving, idle: given.idle)
  out.write_line("listening on #{listener.port}")
  Ok(serving)
end

fn quieted(out: Out, serving: Handle(EchoServer)) : UInt8
  case serving.ask(Quiet, within: 1.minute)
    Ok(seen):
      out.write_line("served #{seen} connections, then went quiet")
      0
    Error(_):
      out.write_line("the server never went quiet")
      1
  end
end

fn main(platform: Platform)
  out = platform.stdout
  case listen(platform.net, out, options(platform.args))
    Ok(serving): platform.exit(quieted(out, serving))
    Error(_):
      out.write_line("the port is not free")
      platform.exit(1)
  end
end
