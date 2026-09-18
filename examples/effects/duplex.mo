# run:
module Effects.Duplex
expose Echo, EchoServer, Acceptor, Back, Heard, Writer, Reader, Echoes, Leg, wrote, read_back, whole, pumped, streamed, leg, both_ways, timed, said, pair, waits, paused, waited, legs, echoed?, fixture_leg, fixture_client, heard_back?, fixture_tls, chain_pem, key_pem, root_pem

intent "Stream both ways through one Conn at once (step 38): a client writes 1,600 lines of 4 KiB to a line echo and reads the echoes on the same connection while the writes go on, from main with the runtime's lines loop reading, and from a process writing while main reads, over a plain socket and over TLS. A write that waits for the peer holds up no read on its connection."

# The echo's worker: one connection, its lines coming from the runtime, each written back.
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

# The plain listener's process: the runtime serves each connection into it.
process EchoServer()
  state
    seen: UInt32
    quiet: UInt32
  end

  message Accepted(conn: Conn)
  message Idle

  fn update(state, message)
    case message
      Accepted(conn):
        conn.lines(into: Echo.start(conn), idle: 1.minute)
        state.seen += 1
      Idle:
        state.quiet += 1
    end
  end
end

# The TLS listener's process: the server's half of the handshake, then the same echo.
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

# What came back to the client: the lines, counted as they come, and whether the stream ended.
# `Done` is answered once `want` lines are in, or once the stream has ended.
process Back(want: UInt32)
  state
    got: UInt32
    ended: Bool
    waiting: List(Reply(Heard))
  end

  message Line(text: String)
  message LineTooLong
  message Closed
  message Idle
  message Done : Heard

  fn update(state, message)
    case message
      Line(text):
        if text.size == 4095
          state.got += 1
        end
        if state.got >= want
          for held in state.waiting
            held.answer(Heard(got: state.got, ended: state.ended))
          end
          state.waiting = []
        end
      LineTooLong | Closed | Idle:
        state.ended = true
        for held in state.waiting
          held.answer(Heard(got: state.got, ended: true))
        end
        state.waiting = []
      Done:
        if state.got >= want or state.ended
          Heard(got: state.got, ended: state.ended)
        else
          state.waiting = state.waiting.push(reply_to)
        end
    end
  end
end

# The writing side as a process, so main can read the same connection while the writes wait.
process Writer(conn: Conn)
  state
    sent: UInt32
  end

  message Write(count: UInt32) : UInt32
  # 16 MiB to a peer that reads nothing: the write waits for the peer until its deadline.
  message Stall

  fn update(state, message)
    case message
      Write(count):
        state.sent = wrote(conn, count)
        state.sent
      Stall:
        line = "#{String.join((0..4095).map(fn(i) "#{i % 10}" end), "")}\n"
        if conn.write(String.join((0..4096).map(fn(_) line end), ""), within: 1.seconds) is Ok(_)
          state.sent += 1
        end
    end
  end
end

# A second reader: one read_line that waits while main tries its own.
process Reader(conn: Conn)
  state
    reads: UInt32
  end

  message Read

  fn update(state, message)
    case message
      Read:
        if conn.read_line(within: 500.ms) is Ok(_)
          state.reads += 1
        end
    end
  end
end

supervisor Echoes(server: TlsServer, conn: Conn)
  child EchoServer, restart: :always
  child Acceptor(server), restart: :always
  child Echo(conn), restart: :always
  child Back(0), restart: :always
  child Writer(conn), restart: :always
  child Reader(conn), restart: :always
end

# What `Back` heard: the whole lines, and whether the stream ended first.
struct Heard
  got: UInt32
  ended: Bool
end

# One leg of the run: the lines sent, the lines back, and whether it took under a second.
struct Leg
  sent: UInt32
  back: UInt32
  quick: Bool
end

# `count` lines of 4 KiB, each written whole; how many went.
fn wrote(conn: Conn, count: UInt32) : UInt32
  line = "#{String.join((0..4095).map(fn(i) "#{i % 10}" end), "")}\n"
  var sent = 0
  for _ in 0..count
    if conn.write(line, within: 1.minute) is Ok(_)
      sent += 1
    end
  end
  sent
