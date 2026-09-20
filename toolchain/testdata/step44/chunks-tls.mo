module ChunksTls
expose Seen, Sink, Writer, Acceptor, Top, tried, successful?, faulted?

intent "Require a fault-free TLS chunk exchange with exact bounded plaintext in both directions, and keep injected-fault evidence separate."

struct Seen
  bytes: List(UInt8)
  chunks: UInt64
  sizes: List(UInt64)
  closed: Bool
  idle: Bool
end

process Sink()
  state
    bytes: List(UInt8)
    chunks: UInt64
    sizes: List(UInt64)
    closed: Bool
    idle: Bool
    waiting: List(Reply(Seen))
    want_bytes: UInt64
  end

  message Chunk(bytes: List(UInt8))
  message Closed
  message Idle
  message Snapshot : Seen
  message Await(me: Handle(Sink), bytes: UInt64) : Seen
  message Check

  fn update(state, message)
    case message
      Chunk(bytes):
        state.bytes = state.bytes.concat(bytes)
        state.sizes = state.sizes.push(bytes.size)
        state.chunks += 1
        if state.waiting.size > 0 and (state.bytes.size >= state.want_bytes or state.closed or state.idle)
          seen = Seen(bytes: state.bytes, chunks: state.chunks, sizes: state.sizes,
            closed: state.closed, idle: state.idle)
          for waiter in state.waiting
            waiter.answer(seen)
          end
          state.waiting = []
        end
      Closed:
        state.closed = true
        if state.waiting.size > 0
          seen = Seen(bytes: state.bytes, chunks: state.chunks, sizes: state.sizes,
            closed: state.closed, idle: state.idle)
          for waiter in state.waiting
            waiter.answer(seen)
          end
          state.waiting = []
        end
      Idle:
        state.idle = true
        if state.waiting.size > 0
          seen = Seen(bytes: state.bytes, chunks: state.chunks, sizes: state.sizes,
            closed: state.closed, idle: state.idle)
          for waiter in state.waiting
            waiter.answer(seen)
          end
          state.waiting = []
        end
      Snapshot:
        Seen(bytes: state.bytes, chunks: state.chunks, sizes: state.sizes, closed: state.closed,
          idle: state.idle)
      Await(me: me, bytes: bytes):
        state.want_bytes = bytes
        state.waiting = state.waiting.push(reply_to)
        me.send(Check)
      Check:
        if state.waiting.size > 0 and (state.bytes.size >= state.want_bytes or state.closed or state.idle)
          seen = Seen(bytes: state.bytes, chunks: state.chunks, sizes: state.sizes,
            closed: state.closed, idle: state.idle)
          for waiter in state.waiting
            waiter.answer(seen)
          end
          state.waiting = []
        end
    end
  end
end

process Writer(conn: Conn)
  state
    writes: UInt64
  end

  message Line(text: String)
  message LineTooLong
  message Closed
  message Idle

  fn update(state, message)
    case message
      Line(text):
        if text == "go" and conn.write("aéz", within: 1.minute) is Ok(_)
          state.writes += 1
        else
          conn.close
        end
      LineTooLong | Closed | Idle: conn.close
    end
  end
end

process Acceptor(server: TlsServer)
  state
    accepted: UInt64
    refused: UInt64
  end

  message Accepted(conn: Conn)
  message Idle

  fn update(state, message)
    case message
      Accepted(conn):
        case server.accept(conn, within: 10.seconds)
          Ok(secure):
            secure.lines(into: Writer.start(secure), idle: 1.minute)
            state.accepted += 1
          Error(_):
            state.refused += 1
        end
      Idle:
        state.refused += 1
    end
  end
end

supervisor Top(server: TlsServer, conn: Conn)
  child Sink, restart: :always
  child Writer(conn), restart: :always
  child Acceptor(server), restart: :always
end

fn successful?(got: Result(Bool, TlsError)) : Bool
  case got
    Ok(true): true
    Ok(false) | Error(_): false
  end
end

fn observed(seen: Seen) : Result(Bool, TlsError)
  exact = seen.bytes == "aéz".bytes and seen.chunks == seen.sizes.size
  bounded = seen.sizes.all?(fn(n) n > 0 and n <= 2 end)
  open = !seen.closed and !seen.idle
  if exact and bounded and open
    return Ok(true)
  end
  if seen.idle
    return Error(Timeout)
  end
  if seen.closed
    return Error(Closed)
  end
  Ok(false)
end

fn spoke(client: TlsClient, plain: Conn, sink: Handle(Sink)) : Result(Bool, TlsError)
  case client.connect(plain, host: "localhost", within: 10.seconds)
    Ok(secure):
      secure.chunks(into: sink, max_bytes: 2, idle: 1.minute)
      case secure.write("go\n", within: 1.minute)
        Ok(_):
          case sink.ask(Await(me: sink, bytes: 4), within: 1.minute)
            Ok(seen): observed(seen)
            Error(_): Error(Timeout)
          end
        Error(_): Error(Closed)
      end
    Error(why): Error(why)
  end
end

fn talked(net: Net, server: TlsServer, client: TlsClient, sink: Handle(Sink)) : Result(Bool,
  TlsError)
  case net.listen(0, within: 1.minute)
    Ok(listener):
      listener.serve(into: Acceptor.start(server), idle: 1.minute)
      case net.connect("localhost", listener.port, within: 1.minute)
        Ok(plain): spoke(client, plain, sink)
        Error(_): Error(Closed)
      end
    Error(_): Error(Closed)
  end
