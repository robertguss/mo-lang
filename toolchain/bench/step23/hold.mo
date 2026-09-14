module Main

# One idle connection's process: it lives while the runtime reads its connection into it.
process Holder(conn: Conn)
  state
    lines: UInt64
  end

  message Line(text: String)
  message LineTooLong
  message Closed
  message Idle

  fn update(state, message)
    case message
      Line(_):
        state.lines += 1
      LineTooLong:
        state.lines += 1
      Closed | Idle: conn.close
    end
  end
end

process Acceptor() mailbox: 16_384
  state
    accepted: UInt64
  end

  message Accepted(conn: Conn)
  message Idle

  fn update(state, message)
    case message
      Accepted(conn):
        conn.lines(into: Holder.start(conn), idle: 3_600_000.ms)
        state.accepted += 1
      Idle: state.accepted
    end
  end
end

supervisor Holders(conn: Conn)
  child Holder(conn), restart: :never
end

supervisor Acceptors
  child Acceptor, restart: :always
end

fn main(platform: Platform)
  port = ((platform.args.first or "7990").to_u64 or 7_990).to_u16
  case platform.net.listen(port, within: 5_000.ms)
    Ok(listener): listener.serve(into: Acceptor.start(), idle: 3_600_000.ms)
    Error(_): platform.exit(1)
  end
end
