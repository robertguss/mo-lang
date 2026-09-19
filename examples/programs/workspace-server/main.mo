# run:
# exit: 2
module WorkspaceServer.Main
expose main

intent "The stub of the Mo workspace server: it listens on two loopback ports, publishes them in the run folder's ready.json, and closes every connection unanswered, so every behaviour group is red before the server exists."

process Closer()
  state
    closed: UInt64
  end

  message Accepted(conn: Conn)
  message Idle

  fn update(state, message)
    case message
      Accepted(conn):
        conn.close
        state.closed += 1
      Idle:
        state.closed += 0
    end
  end
end

supervisor Stubs
  child Closer, restart: :always
end

fn main(platform: Platform)
  folder = platform.args.first or ""
  if folder == ""
    platform.stdout.write_line("usage: workspace-server RUN_FOLDER")
    platform.exit(2)
  else
    serve(platform.net, platform.fs.scoped(folder), platform.stderr)
  end
end

fn serve(net: Net, run: Fs, err: Out)
  case (net.listen(0, within: 5_000.ms), net.listen(0, within: 5_000.ms))
    (Ok(tools), Ok(operator)):
      tools.serve(into: Closer.start(), idle: 60_000.ms)
      operator.serve(into: Closer.start(), idle: 60_000.ms)
      ready = "{\"port\": #{tools.port}, \"operator_port\": #{operator.port}}"
      if run.replace("ready.json", ready, within: 5_000.ms) is Error(e)
        err.write_line("ready.json: #{e}")
      end
    _: err.write_line("no loopback port")
  end
end
