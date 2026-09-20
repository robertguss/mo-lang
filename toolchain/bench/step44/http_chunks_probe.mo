# run: 0 http
module Step44.HttpChunksProbe
expose main

intent "Prove a runtime-owned byte source can frame an HTTP body before EOF, reject an unfinished oversized header, and reply after directional EOF."

process Done()
  state
    waiting: List(Reply(Bool))
    finished: Bool
  end

  message Wait : Bool
  message Finish

  fn update(state, message)
    case message
      Wait:
        state.waiting = state.waiting.push(reply_to)
        if state.finished
          for waiter in state.waiting
            waiter.answer(true)
          end
          state.waiting = []
        end
      Finish:
        state.finished = true
        for waiter in state.waiting
          waiter.answer(true)
        end
        state.waiting = []
    end
  end
end

fn content_length(head: String) : Option(UInt64)
  for line in head.split("\r\n")
    if line.starts_with?("Content-Length: ")
      return (line.split(": ").last or "").to_u64
    end
  end
  None
end

fn complete?(bytes: List(UInt8)) : Bool
  case String.from_bytes(bytes)
    Some(text):
      if !text.contains?("\r\n\r\n")
        return false
      end
      head = text.split("\r\n\r\n").first or ""
      case content_length(head)
        Some(n): bytes.size >= head.byte_size + 4 + n
        None: false
      end
    None: false
  end
end

fn unfinished_header_too_large?(bytes: List(UInt8)) : Bool
  if bytes.size <= 1_024
    return false
  end
  case String.from_bytes(bytes)
    Some(text): !text.contains?("\r\n\r\n")
    None: true
  end
end

fn byte_sum(bytes: List(UInt8)) : UInt64
  bytes.reduce(0.to_u64, fn(total, byte) total + byte.to_u64 end)
end

fn response(status: String, body: String) : String
  "HTTP/1.1 #{status}\r\nContent-Length: #{body.byte_size}\r\nConnection: close\r\n\r\n#{body}"
end

process Reader(conn: Conn, out: Out, done: Handle(Done), mode: String)
  state
    bytes: List(UInt8)
    chunks: UInt64
    finished: Bool
  end

  message Chunk(bytes: List(UInt8))
  message Closed
  message Idle

  fn update(state, message)
    case message
      Chunk(bytes):
        state.bytes = state.bytes.concat(bytes)
        state.chunks += 1
        if !state.finished and unfinished_header_too_large?(state.bytes)
          state.finished = true
          out.write_line("server event=header_too_large bytes=#{state.bytes.size} chunks=#{state.chunks}")
          wrote = conn.write(response("431 Request Header Fields Too Large", ""),
            within: 1.seconds) is Ok(_)
          out.write_line("server response_write=#{wrote}")
          conn.close
          done.send(Finish)
        else
          if !state.finished and mode == "http" and complete?(state.bytes)
            state.finished = true
            out.write_line("server event=request_complete bytes=#{state.bytes.size} chunks=#{state.chunks}")
            wrote = conn.write(response("200 OK", "{}"), within: 1.seconds) is Ok(_)
            out.write_line("server response_write=#{wrote}")
            conn.close
            done.send(Finish)
          end
        end
      Closed:
        if !state.finished and mode == "eof"
          state.finished = true
          body = "{\"bytes\":#{state.bytes.size},\"chunks\":#{state.chunks},\"sum\":#{byte_sum(state.bytes)}}"
          out.write_line("server event=input_closed bytes=#{state.bytes.size} chunks=#{state.chunks}")
          wrote = conn.write(response("200 OK", body), within: 1.seconds) is Ok(_)
          out.write_line("server response_write=#{wrote}")
          conn.close
          done.send(Finish)
        else
          if !state.finished
            state.finished = true
            out.write_line("server event=early_closed bytes=#{state.bytes.size} chunks=#{state.chunks}")
            conn.close
            done.send(Finish)
          end
        end
      Idle:
        if !state.finished
          state.finished = true
          out.write_line("server event=idle bytes=#{state.bytes.size} chunks=#{state.chunks}")
          conn.close
          done.send(Finish)
        end
    end
  end
end

process Acceptor(out: Out, done: Handle(Done), mode: String)
  state
    accepted: UInt64
  end

  message Accepted(conn: Conn)
  message Idle

  fn update(state, message)
    case message
      Accepted(conn):
        state.accepted += 1
        out.write_line("server event=accepted")
        conn.chunks(into: Reader.start(conn, out, done, mode), max_bytes: 64, idle: 5.seconds)
      Idle:
        out.write_line("server event=listener_idle")
        done.send(Finish)
    end
  end
end

supervisor Probe(out: Out, done: Handle(Done), mode: String)
  child Done, restart: :never
  child Acceptor(out, done, mode), restart: :never
end

supervisor Readers(conn: Conn, out: Out, done: Handle(Done), mode: String)
  child Reader(conn, out, done, mode), restart: :never
end

fn main(platform: Platform)
  done = Done.start()
  port = ((platform.args.get(0) or "0").to_u64 or 0).checked_to_u16 or 0
  mode = platform.args.get(1) or "http"
  case platform.net.listen(port, within: 2.seconds)
    Ok(listener):
      platform.stdout.write_line("server port=#{listener.port} mode=#{mode}")
      listener.serve(into: Acceptor.start(platform.stdout, done, mode), idle: 10.seconds)
      finished = done.ask(Wait, within: 12.seconds) == Ok(true)
      platform.stdout.write_line("server finished=#{finished}")
      platform.exit(if finished: 0 else: 1)
    Error(e):
      platform.stderr.write_line("server listen_error=#{e}")
      platform.exit(1)
  end
end
