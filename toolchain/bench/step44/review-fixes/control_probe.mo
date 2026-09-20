module Step44.ReviewControls
expose Done, ChunkSink, PullReader, BlockedWriter, PendingObserver, Controls, Observers, bounded?, pending?, main

intent "Exercise Conn.chunks bounds and reader ownership on real sockets, including a blocked writer that cannot stop input progress."

process Done()
  state
    finished: Bool
    ok: Bool
    waiting: List(Reply(Bool))
  end

  message Wait : Bool
  message Finish(ok: Bool)

  fn update(state, message)
    case message
      Wait:
        if state.finished
          state.ok
        else
          state.waiting = state.waiting.push(reply_to)
        end
      Finish(ok):
        if !state.finished
          state.finished = true
          state.ok = ok
          for waiter in state.waiting
            waiter.answer(ok)
          end
          state.waiting = []
        end
    end
  end
end

fn bounded?(sizes: List(UInt64), max: UInt64) : Bool
  sizes.all?(fn(n) n > 0 and n <= max end)
end

process ChunkSink(done: Handle(Done), want: String, max: UInt64)
  state
    bytes: List(UInt8)
    sizes: List(UInt64)
  end

  message Chunk(bytes: List(UInt8))
  message Closed
  message Idle

  fn update(state, message)
    case message
      Chunk(bytes):
        state.bytes = state.bytes.concat(bytes)
        state.sizes = state.sizes.push(bytes.size)
        if state.bytes.size >= want.byte_size
          done.send(Finish(ok: state.bytes == want.bytes and bounded?(state.sizes, max)))
        end
      Closed | Idle:
        done.send(Finish(ok: false))
    end
  end
end

process PullReader(conn: Conn)
  state
    returned: Bool
  end

  message Begin

  fn update(state, message)
    case message
      Begin:
        case conn.read_line(within: 10.seconds)
          Ok(_) | Error(_):
            state.returned = true
        end
    end
  end
end

process BlockedWriter(conn: Conn, payload: String, out: Out)
  state
    returned: Bool
  end

  message Stall

  fn update(state, message)
    case message
      Stall:
        case conn.write(payload, within: 10.seconds)
          Ok(wrote):
            out.write_line("blocked-writer returned=Ok bytes=#{wrote}")
            out.flush
            state.returned = true
          Error(why):
            out.write_line("blocked-writer returned=Error(#{why})")
            out.flush
            state.returned = true
        end
    end
  end
end

supervisor Controls(conn: Conn, done: Handle(Done), want: String, max: UInt64,
    payload: String, out: Out)
  child Done, restart: :always
  child ChunkSink(done, want, max), restart: :always
  child PullReader(conn), restart: :always
  child BlockedWriter(conn, payload, out), restart: :always
end

fn pending?(runtime: Runtime, process_name: String, call: String) : Bool
  runtime.processes(within: 1.seconds).any?(fn(info)
    info.name == process_name and info.waiting_in == Some(call)
  end)
end

process PendingObserver(runtime: Runtime, process_name: String, call: String)
  state
    waiting: List(Reply(Bool))
    checks_left: UInt64
  end

  message Await(me: Handle(PendingObserver), checks: UInt64) : Bool
  message Check(me: Handle(PendingObserver))

  fn update(state, message)
    case message
      Await(me: me, checks: checks):
        state.waiting = state.waiting.push(reply_to)
        state.checks_left = checks
        me.send(Check(me: me))
      Check(me):
        ready = pending?(runtime, process_name, call)
        if ready or state.checks_left == 0
          for waiter in state.waiting
            waiter.answer(ready)
          end
          state.waiting = []
        else
          state.checks_left -= 1
          me.send(Check(me: me))
        end
    end
  end
end

supervisor Observers(runtime: Runtime, process_name: String, call: String)
  child PendingObserver(runtime, process_name, call), restart: :always
end

fn await_pending?(runtime: Runtime, process_name: String, call: String) : Bool
  observer = PendingObserver.start(runtime, process_name, call)
  observer.ask(Await(me: observer, checks: 256), within: 3.seconds) == Ok(true)
end

fn show_pending_rows(runtime: Runtime, out: Out, process_name: String)
  var rows = 0
  for info in runtime.processes(within: 1.seconds)
    if info.name == process_name
      rows += 1
      waiting = case info.waiting_in
        Some(found): found
        None: "none"
      end
      out.write_line("pending-row id=#{info.id} name=#{info.name} alive=#{info.alive} paused=#{info.paused}")
      out.write_line("pending-row mailbox=#{info.mailbox} bound=#{info.bound} restarts=#{info.restarts} scheduler=#{info.scheduler} waiting_in=#{waiting}")
    end
  end
  out.write_line("pending-row target=#{process_name} rows=#{rows}")
  out.flush
end

fn bound_pair(out: Out, max: UInt64, listener: Listener, client: Conn) : UInt8
  case listener.accept(within: 2.seconds)
    Ok(server):
      done = Done.start()
      server.chunks(into: ChunkSink.start(done, "B", max), max_bytes: max, idle: 2.seconds)
      wrote = client.write("B", within: 2.seconds) is Ok(_)
      client.close
      exact = done.ask(Wait, within: 2.seconds) == Ok(true)
      out.write_line("bound=#{max} wrote=#{wrote} exact_bounded=#{exact}")
      if wrote and exact: 0 else: 1
    Error(_): 1
  end
end

fn bounds(net: Net, out: Out, max: UInt64) : UInt8
  case net.listen(0, within: 2.seconds)
    Ok(listener):
      case net.connect("localhost", listener.port, within: 2.seconds)
        Ok(client): bound_pair(out, max, listener, client)
        Error(_): 1
      end
    Error(_): 1
  end
