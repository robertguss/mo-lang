module Step44.ChunksThroughput
expose Done, Reader, Acceptor, Top, main

intent "Count a fixed volume of loopback binary input delivered by Conn.chunks and acknowledge only after every byte arrived."

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
    chunks: UInt64
    finished: Bool
  end

  message Chunk(bytes: List(UInt8))
  message Closed
  message Idle

  fn update(state, message)
    case message
      Chunk(bytes):
        state.bytes += bytes.size
        state.chunks += 1
        if !state.finished and state.bytes >= want
          state.finished = true
          ok = state.bytes == want and conn.write("ok\n", within: 5.seconds) is Ok(_)
          conn.close
          done.send(Finish(ok: ok))
        end
      Closed | Idle:
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
        conn.chunks(into: Reader.start(conn, done, want), max_bytes: 65_536, idle: 30.seconds)
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
