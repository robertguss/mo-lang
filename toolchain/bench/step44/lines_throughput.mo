module Step44.LinesThroughput
expose Done, Reader, Acceptor, Top, main

intent "Count the unchanged Conn.lines path over a fixed volume of loopback newline-delimited input."

process Done()
  state
    waiting: List(Reply(Bool))
    finished: Bool
    ok: Bool
  end

  message Wait : Bool
  message Finish(ok: Bool)

  fn update(state, message)
    case message
      Wait:
        state.waiting = state.waiting.push(reply_to)
        if state.finished
          for waiter in state.waiting
            waiter.answer(state.ok)
          end
          state.waiting = []
        end
      Finish(ok):
        state.finished = true
        state.ok = ok
        for waiter in state.waiting
          waiter.answer(ok)
        end
        state.waiting = []
    end
  end
end

process Reader(conn: Conn, done: Handle(Done), want: UInt64)
  state
    bytes: UInt64
    lines: UInt64
    finished: Bool
  end

  message Line(text: String)
  message LineTooLong
  message Closed
  message Idle

  fn update(state, message)
    case message
      Line(text):
        state.bytes += text.byte_size + 1
        state.lines += 1
        if !state.finished and state.bytes >= want
          state.finished = true
          ok = state.bytes == want and conn.write("ok\n", within: 5.seconds) is Ok(_)
          conn.close
          done.send(Finish(ok: ok))
        end
      LineTooLong | Closed | Idle:
        if !state.finished
          state.finished = true
          conn.close
          done.send(Finish(ok: false))
        end
    end
  end
end

process Acceptor(done: Handle(Done), want: UInt64)
  state
    accepted: UInt64
  end

  message Accepted(conn: Conn)
  message Idle

  fn update(state, message)
    case message
      Accepted(conn):
        state.accepted += 1
        conn.lines(into: Reader.start(conn, done, want), idle: 30.seconds)
      Idle: done.send(Finish(ok: false))
    end
  end
end

supervisor Top(done: Handle(Done), want: UInt64, conn: Conn)
  child Done, restart: :never
  child Reader(conn, done, want), restart: :never
  child Acceptor(done, want), restart: :never
end

fn main(platform: Platform)
  port = ((platform.args.get(0) or "0").to_u64 or 0).checked_to_u16 or 0
  want = (platform.args.get(1) or "0").to_u64 or 0
  done = Done.start()
  case platform.net.listen(port, within: 5.seconds)
    Ok(listener):
      listener.serve(into: Acceptor.start(done, want), idle: 30.seconds)
      platform.exit(if done.ask(Wait, within: 60.seconds) == Ok(true): 0 else: 1)
    Error(_): platform.exit(1)
  end
end
