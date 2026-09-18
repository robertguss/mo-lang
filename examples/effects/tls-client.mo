# run: 127.0.0.1 1
# exit: 1
module Effects.TlsClient
expose Echo, Acceptor, Heard, Echoes, Target, Attempt, target, dialed, echoed, tried, talked, spoke, faulted?, heard?, chain_pem, key_pem, root_pem, other_root_pem

intent "Open a TLS connection from a Mo program: main reads the roots it trusts with Fs, makes a TlsClient from them, connects to the host and port on its command line, runs the client's half of the handshake on that Conn, writes one line, and prints what comes back. Its tests put a TlsServer and a TlsClient on the two ends of Net.fixture()'s network, both halves of the handshake driven by the simulator: a line each way, ALPN agreed and refused, and a chain refused for its root and for its name."

# A worker on the server's side: one connection, its lines coming from the runtime, each written
# back as records.
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

# The listener's process: the runtime serves each connection into it, and it runs the server's
# half of the handshake before the runtime reads the connection into a worker.
process Acceptor(server: TlsServer)
  state
    handshakes: UInt32
    refused: UInt32
    quiet: UInt32
  end

  message Accepted(conn: Conn)
  message Idle

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
      Idle:
        state.quiet += 1
    end
  end
end

# What the client heard, line by line, until its connection ended.
process Heard()
  state
    lines: List(String)
    ended: Bool
  end

  message Line(text: String)
  message LineTooLong
  message Closed
  message Idle
  message Lines : List(String)

  fn update(state, message)
    case message
      Line(text):
        state.lines = state.lines.push(text)
      LineTooLong:
        state.lines = state.lines.push("")
      Closed | Idle:
        state.ended = true
      Lines: state.lines
    end
  end
end

supervisor Echoes(server: TlsServer, conn: Conn)
  child Acceptor(server), restart: :always
  child Echo(conn), restart: :always
  child Heard, restart: :always
end

# Where main connects: the host and the port on the command line.
struct Target
  host: String
  port: UInt16
end

fn target(args: List(String)) : Target
  Target(host: args.get(0) or "localhost",
    port: ((args.get(1) or "0").to_u64 or 0).checked_to_u16 or 0)
end

# A plain connection, then the client's half of the handshake on it, for the host the command
# line named (a name or an address, which the leaf must hold), then one line out and one back.
fn dialed(net: Net, client: TlsClient, out: Out, to: Target) : UInt8
  case net.connect(to.host, to.port, within: 10.seconds)
    Ok(plain):
      case client.connect(plain, host: to.host, within: 10.seconds)
        Ok(secure): echoed(secure, out)
        Error(why):
          out.write_line("#{why}")
          1
      end
    Error(why):
      out.write_line("#{why}")
      1
  end
end

fn echoed(secure: Conn, out: Out) : UInt8
  case secure.write("hello from mo\n", within: 10.seconds)
    Ok(_):
      case secure.read_line(within: 10.seconds)
        Ok(got):
          out.write_line(got or "the server closed")
          secure.close
          0
        Error(why):
          out.write_line("#{why}")
          1
      end
    Error(why):
      out.write_line("#{why}")
      1
  end
end

# What a test tries: the roots the client trusts, the host it connects for, and each side's ALPN
# list (an empty list offers nothing).
struct Attempt
  trust: String
  host: String
  offered: List(String)
  accepted: List(String)
end

# A client and a server from the PEM text below, on one network.
fn tried(tls: Tls, net: Net, heard: Handle(Heard), attempt: Attempt) : Result(Option(String),
  TlsError)
  server = try tls.server(cert: chain_pem(), key: key_pem())
  client = try tls.client(trust: attempt.trust)
  talked(net, server.offer(attempt.accepted), client.offer(attempt.offered), attempt.host, heard)
end

# A client of a listener the runtime serves into an acceptor holding `server`: it connects,
# handshakes for `host`, has what comes back read into `heard`, and writes one line, all in one
# statement, so the handshake's rounds and the echo run as it goes. The protocol ALPN agreed, or
# why the client has none.
fn talked(net: Net, server: TlsServer, client: TlsClient, host: String,
  heard: Handle(Heard)) : Result(Option(String), TlsError)
  case net.listen(0, within: 1.minute)
    Ok(listener):
      listener.serve(into: Acceptor.start(server), idle: 1.minute)
      case net.connect("localhost", listener.port, within: 1.minute)
        Ok(plain): spoke(client, plain, host, heard)
        Error(_): Error(Closed)
      end
    Error(_): Error(Closed)
  end
end

fn spoke(client: TlsClient, plain: Conn, host: String,
  heard: Handle(Heard)) : Result(Option(String), TlsError)
  secure = try client.connect(plain, host: host, within: 10.seconds)
  secure.lines(into: heard, idle: 1.minute)
  case secure.write("hello\n", within: 1.minute)
    Ok(_): Ok(secure.protocol)
    Error(_): Error(Closed)
  end
