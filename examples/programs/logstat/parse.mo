module Logstat.Parse
expose Status, Record, ParseError, parse_line, masked, card?

intent "Turn one log line, <ISO-8601 timestamp> <method> <path> <status> <duration_ms>, into a record, or say it is malformed; a card number in a path is starred out before the record exists."

never "a record's path holds a card number"
  for r in Record.all
    card?(r.path)
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

enum ParseError
  Malformed(why: String)
end

fn parse_line(line: String) : Result(Record, ParseError)
  ensures result is Ok(r) implies r.status >= 100 and r.status <= 599 and !card?(r.path)

  fields = line.split(" ")
  return Error(Malformed(why: "not five fields")) if fields.size != 5
  at = try timestamp(fields.get(0) or "")
  method = try method_of(fields.get(1) or "")
  path = try path_of(fields.get(2) or "")
  status = try status_of(fields.get(3) or "")
  ms = try duration_of(fields.get(4) or "")
  Ok(Record(at: at, method: method, path: masked(path), status: status, duration_ms: ms))
end

fn timestamp(text: String) : Result(Time, ParseError)
  case Time.parse(text)
    Some(at): Ok(at)
    None: Error(Malformed(why: "the timestamp is not ISO-8601"))
  end
end

fn method_of(text: String) : Result(String, ParseError)
  letters = text.bytes.all?(fn(b) b >= 65 and b <= 90 end)
  return Ok(text) if text != "" and letters
  Error(Malformed(why: "the method is not upper-case letters"))
end

fn path_of(text: String) : Result(String, ParseError)
  return Ok(text) if text.starts_with?("/")
  Error(Malformed(why: "the path does not start with /"))
end

fn status_of(text: String) : Result(Status, ParseError)
  n = text.to_u64 or 0
  return Error(Malformed(why: "the status is not 100 to 599")) if n < 100 or n > 599
  Ok(n.to_u16)
end

fn duration_of(text: String) : Result(UInt32, ParseError)
  case text.to_u64
    Some(n):
      case n.checked_to_u32
        Some(ms): Ok(ms)
        None: Error(Malformed(why: "the duration does not fit UInt32"))
      end
    None: Error(Malformed(why: "the duration is not a whole number of milliseconds"))
  end
end

# A card number is 16 digits in a row; a run of 16 or more is starred out whole, digit for digit.
fn masked(path: String) : String
  ensures !card?(result)
  ensures result.size == path.size

  return path if !card?(path)
  ends = path.chars.reduce(("", ""), fn(so_far, ch) stepped(so_far, ch) end)
  "#{ends.0}#{hidden(ends.1)}"
end

# The text so far, and the run of digits it ends in that is not decided yet.
fn stepped(so_far: (String, String), ch: String) : (String, String)
  return (so_far.0, "#{so_far.1}#{ch}") if digit?(ch)
  ("#{so_far.0}#{hidden(so_far.1)}#{ch}", "")
end

fn hidden(run: String) : String
  if run.size >= 16: "*".repeat(run.size) else: run
end

fn digit?(ch: String) : Bool
  ch >= "0" and ch <= "9" and ch.byte_size == 1
end

fn card?(text: String) : Bool
  return false if text.bytes.count(fn(b) b >= 48 and b <= 57 end) < 16
  runs = text.chars.reduce((0, 0), fn(so_far, ch) run_step(so_far, ch) end)
  runs.1 >= 16
end

# The run of digits the text so far ends in, and the longest run seen.
fn run_step(so_far: (UInt64, UInt64), ch: String) : (UInt64, UInt64)
  return (0, so_far.1) if !digit?(ch)
  (so_far.0 + 1, max_of(so_far.0 + 1, so_far.1))
end

test "the spec's two lines parse into records"
  assert parse_line("2026-09-12T10:00:01Z GET /api/users 200 12") is Ok(get)
  assert get.at == Time.from_parts(2026, 9, 12, 10, 0, 1)
  assert get.method == "GET"
  assert get.path == "/api/users"
  assert get.status == 200
  assert get.duration_ms == 12
  assert parse_line("2026-09-12T10:00:02Z POST /api/orders 500 340") is Ok(post)
  assert post.status == 500 and post.duration_ms == 340
end

test "the status is 100 to 599 and the duration fits UInt32, both edges included"
  assert parse_line("2026-09-12T10:00:01Z GET / 100 0") is Ok(_)
  assert parse_line("2026-09-12T10:00:01Z GET / 599 4294967295") is Ok(_)
  assert parse_line("2026-09-12T10:00:01Z GET / 99 1") is Error(Malformed(_))
  assert parse_line("2026-09-12T10:00:01Z GET / 600 1") is Error(Malformed(_))
  assert parse_line("2026-09-12T10:00:01Z GET / 200 4294967296") is Error(Malformed(_))
  assert parse_line("2026-09-12T10:00:01Z GET / 200 -1") is Error(Malformed(_))
  assert parse_line("2026-09-12T10:00:01Z GET / 2xx 1") is Error(Malformed(_))
end

test "a line that does not fit the format is malformed"
  assert parse_line("") is Error(Malformed(_))
  assert parse_line("2026-09-12T10:00:01Z GET /api/users 200") is Error(Malformed(_))
  assert parse_line("2026-09-12T10:00:01Z GET /api/users 200 12 extra") is Error(Malformed(_))
  assert parse_line("2026-09-12T10:00:01Z GET  /api/users 200 12") is Error(Malformed(_))
  assert parse_line("yesterday GET /api/users 200 12") is Error(Malformed(_))
  assert parse_line("2026-02-30T10:00:01Z GET /api/users 200 12") is Error(Malformed(_))
  assert parse_line("2026-09-12T10:00:01Z get /api/users 200 12") is Error(Malformed(_))
  assert parse_line("2026-09-12T10:00:01Z GET api/users 200 12") is Error(Malformed(_))
end

test "a card number in a path is starred out, and shorter runs of digits are kept"
  line = "2026-09-12T10:00:03Z GET /cards/4111111111111111/charges 200 9"
  assert parse_line(line) is Ok(record)
  assert record.path == "/cards/****************/charges"
  assert masked("/orders/123456789012345") == "/orders/123456789012345"
  assert masked("/x/12345678901234567/y/4242424242424242") == "/x/*****************/y/****************"
  assert card?("/a4111111111111111")
  assert !card?("/1234-5678-9012-3456")
end

test rejects "a record with a status below 100"
  Record(at: Time.fixture(), method: "GET", path: "/", status: 99, duration_ms: 1)
end

test rejects "a record whose path holds a card number trips the never"
  record = Record(at: Time.fixture(), method: "GET", path: "/cards/4111111111111111", status: 200,
    duration_ms: 1)
  assert record.status == 200
end

property "a masked path never holds a card number, whatever digits it carries"
  for prefix in any(String), digits in any(UInt64)
    assert !card?(masked("/#{prefix}#{digits}#{digits}"))
  end
end

verified: types, contracts, tests (7), property (200 seeds), sim (not run)
          proven: not run