end

fn tried(tls: Tls, net: Net, sink: Handle(Sink), offered: List(String),
  accepted: List(String)) : Result(Bool, TlsError)
  case tls.server(cert: chain_pem(), key: key_pem())
    Ok(server):
      case tls.client(trust: root_pem())
        Ok(client): talked(net, server.offer(accepted), client.offer(offered), sink)
        Error(why): Error(why)
      end
    Error(why): Error(why)
  end
end

fn faulted?(got: Result(Bool, TlsError)) : Bool
  case got
    Error(Handshake) | Error(Timeout) | Error(Closed) | Error(Untrusted): true
    Error(BadPem) | Ok(_): false
  end
end

fn chain_pem() : String
  String.join(["-----BEGIN CERTIFICATE-----",
    "MIIBgDCCATKgAwIBAgICEAIwBQYDK2VwMCkxJzAlBgNVBAMMHk1vIFRlc3QgSW50",
    "ZXJtZWRpYXRlIChFZDI1NTE5KTAeFw0yNTAxMDEwMDAwMDBaFw0zNTAxMDEwMDAw",
    "MDBaMBQxEjAQBgNVBAMMCWxvY2FsaG9zdDAqMAUGAytlcAMhAPWlBXHb/Reusmcl",
    "cbW42ZWrKs/YKsSnQ5ntlVvWjQu8o4GSMIGPMAwGA1UdEwEB/wQCMAAwDgYDVR0P",
    "AQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMBMBoGA1UdEQQTMBGCCWxvY2Fs",
    "aG9zdIcEfwAAATAdBgNVHQ4EFgQUG1YyQbz9PmEkcSeMeRtk1eyC5WAwHwYDVR0j",
    "BBgwFoAUs8Wqz4ozRi2d7GjNPmghqQilLDwwBQYDK2VwA0EAK+PG4xU+bYA6WiiA",
    "krI4jiJRpXHj7QkfA6P02aOcI9KMm1LdZf/yhP6XytiLPMQBKw0r2HnjXudDIeP8",
    "Vx6LAg==",
    "-----END CERTIFICATE-----",
    "-----BEGIN CERTIFICATE-----",
    "MIIBXTCCAQ+gAwIBAgICEAEwBQYDK2VwMCExHzAdBgNVBAMMFk1vIFRlc3QgUm9v",
    "dCAoRWQyNTUxOSkwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjApMScw",
    "JQYDVQQDDB5NbyBUZXN0IEludGVybWVkaWF0ZSAoRWQyNTUxOSkwKjAFBgMrZXAD",
    "IQCA33biT7qABH3WMNRD6wDTOw0AL+lnfcwhM8GeVp17mqNjMGEwDwYDVR0TAQH/",
    "BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFLPFqs+KM0YtnexozT5o",
    "IakIpSw8MB8GA1UdIwQYMBaAFGPVUJFKjO60TFE656zLmRHv2BnEMAUGAytlcANB",
    "ANGlNXiuwuCAxd5JzgQn4uOEXkiBGNRsiL+JqcY1h37ICxouv9AEAh/RU2N/fE0M",
    "swc6mTQOkJVG9wOjFsYbnQs=",
    "-----END CERTIFICATE-----"],
    "\n")
end

fn key_pem() : String
  String.join(["-----BEGIN PRIVATE KEY-----",
    "MC4CAQAwBQYDK2VwBCIEIJRPytK0+NsKYitWFX7mQgdwAI6ZovJtK98lEdxY7lWl",
    "-----END PRIVATE KEY-----"],
    "\n")
end

fn root_pem() : String
  String.join(["-----BEGIN CERTIFICATE-----",
    "MIIBMzCB5qADAgECAgIQADAFBgMrZXAwITEfMB0GA1UEAwwWTW8gVGVzdCBSb290",
    "IChFZDI1NTE5KTAeFw0yNTAxMDEwMDAwMDBaFw0zNTAxMDEwMDAwMDBaMCExHzAd",
    "BgNVBAMMFk1vIFRlc3QgUm9vdCAoRWQyNTUxOSkwKjAFBgMrZXADIQDeIWJUEE8q",
    "hsQpjoMpSprF0ahdxYLZBLkz9HBybAiSiqNCMEAwDwYDVR0TAQH/BAUwAwEB/zAO",
    "BgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFGPVUJFKjO60TFE656zLmRHv2BnEMAUG",
    "AytlcANBAJWFiUgoeLAzaJgUUOuh3DKaEOPGjAbuUN96MOU6X9K6oUADR9UVPkBd",
    "hYQFwRexU17XhtvxIZAD59ceKq62xAE=",
    "-----END CERTIFICATE-----"],
    "\n")
end

test "fault-free TLS chunks exchange exact bounded plaintext in both directions"
  got = tried(Tls.fixture(), Net.fixture(), Sink.start(), ["step44/1"], ["step44/1"])
  assert successful?(got)
end

test "a forced TLS handshake error fails the positive oracle"
  got = tried(Tls.fixture(), Net.fixture(), Sink.start(), ["client-only"], ["server-only"])
  assert got == Error(Handshake)
  assert !successful?(got)
end

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs)
          proven: not run
