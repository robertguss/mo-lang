module AbuseClient

intent "Step 38's client for abuse.py: it dials the port its command line names as many times as it names, one connection at a time, runs the client's half of the handshake on each for localhost within a second, and, handshaken, reads one line within a second, printing what the handshake and the read came to. Reaching the last line is the client's process alive."

fn read_named(got: Result(Option(String), NetError)) : String
  case got
    Ok(Some(_)): "Some"
    Ok(None): "None"
    Error(Timeout): "Timeout"
    Error(Closed): "Closed"
    Error(_): "another error"
  end
end

fn talked(secure: Conn) : String
  said = read_named(secure.read_line(within: 1.seconds))
  secure.close
  "connect=Ok read=#{said}"
end

fn dialed(net: Net, client: TlsClient, port: UInt16) : String
  case net.connect("127.0.0.1", port, within: 10.seconds)
    Ok(plain):
      case client.connect(plain, host: "localhost", within: 1.seconds)
        Ok(secure): talked(secure)
        Error(why): "connect=#{why}"
      end
    Error(why): "tcp=#{why}"
  end
end

fn dials(net: Net, client: TlsClient, out: Out, port: UInt16, left: UInt32) : UInt8
  if left == 0
    out.write_line("alive")
    0
  else
    out.write_line(dialed(net, client, port))
    dials(net, client, out, port, left - 1)
  end
end

fn main(platform: Platform)
  out = platform.stdout
  port = ((platform.args.get(0) or "0").to_u64 or 0).checked_to_u16 or 0
  count = ((platform.args.get(1) or "0").to_u64 or 0).checked_to_u32 or 0
  case platform.fs.read("tls/root.pem", within: 10.seconds)
    Ok(roots):
      case platform.tls.client(trust: roots)
        Ok(client): platform.exit(dials(platform.net, client, out, port, count))
        Error(_): out.write_line("no root certificate in tls/root.pem")
      end
    Error(_): out.write_line("no tls/root.pem")
  end
end