end

fn pull_pair(runtime: Runtime, out: Out, listener: Listener, client: Conn) : UInt8
  case listener.accept(within: 2.seconds)
    Ok(server):
      PullReader.start(server).send(Begin)
      waiting = await_pending?(runtime, "PullReader", "Conn.read_line")
      out.write_line("pull-reader waiting_in=Conn.read_line confirmed=#{waiting}")
      out.flush
      if !waiting
        show_pending_rows(runtime, out, "PullReader")
        1
      else
        server.chunks(into: ChunkSink.start(Done.start(), "never", 8), max_bytes: 8,
          idle: 2.seconds)
        2
      end
    Error(_): 1
  end
end

fn pending_pull(net: Net, runtime: Runtime, out: Out) : UInt8
  case net.listen(0, within: 2.seconds)
    Ok(listener):
      case net.connect("localhost", listener.port, within: 2.seconds)
        Ok(client): pull_pair(runtime, out, listener, client)
        Error(_): 1
      end
    Error(_): 1
  end
end

fn late_pair(tls: TlsClient, out: Out, listener: Listener, client: Conn) : UInt8
  case listener.accept(within: 2.seconds)
    Ok(_):
      client.chunks(into: ChunkSink.start(Done.start(), "never", 8), max_bytes: 8,
        idle: 2.seconds)
      out.write_line("late-tls registration=complete handshake=starting")
      out.flush
      case tls.connect(client, host: "localhost", within: 2.seconds)
        Ok(_) | Error(_): 2
      end
    Error(_): 1
  end
end

fn late_connected(net: Net, tls: TlsClient, out: Out, listener: Listener) : UInt8
  case net.connect("localhost", listener.port, within: 2.seconds)
    Ok(client): late_pair(tls, out, listener, client)
    Error(_): 1
  end
end

fn late_tls(net: Net, tls: Tls, fs: Fs, out: Out) : UInt8
  case fs.read("examples/effects/tls/root.pem", within: 2.seconds)
    Ok(root):
      case tls.client(trust: root)
        Ok(client):
          case net.listen(0, within: 2.seconds)
            Ok(listener): late_connected(net, client, out, listener)
            Error(_): 1
          end
        Error(_): 1
      end
    Error(_): 1
  end
end

fn controlled_input(data: Conn, control_at: Listener, runtime: Runtime, out: Out) : UInt8
  payload = "x".repeat(16_777_216)
  done = Done.start()
  data.chunks(into: ChunkSink.start(done, "input-progress", 4), max_bytes: 4, idle: 5.seconds)
  BlockedWriter.start(data, payload, out).send(Stall)
  blocked = await_pending?(runtime, "BlockedWriter", "Conn.write")
  out.write_line("blocked-writer waiting_in=Conn.write confirmed=#{blocked}")
  out.flush
  if !blocked
    show_pending_rows(runtime, out, "BlockedWriter")
    1
  else
    case control_at.accept(within: 3.seconds)
      Ok(control):
        signalled = control.write("writer-blocked\n", within: 1.seconds) is Ok(_)
        progressed = done.ask(Wait, within: 3.seconds) == Ok(true)
        var still_blocked = false
        if progressed
          still_blocked = await_pending?(runtime, "BlockedWriter", "Conn.write")
        end
        out.write_line("blocked-writer post-input waiting_in=Conn.write confirmed=#{still_blocked}")
        out.flush
        if !still_blocked
          show_pending_rows(runtime, out, "BlockedWriter")
        end
        var answered = false
        if still_blocked
          answered = control.write("input-progress\n", within: 1.seconds) is Ok(_)
        end
        control.close
        out.write_line("blocked-writer signalled=#{signalled} input_exact=#{progressed} answered=#{answered}")
        if signalled and progressed and still_blocked and answered: 0 else: 1
      Error(_): 1
    end
  end
end

fn blocked(net: Net, runtime: Runtime, out: Out, data_port: UInt16, control_port: UInt16) : UInt8
  case net.listen(data_port, within: 2.seconds)
    Ok(data_at):
      case net.listen(control_port, within: 2.seconds)
        Ok(control_at):
          case data_at.accept(within: 3.seconds)
            Ok(data): controlled_input(data, control_at, runtime, out)
            Error(_): 1
          end
        Error(_): 1
      end
    Error(_): 1
  end
end

fn main(platform: Platform)
  args = platform.args
  mode = args.get(0) or ""
  case platform.runtime
    Some(runtime):
      code = case mode
        "bounds":
          requested = args.get(1) or ""
          case requested.to_u64
            Some(max):
              platform.stdout.write_line("bound-request=#{requested} parsed=#{max}")
              platform.stdout.flush
              bounds(platform.net, platform.stdout, max)
            None:
              platform.stderr.write_line("bound-request=#{requested} parse=failed")
              platform.stderr.flush
              65
          end
        "pending-pull": pending_pull(platform.net, runtime, platform.stdout)
        "late-tls": late_tls(platform.net, platform.tls, platform.fs, platform.stdout)
        "blocked-writer":
          data = ((args.get(1) or "0").to_u64 or 0).checked_to_u16 or 0
          control = ((args.get(2) or "0").to_u64 or 0).checked_to_u16 or 0
          blocked(platform.net, runtime, platform.stdout, data, control)
        _: 64
      end
      platform.exit(code)
    None:
      platform.stderr.write_line("runtime surface required")
      platform.exit(1)
  end
end
