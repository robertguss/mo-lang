module TlsDial

intent "Step 37's client for measure.py: handshakes back to back against a server, each one a new connection and a whole TLS 1.3 handshake closed at once, or one connection that sends lines of 4 KiB through a line echo and reads them back, two windows in flight, over TLS or plain, so the same program under mo run and as a binary puts a client handshake's cost and a record's cost on the table."

# What the command line says: the host and port, how many handshakes (or, with lines, how many
# lines through one connection), whether the lines go over TLS, and the trust file.
struct Options
  host: String
  port: UInt16
  count: UInt64
  lines: UInt64
  tls: Bool
  trust: String
end

fn options(args: List(String)) : Options
  Options(host: args.get(0) or "localhost",
    port: ((args.get(1) or "0").to_u64 or 0).checked_to_u16 or 0,
    count: (args.get(2) or "0").to_u64 or 0, lines: (args.get(3) or "0").to_u64 or 0,
    tls: (args.get(4) or "tls") == "tls", trust: args.get(5) or "trust.pem")
end

# `count` connections, each handshaken and closed; how many handshook.
fn dialed(net: Net, client: TlsClient, given: Options) : UInt64
  var done = 0
  for _ in 0..given.count
    if handshook?(net, client, given)
      done += 1
    end
  end
  done
end

fn handshook?(net: Net, client: TlsClient, given: Options) : Bool
  case net.connect(given.host, given.port, within: 10.seconds)
    Ok(plain): closed?(client.connect(plain, host: given.host, within: 10.seconds))
    Error(_): false
  end
end

fn closed?(conn: Result(Conn, TlsError)) : Bool
  case conn
    Ok(secure):
      secure.close
      true
    Error(_): false
  end
end

# Lines of 4 KiB through the echo with two windows of 64 in flight: the next window goes out before
# the last is read back, so each direction always has bytes moving. A window written and then read
# back whole stalls on the delayed ACK (the runtimes leave Nagle on), about 40 ms a window; reading
# on the runtime's loop while a write on the same Conn waits does not work either (the read waits
# for the write). A window of 64 lines is 256 KiB, which the sockets' buffers hold.
fn pumped(conn: Conn, line: String, lines: UInt64) : UInt64
  window = 64
  var back = 0
  var ahead = wrote(conn, line, window)
  for _ in 1..lines / window
    sent = wrote(conn, line, window)
    back += read_back(conn, ahead)
    ahead = sent
  end
  back += read_back(conn, ahead)
  back
end

fn wrote(conn: Conn, line: String, window: UInt64) : UInt64
  var sent = 0
  for _ in 0..window
    if conn.write(line, within: 1.minute) is Ok(_)
      sent += 1
    end
  end
  sent
end

fn read_back(conn: Conn, count: UInt64) : UInt64
  var back = 0
  for _ in 0..count
    back += size_of(conn.read_line(within: 1.minute))
  end
  back
end

fn size_of(got: Result(Option(String), NetError)) : UInt64
  case got
    Ok(text): (text or "").size + 1
    Error(_): 0
  end
end

fn bulk(net: Net, client: TlsClient, given: Options) : UInt64
  line = "#{String.join((0..4095).map(fn(i) "#{i % 10}" end), "")}\n"
  case net.connect(given.host, given.port, within: 10.seconds)
    Ok(plain):
      if given.tls
        case client.connect(plain, host: given.host, within: 10.seconds)
          Ok(secure): pumped(secure, line, given.lines)
          Error(_): 0
        end
      else
        pumped(plain, line, given.lines)
      end
    Error(_): 0
  end
end

fn main(platform: Platform)
  out = platform.stdout
  given = options(platform.args)
  fs = platform.fs
  tls = platform.tls
  net = platform.net
  case fs.read(given.trust, within: 10.seconds)
    Ok(roots):
      case tls.client(trust: roots)
        Ok(client):
          if given.lines > 0
            out.write_line("#{bulk(net, client, given)} bytes back")
          else
            out.write_line("#{dialed(net, client, given)} handshakes")
          end
        Error(_): out.write_line("no root in #{given.trust}")
      end
    Error(_): out.write_line("no #{given.trust}")
  end
end
