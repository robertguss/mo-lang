module WorkspaceServer.Wire
expose Refusal, Head, head, head_fits?, response, malformed, too_large, request_cap, response_cap

intent "Read the head of one mo-workspace-http-v1 request as the contract fixes it, and write a response: a request line of POST /tool HTTP/1.1, the four required headers once each and an optional Connection: close, nothing else, and the refusal each departure earns, with the status and the stable code CONTRACT.md names."

# A refusal before admission: the HTTP status and the stable error code.
struct Refusal
  status: UInt16
  error: String
end

# What a head that passed gives the reader: the body's length and the token offered.
struct Head
  length: UInt64
  offered: String
end

fn request_cap() : UInt64
  851_968
end

fn response_cap() : UInt64
  524_288
end

fn malformed() : Refusal
  Refusal(status: 400, error: "malformed")
end

# The contract names 413 for a request past its bounds and no bridge code for it; the core
# code `oversized` belongs to files (review finding H7), so the code is `malformed`.
fn too_large() : Refusal
  Refusal(status: 413, error: "malformed")
end

# Whether a head of this many bytes, counting the CRLF after each line, stays within 16,384.
# Its line count is the head's own check: 32 fields past the request line is malformed.
fn head_fits?(bytes: UInt64) : Bool
  bytes <= 16_384
end

# The request line and header lines of one request, without their line ends, checked in the
# order the Python bridge checks them.
fn head(lines: List(String), port: UInt16) : Result(Head, Refusal)
  return Error(malformed()) if !lines.all?(fn(line) ascii?(line) end)
  parts = (lines.first or "").split(" ")
  return Error(malformed()) if parts.size != 3
  return Error(malformed()) if (parts.get(2) or "") != "HTTP/1.1"
  return Error(Refusal(status: 405, error: "method")) if (parts.first or "") != "POST"
  return Error(Refusal(status: 404, error: "not_found")) if (parts.get(1) or "") != "/tool"
  fields = lines.drop(1)
  return Error(malformed()) if fields.size > 32
  headers = try named(fields)
  checked(headers, port)
end

# The header fields by lower-cased name; a name outside the five, a repeat, or a control
# character in a value is malformed.
fn named(fields: List(String)) : Result(Map(String, String), Refusal)
  allowed = ["host", "content-type", "content-length", "x-mo-workspace-token", "connection"]
  var headers = Map.new()
  for field in fields
    colon = field.index_of(":") or field.size
    return Error(malformed()) if colon == field.size
    name = field.slice(0, colon).to_lower
    value = field.slice(colon + 1, field.size)
    return Error(malformed()) if !allowed.contains?(name) or headers.has?(name)
    return Error(malformed()) if value.bytes.any?(fn(b) b < 32 or b == 127 end)
    headers = headers.set(name, spaces_off(value))
  end
  Ok(headers)
end

fn checked(headers: Map(String, String), port: UInt16) : Result(Head, Refusal)
  return Error(malformed()) if !headers.has?("host")
  return Error(Refusal(status: 403,
    error: "unbound")) if headers.get("host") != Some("127.0.0.1:#{port}")
  if !headers.has?("x-mo-workspace-token")
    return Error(Refusal(status: 401, error: "unauthorized"))
  end
  offered = headers.get("x-mo-workspace-token") or ""
  if (headers.get("content-type") or "") != "application/json"
    return Error(Refusal(status: 415, error: "unsupported_media"))
  end
  return Error(malformed()) if (headers.get("connection") or "close").to_lower != "close"
  length = try canonical(headers.get("content-length") or "")
  return Error(too_large()) if length > request_cap()
  Ok(Head(length: length, offered: offered))
end

# A canonical positive decimal of at most nine digits.
fn canonical(text: String) : Result(UInt64, Refusal)
  digits = text.bytes
  return Error(malformed()) if digits.size == 0 or digits.size > 9 or digits.first == Some(48)
  return Error(malformed()) if !digits.all?(fn(b) b >= 48 and b <= 57 end)
  text.to_u64.map(fn(n) Ok(n) end) or Error(malformed())
end

fn ascii?(line: String) : Bool
  line.bytes.all?(fn(b) b < 128 end)
