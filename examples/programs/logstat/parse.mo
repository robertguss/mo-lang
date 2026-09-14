module Logstat.Parse
expose Status, Record, Malformed, parse_line

intent "Turn one line of a log in the common format into a record, or say why the line is malformed; a line is never a crash."

type Status = UInt16 where value >= 100 and value <= 599

struct Record
  at: Time
  method: String
  path: String
  status: Status
  ms: UInt32
end

enum Malformed
  Fields(count: UInt64)
  BadTime
  BadMethod
  BadPath
  BadStatus
  BadDuration
end

# `<ISO-8601 timestamp> <method> <path> <status> <duration_ms>`, one space between each two.
fn parse_line(line: String) : Result(Record, Malformed)
  ensures result is Ok(r) implies r.status >= 100 and r.status <= 599

  fields = line.split(" ")
  return Error(Fields(count: fields.size)) if fields.size != 5
  at = try time_of(fields.get(0) or "")
  method = try method_of(fields.get(1) or "")
  path = try path_of(fields.get(2) or "")
  status = try status_of(fields.get(3) or "")
  ms = try duration_of(fields.get(4) or "")
  Ok(Record(at: at, method: method, path: path, status: status, ms: ms))
end

fn time_of(text: String) : Result(Time, Malformed)
  case Time.parse(text)
    Some(at): Ok(at)
    None: Error(BadTime)
  end
end

# A method is one to sixteen ASCII capital letters.
fn method_of(text: String) : Result(String, Malformed)
  capitals = text.bytes.all?(fn(b) b >= 65 and b <= 90 end)
  return Error(BadMethod) if text.byte_size < 1 or text.byte_size > 16 or !capitals
  Ok(text)
end

fn path_of(text: String) : Result(String, Malformed)
  return Error(BadPath) if !text.starts_with?("/")
  Ok(text)
end

# Three digits, 100 to 599.
fn status_of(text: String) : Result(Status, Malformed)
  n = text.to_u64 or 0
  return Error(BadStatus) if text.byte_size != 3 or n < 100 or n > 599
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

test "a line in the common format is a record"
  parsed = parse_line("2026-09-12T10:00:02Z POST /api/orders 500 340")
  assert parsed is Ok(r)
  assert r.at == (Time.parse("2026-09-12T10:00:02Z") or t0)
  assert r.method == "POST"
  assert r.path == "/api/orders"
  assert r.status == 500
  assert r.ms == 340
end

test "a line that does not fit the format is malformed, and says which field"
  assert parse_line("") is Error(Fields(1))
  assert parse_line("2026-09-12T10:00:02Z GET /a 200") is Error(Fields(4))
  assert parse_line("2026-09-12T10:00:02Z GET /a 200 12 extra") is Error(Fields(6))
  assert parse_line("2026-09-12T10:00:02Z  GET /a 200") is Error(BadMethod)
  assert parse_line("yesterday GET /a 200 12") is Error(BadTime)
  assert parse_line("2026-02-30T10:00:02Z GET /a 200 12") is Error(BadTime)
  assert parse_line("2026-09-12T10:00:02Z get /a 200 12") is Error(BadMethod)
  assert parse_line("2026-09-12T10:00:02Z - /a 200 12") is Error(BadMethod)
  assert parse_line("2026-09-12T10:00:02Z GET a 200 12") is Error(BadPath)
  assert parse_line("2026-09-12T10:00:02Z GET /a 20 12") is Error(BadStatus)
  assert parse_line("2026-09-12T10:00:02Z GET /a 0200 12") is Error(BadStatus)
  assert parse_line("2026-09-12T10:00:02Z GET /a abc 12") is Error(BadStatus)
  assert parse_line("2026-09-12T10:00:02Z GET /a 200 -1") is Error(BadDuration)
  assert parse_line("2026-09-12T10:00:02Z GET /a 200 1.5") is Error(BadDuration)
end

test "a status is 100 to 599 and a duration fits UInt32"
  assert parse_line("2026-09-12T10:00:02Z GET /a 100 0") is Ok(_)
  assert parse_line("2026-09-12T10:00:02Z GET /a 599 4294967295") is Ok(_)
  assert parse_line("2026-09-12T10:00:02Z GET /a 099 1") is Error(BadStatus)
  assert parse_line("2026-09-12T10:00:02Z GET /a 600 1") is Error(BadStatus)
  assert parse_line("2026-09-12T10:00:02Z GET /a 200 4294967296") is Error(BadDuration)
end

test rejects "a record whose status is 600"
  Record(at: t0, method: "GET", path: "/", status: 600, ms: 1)
end

property "a line parses exactly when its status is 100 to 599 and its duration fits UInt32"
  for status in any(UInt16), ms in any(UInt64)
    parsed = parse_line("2026-09-12T10:00:01Z GET /a #{status} #{ms}")
    fits = status >= 100 and status <= 599 and ms <= 4_294_967_295
    assert (parsed is Ok(_)) == fits
  end
end

verified: types, contracts, tests (5), property (200 seeds), sim (not run)
          proven: not run
