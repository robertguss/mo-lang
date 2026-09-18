module AbuseServer

intent "Step 38's server for abuse.py: a TLS echo that says what each connection came to. It listens on the port its command line names, takes as many connections as it names one at a time, runs the server's half of the handshake on each within a second, and, handshaken, echoes lines until a read gives something other than a line, then prints the handshake's outcome, the lines echoed, and how the reading ended."

fn named(shook: Result(Conn, TlsError)) : String
  case shook
    Ok(_): "Ok"
    Error(Handshake): "Handshake"
    Error(Closed): "Closed"
    Error(Timeout): "Timeout"
    Error(Untrusted): "Untrusted"
    Error(_): "another error"
  end
end

fn read_named(got: Result(Option(String), NetError)) : String
  case got
    Ok(Some(_)): "Some"
    Ok(None): "None"
    Error(Timeout): "Timeout"
    Error(Closed): "Closed"
    Error(_): "another error"
  end
end

# Lines read and written back until a read gives no line: how many, and what ended them.
fn echoed(conn: Conn, lines: UInt32) : String
  got = conn.read_line(within: 1.seconds)
  case got
    Ok(Some(text)):
      if conn.write("#{text}\n", within: 1.seconds) is Ok(_)
        echoed(conn, lines + 1)
      else
        "lines=#{lines + 1} end=write-failed"
      end
    Ok(None) | Error(_): "lines=#{lines} end=#{read_named(got)}"
  end
end

fn served(conn: Conn) : String
  said = echoed(conn, 0)
  conn.close
  said
end

fn accepts(server: TlsServer, listener: Listener, out: Out, left: UInt32) : UInt8
  if left == 0
    0
  else
    case listener.accept(within: 1.minute)
      Ok(conn):
        shook = server.accept(conn, within: 1.seconds)
        case shook
          Ok(secure): out.write_line("accept=Ok #{served(secure)}")
          Error(_): out.write_line("accept=#{named(shook)}")
        end
        accepts(server, listener, out, left - 1)
      Error(_):
        out.write_line("no connection")
        1
    end
  end
end

fn serve(net: Net, tls: Tls, out: Out, cert: String, key: String, args: List(String)) : UInt8
  port = ((args.get(0) or "0").to_u64 or 0).checked_to_u16 or 0
  count = ((args.get(1) or "0").to_u64 or 0).checked_to_u32 or 0
  case tls.server(cert: cert, key: key)
    Ok(server):
      case net.listen(port, within: 1.minute)
        Ok(listener): accepts(server, listener, out, count)
        Error(_): 1
      end
    Error(_): 1
  end
end

fn main(platform: Platform)
  out = platform.stdout
  fs = platform.fs
  case fs.read("tls/cert.pem", within: 10.seconds)
    Ok(cert):
      case fs.read("tls/key.pem", within: 10.seconds)
        Ok(key): platform.exit(serve(platform.net, platform.tls, out, cert, key, platform.args))
        Error(_): out.write_line("no key")
      end
    Error(_): out.write_line("no certificate")
  end
end