end

# Spaces off both ends, as the bridge strips them; a tab is a control character, refused above.
fn spaces_off(value: String) : String
  var start = 0
  var stop = value.size
  for _ in 0..value.size
    if start < stop and value.slice(start, start + 1) == " "
      start += 1
    end
  end
  for _ in 0..value.size
    if stop > start and value.slice(stop - 1, stop) == " "
      stop -= 1
    end
  end
  value.slice(start, stop)
end

fn reason(status: UInt16) : String
  case status
    200: "OK"
    400: "Bad Request"
    401: "Unauthorized"
    403: "Forbidden"
    404: "Not Found"
    405: "Method Not Allowed"
    409: "Conflict"
    413: "Content Too Large"
    415: "Unsupported Media Type"
    504: "Gateway Timeout"
    _: "Result"
  end
end

# One whole response: explicit Content-Length and Connection: close on every one.
fn response(status: UInt16, body: String) : String
  "HTTP/1.1 #{status} #{reason(status)}\r\nContent-Type: application/json\r\nContent-Length: #{body.byte_size}\r\nConnection: close\r\n\r\n#{body}"
end

fn good(port: UInt16) : List(String)
  ["POST /tool HTTP/1.1",
    "Host: 127.0.0.1:#{port}",
    "Content-Type: application/json",
    "Content-Length: 12",
    "X-Mo-Workspace-Token: abc"]
end

test "a whole head gives the body's length and the token offered"
  assert head(good(8080), 8080) == Ok(Head(length: 12, offered: "abc"))
  assert head(good(8080).push("Connection: close"), 8080) == Ok(Head(length: 12, offered: "abc"))
end

test "each departure from the request line earns its own refusal"
  lines = good(9)
  assert head(["GET /tool HTTP/1.1"].concat(lines.drop(1)),
    9) == Error(Refusal(status: 405, error: "method"))
  assert head(["POST /tool?x HTTP/1.1"].concat(lines.drop(1)),
    9) == Error(Refusal(status: 404, error: "not_found"))
  assert head(["POST /tool HTTP/1.0"].concat(lines.drop(1)), 9) == Error(malformed())
  assert head(["POST  /tool HTTP/1.1"].concat(lines.drop(1)), 9) == Error(malformed())
end

test "headers: extra, repeated, unknown, missing, and bad lengths"
  lines = good(9)
  assert head(lines.push("Origin: null"), 9) == Error(malformed())
  assert head(lines.push("Transfer-Encoding: chunked"), 9) == Error(malformed())
  assert head(lines.push("Content-Length: 1"), 9) == Error(malformed())
  assert head(lines.push("Connection: keep-alive"), 9) == Error(malformed())
  assert head(lines.filter(fn(l) !l.starts_with?("Host") end), 9) == Error(malformed())
  assert head(lines, 10) == Error(Refusal(status: 403, error: "unbound"))
  assert head(lines.filter(fn(l) !l.starts_with?("X-Mo") end),
    9) == Error(Refusal(status: 401, error: "unauthorized"))
  assert head(lines.take(2).concat(["Content-Type: text/plain"]).concat(lines.drop(3)),
    9) == Error(Refusal(status: 415, error: "unsupported_media"))
  assert head(lines.take(3).concat(["Content-Length: 01"]).concat(lines.drop(4)),
    9) == Error(malformed())
  assert head(lines.take(3).concat(["Content-Length: 851969"]).concat(lines.drop(4)),
    9) == Error(too_large())
  assert head(lines.take(3).concat(["Content-Length: 1000000000"]).concat(lines.drop(4)),
    9) == Error(malformed())
  assert head(lines.push("X: é"), 9) == Error(malformed())
end

test "a head is bounded in bytes, and past 32 fields it is malformed"
  assert head_fits?(16_384)
  assert !head_fits?(16_385)
  fields = "X: 1\n".repeat(33).split("\n").take(33)
  assert head(["POST /tool HTTP/1.1"].concat(fields), 9) == Error(malformed())
end

test "a response carries its length and closes"
  assert response(200,
    "{}") == "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}"
  assert response(409, "é").contains?("Content-Length: 2\r\n")
end