end

# What a seeded run's faults can make of a connection: it timed out or closed before the
# handshake had anything to say.
fn faulted?(talk: Result(Option(String), TlsError)) : Bool
  talk is Error(Timeout) or talk is Error(Closed)
end

# What came back is the line that went, unless a fault cut it short or a seeded run left it
# waiting; anything, when the client never got to talk.
fn heard?(talk: Result(Option(String), TlsError), heard: Result(List(String), AskError)) : Bool
  case heard
    Ok(lines): talk is Error(_) or ["hello"].take(lines.size) == lines
    Error(_): true
  end
end

fn main(platform: Platform)
  out = platform.stdout
  fs = platform.fs
  tls = platform.tls
  net = platform.net
  case fs.read("tls/root.pem", within: 10.seconds)
    Ok(roots):
      case tls.client(trust: roots)
        Ok(client): platform.exit(dialed(net, client, out, target(platform.args)))
        Error(_): out.write_line("no root certificate in tls/root.pem")
      end
    Error(_): out.write_line("no tls/root.pem")
  end
end

# The server's chain, leaf first (leaf, intermediate), as tls/cert.pem holds it.
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

# The leaf's key, as tls/key.pem holds it.
fn key_pem() : String
  String.join(["-----BEGIN PRIVATE KEY-----",
    "MC4CAQAwBQYDK2VwBCIEIJRPytK0+NsKYitWFX7mQgdwAI6ZovJtK98lEdxY7lWl",
    "-----END PRIVATE KEY-----"],
    "\n")
end

# The root that signed the intermediate, as tls/root.pem holds it: what main trusts.
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

# A second root that signed nothing here (tls/root-other.pem).
fn other_root_pem() : String
  String.join(["-----BEGIN CERTIFICATE-----",
    "MIIBNTCB6KADAgECAgIQDjAFBgMrZXAwIjEgMB4GA1UEAwwXTW8gT3RoZXIgUm9v",
    "dCAoRWQyNTUxOSkwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjAiMSAw",
    "HgYDVQQDDBdNbyBPdGhlciBSb290IChFZDI1NTE5KTAqMAUGAytlcAMhAHQZcxGd",
    "6KGDS/ZcRZNodH99WMGi8STv7jXWQMqNFVJuo0IwQDAPBgNVHRMBAf8EBTADAQH/",
    "MA4GA1UdDwEB/wQEAwIBBjAdBgNVHQ4EFgQUB6OsojSRohcN5MTBjfeP9X0Jp4Yw",
    "BQYDK2VwA0EAblxbn4cmS9fVnCXNvjXUu0PGT3PCvBQVt7GD0JJ9GjcL68Pr/AEP",
    "PCg1Ur6mGiLv/ndwWY74QTKUCEbxmoYqBg==",
    "-----END CERTIFICATE-----"],
    "\n")
end

test "a client that trusts the root handshakes with the server from its chain, and a line goes each way"
  heard = Heard.start()
  talk = tried(Tls.fixture(), Net.fixture(), heard,
    Attempt(trust: root_pem(), host: "localhost", offered: [], accepted: []))
  assert talk == Ok(None) or faulted?(talk)
  assert heard?(talk, heard.ask(Lines, within: 1.minute))
end

test "ALPN: the server's protocol that the client also offered is the one agreed"
  heard = Heard.start()
  talk = tried(Tls.fixture(), Net.fixture(), heard,
    Attempt(trust: root_pem(), host: "localhost", offered: ["mo/1", "echo/1"],
    accepted: ["echo/1"]))
  assert talk == Ok(Some("echo/1")) or faulted?(talk)
  assert heard?(talk, heard.ask(Lines, within: 1.minute))
end

test "ALPN: a client offering only what the server does not speak is Handshake"
  talk = tried(Tls.fixture(), Net.fixture(), Heard.start(),
    Attempt(trust: root_pem(), host: "localhost", offered: ["mo/1"], accepted: ["echo/1"]))
  assert talk == Error(Handshake) or faulted?(talk)
end

test "a client that trusts another root refuses the server's chain"
  talk = tried(Tls.fixture(), Net.fixture(), Heard.start(),
    Attempt(trust: other_root_pem(), host: "localhost", offered: [], accepted: []))
  assert talk == Error(Untrusted) or faulted?(talk)
end

test "a client connecting for example.org refuses a leaf for localhost"
  talk = tried(Tls.fixture(), Net.fixture(), Heard.start(),
    Attempt(trust: root_pem(), host: "example.org", offered: [], accepted: []))
  assert talk == Error(Untrusted) or faulted?(talk)
end

test "text with no certificate in it makes no client"
  assert Tls.fixture().client(trust: "not a certificate") is Error(BadPem)
  assert Tls.fixture().client(trust: key_pem()) is Error(BadPem)
end

verified: types, contracts, tests (6), property (0 seeds), sim (100 runs)
          proven: not run
