# run: 18443
module Effects.TlsEcho
expose Options, Echo, EchoServer, Acceptor, Echoes, listen, serve, quieted, options, bad_pem?, plain_client?, cert_pem, key_pem, other_key_pem

intent "Echo lines back through TLS: main reads a certificate and a key with Fs, makes a TlsServer from them, listens, and hands each accepted connection to an acceptor that runs the handshake and reads the connection into a worker. Every row after the handshake is the row a plain socket has."

# A worker: one connection, its lines coming from the runtime, its answers going back as records.
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

# The acceptor holds the TlsServer, which is no authority beyond its own key, and runs the
# handshake on each connection before the runtime reads it.
process Acceptor(server: TlsServer)
  state
    handshakes: UInt32
    refused: UInt32
  end

  message Accepted(conn: Conn)

  fn update(state, message)
    case message
      Accepted(conn):
        case server.accept(conn, within: 10.seconds)
          Ok(secure):
            secure.lines(into: Echo.start(secure), idle: 1.minute)
            state.handshakes += 1
          Error(_):
            state.refused += 1
        end
    end
  end
end

# The listener's own process: the runtime serves it and sends each connection on.
process EchoServer(acceptor: Handle(Acceptor))
  state
    seen: UInt32
    quiet: UInt32
    waiting: List(Reply(UInt32))
  end

  message Accepted(conn: Conn)
  message Idle
  # An ask nobody answers until the listener has gone quiet once (step 31's kept reply), so a
  # run with no client ends on Idle rather than serving for ever.
  message Quiet : UInt32

  fn update(state, message)
    case message
      Accepted(conn):
        acceptor.send(Accepted(conn: conn))
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

supervisor Echoes(server: TlsServer, acceptor: Handle(Acceptor), conn: Conn)
  child Acceptor(server), restart: :always
  child EchoServer(acceptor), restart: :always
  child Echo(conn), restart: :always
end

# What the command line says: the port to listen on, and how long with no connection ends the run.
struct Options
  port: UInt16
  idle: Duration
end

# The listener, serving every connection into a server process that hands each to the acceptor.
fn listen(net: Net, server: TlsServer, out: Out, port: UInt16,
  idle: Duration) : Result(Handle(EchoServer), NetError)
  listener = try net.listen(port, within: 1.minute)
  serving = EchoServer.start(Acceptor.start(server))
  listener.serve(into: serving, idle: idle)
  out.write_line("listening on #{listener.port}")
  Ok(serving)
end

# A certificate or a key that does not parse, or a key that is not the certificate's, is BadPem.
fn bad_pem?(tls: Tls, cert: String, key: String) : Bool
  tls.server(cert: cert, key: key) is Error(BadPem)
end

# The handshake on a connection whose client wrote plain text where a hello belongs.
fn handshook?(server: TlsServer, listener: Listener) : Bool
  case listener.accept(within: 1.minute)
    Ok(conn): server.accept(conn, within: 1.minute) is Error(Handshake)
    Error(_): false
  end
end

fn spoke_plainly?(server: TlsServer, net: Net, listener: Listener, text: String) : Bool
  case net.connect("localhost", listener.port, within: 1.minute)
    Ok(client):
      wrote = client.write(text, within: 1.minute)
      wrote is Ok(_) and handshook?(server, listener)
    Error(_): false
  end
end

fn plain_client?(net: Net, tls: Tls, cert: String, key: String, text: String) : Bool
  case tls.server(cert: cert, key: key)
    Ok(server):
      case net.listen(0, within: 1.minute)
        Ok(listener): spoke_plainly?(server, net, listener, text)
        Error(_): false
      end
    Error(_): false
  end
end

# Serving goes on until the listener has been quiet for `idle`, which with no client is at once:
# the ask the server keeps is answered from that Idle, and the count it gives is what came.
fn serve(net: Net, tls: Tls, out: Out, cert: String, key: String, given: Options) : UInt8
  case tls.server(cert: cert, key: key)
    Ok(server):
      case listen(net, server, out, given.port, given.idle)
        Ok(serving): quieted(out, serving)
        Error(_):
          out.write_line("the port is not free")
          1
      end
    Error(_):
      out.write_line("the certificate and the key do not make a server")
      1
  end
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

