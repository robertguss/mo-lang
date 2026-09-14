module Logstat.Parse
expose Record, Status, Malformed, parse_line, record_of, masked, card_number?

intent "Turn one log line, a timestamp, a method, a path, a status, and a duration in milliseconds separated by single spaces, into a record whose path has every card number starred out, or say why the line is malformed."

never "a parsed path still holds a card number"
  for r in Record.all
    card_number?(r.path)
  end
end

type Status = UInt16 where value >= 100 and value <= 599

struct Record
  at: Time
  method: String
  path: String
  status: Status
  duration_ms: UInt32
end

enum Malformed
  WrongFieldCount(count: UInt64)
  BadTime
  BadMethod
  BadPath
  BadStatus
  BadDuration
end

# The digits of a path read so far: the text already settled, and the run of digits not yet.
struct Scan
  done: String
  digits: String
end

fn parse_line(line: String) : Result(Record, Malformed)
  ensures result is Ok(r) implies r.status >= 100 and r.status <= 599

  fields = line.split(" ")
  return Error(WrongFieldCount(count: fields.size)) if fields.size != 5
  record_of(fields)
end

fn record_of(fields: List(String)) : Result(Record, Malformed)
  requires fields.size == 5

  at = try time_of(fields.get(0) or "")
  method = try method_of(fields.get(1) or "")
  path = try path_of(fields.get(2) or "")
  status = try status_of(fields.get(3) or "")
  ms = try duration_of(fields.get(4) or "")
  Ok(Record(at: at, method: method, path: masked(path), status: status, duration_ms: ms))
end

fn time_of(text: String) : Result(Time, Malformed)
  case Time.parse(text)
    Some(t): Ok(t)
    None: Error(BadTime)
  end
end

# A method is one or more capital ASCII letters.
fn method_of(text: String) : Result(String, Malformed)
  return Error(BadMethod) if text == "" or !text.chars.all?(fn(c) capital?(c) end)
  Ok(text)
end

fn capital?(c: String) : Bool
  "ABCDEFGHIJKLMNOPQRSTUVWXYZ".contains?(c)
end

fn path_of(text: String) : Result(String, Malformed)
  return Error(BadPath) if !text.starts_with?("/")
  Ok(text)
end

fn status_of(text: String) : Result(Status, Malformed)
  n = text.to_u64 or 0
  return Error(BadStatus) if n < 100 or n > 599
  Ok(n.to_u16)
end

fn duration_of(text: String) : Result(UInt32, Malformed)
  case text.to_u64
    Some(n):
      case n.checked_to_u32
        Some(ms): Ok(ms)
        None: Error(BadDuration)
      end
    None: Error(BadDuration)
  end
end

# Every run of 16 or more ASCII digits becomes as many stars; shorter runs stay as they are.
fn masked(text: String) : String
  scan = text.chars.reduce(Scan(done: "", digits: ""), fn(so_far, c) scanned(so_far, c) end)
  "#{scan.done}#{starred(scan.digits)}"
end

fn scanned(scan: Scan, c: String) : Scan
  return Scan(done: scan.done, digits: "#{scan.digits}#{c}") if digit?(c)
  Scan(done: "#{scan.done}#{starred(scan.digits)}#{c}", digits: "")
end

fn starred(digits: String) : String
  return digits if digits.size < 16
  "*".repeat(digits.size)
end

fn digit?(c: String) : Bool
  "0123456789".contains?(c)
end

fn card_number?(text: String) : Bool
  masked(text) != text
end

test "a line of five fields is a record"
  assert parse_line("2026-09-12T10:00:02Z POST /api/orders 500 340") is Ok(r)
  assert r.at == Time.from_parts(2026, 9, 12, 10, 0, 2)
  assert r.method == "POST" and r.path == "/api/orders"
  assert r.status == 500 and r.duration_ms == 340
end

test "a line that does not fit is malformed, and says where"
  assert parse_line("") is Error(WrongFieldCount(1))
  assert parse_line("2026-09-12T10:00:01Z GET /a 200") is Error(WrongFieldCount(4))
  assert parse_line("2026-09-12T10:00:01Z  GET /a 200 12") is Error(WrongFieldCount(6))
  assert parse_line("yesterday GET /a 200 12") is Error(BadTime)
  assert parse_line("2026-09-12T10:00:01Z get /a 200 12") is Error(BadMethod)
  assert parse_line("2026-09-12T10:00:01Z GET a 200 12") is Error(BadPath)
  assert parse_line("2026-09-12T10:00:01Z GET /a 99 12") is Error(BadStatus)
  assert parse_line("2026-09-12T10:00:01Z GET /a 600 12") is Error(BadStatus)
  assert parse_line("2026-09-12T10:00:01Z GET /a OK 12") is Error(BadStatus)
  assert parse_line("2026-09-12T10:00:01Z GET /a 200 -1") is Error(BadDuration)
  assert parse_line("2026-09-12T10:00:01Z GET /a 200 4294967296") is Error(BadDuration)
  assert parse_line("2026-09-12T10:00:01Z GET /a 200 4294967295") is Ok(_)
end

test "a card number in a path is starred out, and shorter runs of digits stay"
  assert masked("/pay/4111111111111111/charge") == "/pay/****************/charge"
  assert masked("/cards/41111111111111112") == "/cards/*****************"
  assert masked("/orders/123456789012345") == "/orders/123456789012345"
  assert parse_line("2026-09-12T10:00:01Z GET /pay/4111111111111111 200 12") is Ok(r)
  assert r.path == "/pay/****************"
  assert card_number?("/pay/4111111111111111") and !card_number?(r.path)
end

test rejects "a record read from four fields"
  record_of(["2026-09-12T10:00:01Z", "GET", "/a", "200"])
end

test rejects "a record whose status is past 599"
  Record(at: Time.fixture(), method: "GET", path: "/a", status: 600, duration_ms: 1)
end

property "a status and a duration parse exactly when the status is 100 to 599 and the duration fits UInt32"
  for status in any(UInt64), ms in any(UInt64)
    fits = status >= 100 and status <= 599 and ms <= 4_294_967_295
    assert (parse_line("2026-09-12T10:00:01Z GET /a #{status} #{ms}") is Ok(_)) == fits
  end
end