end

# `count` lines read on the connection itself, each checked whole: a line at a time, since the
# runtime owns every loop around read_line.
fn read_back(conn: Conn, count: UInt32) : UInt32
  if count == 0
    0
  else
    whole(conn.read_line(within: 1.minute)) + read_back(conn, count - 1)
  end
end

fn whole(got: Result(Option(String), NetError)) : UInt32
  case got
    Ok(Some(text)):
      if text.size == 4095
        1
      else
        0
      end
    Ok(None) | Error(_): 0
  end
end

# main writes; the runtime reads the echoes into `Back` while the writes go on.
fn pumped(conn: Conn, count: UInt32) : Leg
  back = Back.start(count)
  conn.lines(into: back, idle: 1.minute)
  sent = wrote(conn, count)
  heard = case back.ask(Done, within: 1.minute)
    Ok(h): h.got
    Error(_): 0
  end
  Leg(sent: sent, back: heard, quick: false)
end

# A process writes; main reads the echoes with read_line while the writes go on.
fn streamed(conn: Conn, count: UInt32) : Leg
  writer = Writer.start(conn)
  writer.send(Write(count: count))
  back = read_back(conn, count)
  Leg(sent: count, back: back, quick: false)
end

# One leg over a new connection to the echo at `port`, behind TLS when `client` is one: main
# writes and the runtime reads (`main_writes`), or a process writes and main reads.
fn leg(net: Net, client: Option(TlsClient), port: UInt16, main_writes: Bool, count: UInt32) : Leg
  case net.connect("localhost", port, within: 10.seconds)
    Ok(plain):
      case client
        Some(tls):
          case tls.connect(plain, host: "localhost", within: 10.seconds)
            Ok(secure): both_ways(secure, main_writes, count)
            Error(_): Leg(sent: 0, back: 0, quick: false)
          end
        None: both_ways(plain, main_writes, count)
      end
    Error(_): Leg(sent: 0, back: 0, quick: false)
  end
end

fn both_ways(conn: Conn, main_writes: Bool, count: UInt32) : Leg
  if main_writes
    pumped(conn, count)
  else
    streamed(conn, count)
  end
end

# A leg's time on the runtime's clock, from `started`: under a second or not.
fn timed(clock: Clock, started: Time, done: Leg) : Leg
  Leg(sent: done.sent, back: done.back, quick: clock.now.since(started).ms < 1000)
end

fn said(name: String, done: Leg) : String
  "#{name}: #{done.sent} sent, #{done.back} back, under a second: #{done.quick}"
end

# Both legs over one listener: main writing, then main reading, 1,600 lines each.
fn pair(net: Net, clock: Clock, out: Out, client: Option(TlsClient), port: UInt16) : UInt8
  name = if client is Some(_): "tls" else: "plain"
  started = clock.now
  out.write_line(said("#{name}, main writes, lines reads",
    timed(clock, started, leg(net, client, port, true, 1600))))
  restarted = clock.now
  out.write_line(said("#{name}, a process writes, main reads",
    timed(clock, restarted, leg(net, client, port, false, 1600))))
  0
end

# While a process's write waits for a peer that reads nothing (a listener nobody accepts on, whose
# queue holds the connection): a second write is Busy, a read_line goes on and is Timeout, and a
# read_line while another reader waits is Busy. main pauses in an accept nobody answers, so the
# process it just sent to runs up to its wait first.
fn waits(net: Net, out: Out) : UInt8
  case net.listen(0, within: 1.minute)
    Ok(unread):
      case net.connect("localhost", unread.port, within: 10.seconds)
        Ok(conn): paused(net, conn, out)
        Error(_): 1
      end
    Error(_): 1
  end
end

# A second listener nobody connects to, for main's pauses.
fn paused(net: Net, conn: Conn, out: Out) : UInt8
  case net.listen(0, within: 1.minute)
    Ok(pause):
      out.write_line(waited(conn, pause))
      0
    Error(_): 1
  end
end