fn options(args: List(String)) : Options
  port = ((args.get(0) or "0").to_u64 or 0).checked_to_u16 or 0
  Options(port: port, idle: ((args.get(1) or "200").to_u64 or 200).ms)
end

fn main(platform: Platform)
  out = platform.stdout
  net = platform.net
  tls = platform.tls
  fs = platform.fs
  case fs.read("tls/cert.pem", within: 10.seconds)
    Ok(cert):
      case fs.read("tls/key.pem", within: 10.seconds)
        Ok(key): platform.exit(serve(net, tls, out, cert, key, options(platform.args)))
        Error(_): out.write_line("no key")
      end
    Error(_): out.write_line("no certificate")
  end
end

# The pair `examples/effects/tls/` keeps, written here so the tests need no file of their own.
fn cert_pem() : String
  String.join(["-----BEGIN CERTIFICATE-----",
    "MIIBUzCCAQWgAwIBAgIUezLLClFE6Kk5mrl54JhJWvbLXPMwBQYDK2VwMBQxEjAQ",
    "BgNVBAMMCWxvY2FsaG9zdDAeFw0yNjA5MTcxOTI0MDRaFw0zNjA5MTQxOTI0MDRa",
    "MBQxEjAQBgNVBAMMCWxvY2FsaG9zdDAqMAUGAytlcAMhAARTp3qAE8E1cQRtDwpT",
    "aRWPIPG6tgcJslpuYqhi1ebxo2kwZzAdBgNVHQ4EFgQULj/kPJm0T6AHNDbPj2Iv",
    "LbF9MhcwHwYDVR0jBBgwFoAULj/kPJm0T6AHNDbPj2IvLbF9MhcwDwYDVR0TAQH/",
    "BAUwAwEB/zAUBgNVHREEDTALgglsb2NhbGhvc3QwBQYDK2VwA0EAnMn3HbpwwPj5",
    "fB43amhTujMvM5GDAjAuwkDujf4d27Nuq4cr/oi0q95n1r4k7KnLyoClrodc3EkY",
    "Xh6NHG0hDA==",
    "-----END CERTIFICATE-----"],
    "\n")
end

fn key_pem() : String
  String.join(["-----BEGIN PRIVATE KEY-----",
    "MC4CAQAwBQYDK2VwBCIEILztkUJ1ZEn2x5XmjH02yEJpFIdN5ujlkWGyjjJIQYFn",
    "-----END PRIVATE KEY-----"],
    "\n")
end

# The other pair's key: it parses, and it is not this certificate's.
fn other_key_pem() : String
  String.join(["-----BEGIN PRIVATE KEY-----",
    "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg3W0DXO8nFwCwcVQ9",
    "sn0332wYzHzNPbLh8U4EBzBhniWhRANCAAQ/25xIuO8CqKSPpwlsdRlJfsl36lpM",
    "xCjpLHtOPUkEJJo8B4mitjW6iEfcS9HMhW8JmLKtLKbDl2U7xcTQzBGu",
    "-----END PRIVATE KEY-----"],
    "\n")
end

test "text that is not PEM makes no server"
  assert bad_pem?(Tls.fixture(), "not a certificate", "not a key")
end

test "a certificate and a key that are not a pair make no server"
  assert bad_pem?(Tls.fixture(), cert_pem(), other_key_pem())
  assert !bad_pem?(Tls.fixture(), cert_pem(), key_pem())
end

test "a client that writes plain text where a hello belongs never handshakes"
  assert plain_client?(Net.fixture(), Tls.fixture(), cert_pem(), key_pem(),
    "GET / HTTP/1.1\r\n\r\n")
end

verified: types, contracts, tests (3), property (0 seeds), sim (not run)
          proven: not run
