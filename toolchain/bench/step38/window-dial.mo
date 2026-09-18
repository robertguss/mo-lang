module WindowDial

intent "Step 38's client for measure.py: one connection that sends lines of 4 KiB through a line echo a window at a time, the whole window written and then the whole window read back, over TLS or plain, so a write-then-read pattern's cost under Nagle's algorithm and with TCP_NODELAY reads off the time."

struct Options
  host: String
  port: UInt16
  lines: UInt64
  window: UInt64
  tls: Bool
  trust: String
end

fn options(args: List(String)) : Options
  Options(host: args.get(0) or "127.0.0.1",
    port: ((args.get(1) or "0").to_u64 or 0).checked_to_u16 or 0,
    lines: (args.get(2) or "0").to_u64 or 0, window: (args.get(3) or "1").to_u64 or 1,
    tls: (args.get(4) or "tls") == "tls", trust: args.get(5) or "root.pem")
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

# `lines` lines, a window at a time: each window written whole, then read back whole.
fn windows(conn: Conn, line: String, given: Options) : UInt64
  var back = 0
  for _ in 0..given.lines / given.window
    back += read_back(conn, wrote(conn, line, given.window))
  end
  back
end

fn bulk(net: Net, client: TlsClient, given: Options) : UInt64
  line = "#{String.join((0..4095).map(fn(i) "#{i % 10}" end), "")}\n"
  case net.connect(given.host, given.port, within: 10.seconds)
    Ok(plain):
      if given.tls
        case client.connect(plain, host: "localhost", within: 10.seconds)
          Ok(secure): windows(secure, line, given)
          Error(_): 0
        end
      else
        windows(plain, line, given)
      end
    Error(_): 0
  end
end

fn main(platform: Platform)
  out = platform.stdout
  given = options(platform.args)
  case platform.fs.read(given.trust, within: 10.seconds)
    Ok(roots):
      case platform.tls.client(trust: roots)
        Ok(client): out.write_line("#{bulk(platform.net, client, given)} bytes back")
        Error(_): out.write_line("no root in #{given.trust}")
      end
    Error(_): out.write_line("no #{given.trust}")
  end
end