fn waited(conn: Conn, pause: Listener) : String
  Writer.start(conn).send(Stall)
  paused = pause.accept(within: 200.ms)
  second = conn.write("x\n", within: 1.seconds)
  read = conn.read_line(within: 50.ms)
  Reader.start(conn).send(Read)
  again = pause.accept(within: 50.ms)
  other = conn.read_line(within: 50.ms)
  "while a write waits (the pauses #{paused} and #{again}): a second write #{second}, a read_line #{read}, a read_line while another waits #{other}"
end

# The two echoes, plain and TLS, each served into its own process, then both pairs of legs.
fn legs(net: Net, clock: Clock, server: TlsServer, client: TlsClient, out: Out) : UInt8
  case net.listen(0, within: 1.minute)
    Ok(plain_at):
      case net.listen(0, within: 1.minute)
        Ok(tls_at):
          plain_at.serve(into: EchoServer.start(), idle: 1.minute)
          tls_at.serve(into: Acceptor.start(server), idle: 1.minute)
          pair(net, clock, out, None, plain_at.port) + pair(net, clock, out, Some(client),
            tls_at.port) + waits(net, out)
        Error(_): 1
      end
    Error(_): 1
  end
end

fn main(platform: Platform)
  out = platform.stdout
  tls = platform.tls
  case tls.server(cert: chain_pem(), key: key_pem())
    Ok(server):
      case tls.client(trust: root_pem())
        Ok(client): platform.exit(legs(platform.net, platform.clock, server, client, out))
        Error(_): out.write_line("no client")
      end
    Error(_): out.write_line("no server")
  end
end

# What a test's leg came to: every line back, or a fault the seed made cut it short.
fn echoed?(count: UInt32, sent: UInt32, heard: Result(Heard, AskError)) : Bool
  case heard
    Ok(h): h.got <= sent and (h.got == count or h.ended or sent < count)
    Error(_): true
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

# The root that signed the intermediate, as tls/root.pem holds it: what the client trusts.
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

# A client of the echo on the in-memory network, plain or behind Tls.fixture(): it connects, has
# the echoes read into `Back`, and writes `count` lines, in one statement, so the echo runs as it
# goes. A connection or a handshake cut short is what a seeded run's faults make, and nothing else.
fn fixture_leg(net: Net, server: Option(TlsServer), client: Option(TlsClient), count: UInt32) : Bool
  case net.listen(0, within: 1.minute)
    Ok(listener):
      case server
        Some(tls): listener.serve(into: Acceptor.start(tls), idle: 1.minute)
        None: listener.serve(into: EchoServer.start(), idle: 1.minute)
      end
      fixture_client(net, client, listener.port, count)
    Error(_): false
  end
end

fn fixture_client(net: Net, client: Option(TlsClient), port: UInt16, count: UInt32) : Bool
  case net.connect("localhost", port, within: 10.seconds)
    Ok(plain):
      case client
        Some(tls):
          case tls.connect(plain, host: "localhost", within: 10.seconds)
            Ok(secure): heard_back?(secure, count)
            Error(why): why == Timeout or why == Closed
          end
        None: heard_back?(plain, count)
      end
    Error(why): why == Timeout
  end
end

fn heard_back?(conn: Conn, count: UInt32) : Bool
  back = Back.start(count)
  conn.lines(into: back, idle: 1.minute)
  sent = wrote(conn, count)
  echoed?(count, sent, back.ask(Done, within: 1.minute))
end

fn fixture_tls(tls: Tls, net: Net, count: UInt32) : Bool
  case tls.server(cert: chain_pem(), key: key_pem())
    Ok(server):
      case tls.client(trust: root_pem())
        Ok(client): fixture_leg(net, Some(server), Some(client), count)
        Error(_): false
      end
    Error(_): false
  end
end

test "the echoes come back through lines while main writes on the same Conn (Net.fixture)"
  assert fixture_leg(Net.fixture(), None, None, 64)
end

test "the same behind Tls.fixture(): records each way on one connection"
  assert fixture_tls(Tls.fixture(), Net.fixture(), 64)
end

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs)
          proven: not run
