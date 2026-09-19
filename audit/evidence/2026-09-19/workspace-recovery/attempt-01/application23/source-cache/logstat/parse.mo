module Logstat.Parse
expose Record, Malformed, Status, parse_line, card?

intent "Turn one log line into a record, or name why it is malformed; no line crashes it."

type Status = UInt64 where value >= 100 and value <= 599

struct Record
  at: Time
  method: String
  path: String
  status: Status
  ms: UInt32
end

enum Malformed
  FieldCount(found: UInt64)
  BadTimestamp
  BadMethod
  BadPath
  BadStatus
  BadDuration
end

fn parse_line(line: String) : Result(Record, Malformed)
  requires !line.contains?("\n")
  ensures result is Ok(r) implies r.status >= 100 and r.status <= 599
  ensures result is Ok(r) implies !card?(r.path)

  parts = line.split(" ")
  return Error(FieldCount(found: parts.size)) if parts.size != 5
  at = try timestamp_of(parts.get(0) or "")
  method = try method_of(parts.get(1) or "")
  path = try path_of(parts.get(2) or "")
  status = try status_of(parts.get(3) or "")
  ms = try ms_of(parts.get(4) or "")
  Ok(Record(at: at, method: method, path: path, status: status, ms: ms))
end

fn timestamp_of(text: String) : Result(Time, Malformed)
  case Time.parse(text)
    Some(at): Ok(at)
    None: Error(BadTimestamp)
  end
end

fn method_of(text: String) : Result(String, Malformed)
  return Error(BadMethod) if text == "" or !text.bytes.all?(fn(b) b >= 65 and b <= 90 end)
  Ok(text)
end

fn path_of(text: String) : Result(String, Malformed)
  plain = text.bytes.all?(fn(b) b >= 33 and b <= 126 and b != 34 and b != 92 end)
  return Error(BadPath) if !text.starts_with?("/") or !plain
  Ok(masked_cards(text))
end

fn status_of(text: String) : Result(UInt64, Malformed)
  status = text.to_u64 or 0
  return Error(BadStatus) if text.size > 3 or status < 100 or status > 599
  Ok(status)
end

fn ms_of(text: String) : Result(UInt32, Malformed)
  return Error(BadDuration) if text.size > 10
  wide = text.to_u64 or 4_294_967_296
  case wide.checked_to_u32
    Some(ms): Ok(ms)
    None: Error(BadDuration)
  end
end

# A run of sixteen or more digits is starred out, so no card number is ever printed.
fn masked_cards(path: String) : String
  ensures !card?(result)
  ensures result.size == path.size

  return path if !card?(path)
  done = path.chars.reduce(([], ""), fn(acc, c)
    if digit?(c)
      (acc.0, "#{acc.1}#{c}")
    else
      (acc.0.push(starred(acc.1)).push(c), "")
    end
  end)
  String.join(done.0.push(starred(done.1)), "")
end

fn starred(run: String) : String
  return run if run.size < 16
  "*".repeat(run.size)
end

# Sixteen digits in a row anywhere in the text.
fn card?(text: String) : Bool
  longest = text.chars.reduce((0, 0), fn(acc, c)
    run = if digit?(c): acc.0 + 1 else: 0
    if run > acc.1
      (run, run)
    else
      (run, acc.1)
    end
  end)
  longest.1 >= 16
end

fn digit?(c: String) : Bool
  c >= "0" and c <= "9"
end

test "a line in the common format is a record"
  outcome = parse_line("2026-09-12T10:00:02Z POST /api/orders 500 340")
  assert outcome is Ok(r)
  assert r.at == Time.from_parts(2026, 9, 12, 10, 0, 2)
  assert r.method == "POST"
  assert r.path == "/api/orders"
  assert r.status == 500
  assert r.ms == 340
end

test "a line that does not fit names the field that broke"
  assert parse_line("") is Error(FieldCount(1))
  assert parse_line("2026-09-12T10:00:02Z POST /api/orders 500") is Error(FieldCount(4))
  assert parse_line("2026-09-12T10:00:02Z  GET /a 200 1") is Error(FieldCount(6))
  assert parse_line("2026-13-12T10:00:02Z GET /a 200 1") is Error(BadTimestamp)
  assert parse_line("2026-02-30T10:00:02Z GET /a 200 1") is Error(BadTimestamp)
  assert parse_line("2026-09-12 10:00:02 GET /a 200 1") is Error(FieldCount(6))
  assert parse_line("2026-09-12T10:00:02Z get /a 200 1") is Error(BadMethod)
  assert parse_line("2026-09-12T10:00:02Z GET a 200 1") is Error(BadPath)
  assert parse_line("2026-09-12T10:00:02Z GET /a\"b 200 1") is Error(BadPath)
  assert parse_line("2026-09-12T10:00:02Z GET /a 700 1") is Error(BadStatus)
  assert parse_line("2026-09-12T10:00:02Z GET /a 99 1") is Error(BadStatus)
  assert parse_line("2026-09-12T10:00:02Z GET /a 200 4294967296") is Error(BadDuration)
  assert parse_line("2026-09-12T10:00:02Z GET /a 200 12ms") is Error(BadDuration)
end

test "the edges of status and duration are records"
  assert parse_line("2026-09-12T10:00:02Z GET /a 100 0") is Ok(_)
  assert parse_line("2026-09-12T10:00:02Z GET /a 599 4294967295") is Ok(_)
end

test "a card number in a path is starred out, and shorter numbers are not"
  outcome = parse_line("2026-09-12T10:00:09Z GET /api/cards/4111111111111111/charge 200 88")
  assert outcome is Ok(r)
  assert r.path == "/api/cards/****************/charge"
  assert parse_line("2026-09-12T10:00:09Z GET /orders/123456789012345 200 88") is Ok(short)
  assert short.path == "/orders/123456789012345"
end

test rejects "a line that still holds its newline"
  parse_line("2026-09-12T10:00:02Z GET /a 200 1\n")
end

property "no sixteen-digit run survives a parse"
  for n in any(UInt64)
    card = n % 9_000_000_000_000_000 + 1_000_000_000_000_000
    outcome = parse_line("2026-09-12T10:00:09Z GET /c/#{card}/x 200 1")
    assert outcome is Ok(r) and !card?(r.path)
  end
end

verified: types, contracts, tests (6), property (200 seeds), sim (not run)
          proven: not run
