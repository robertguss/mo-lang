module Logstat.Parse
expose Status, Record, Malformed, parse_line, masked, card?

intent "Read one log line, `<ISO-8601 timestamp> <method> <path> <status> <duration_ms>`, into a record whose path never holds a card number, or name why the line is malformed."

never "a card number reaches a record"
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
  ms: UInt32
end

enum Malformed
  Fields(count: UInt64)
  Timestamp
  Method
  Path
  StatusCode
  Duration
end

# One line without its newline. The path in a record is already masked.
fn parse_line(line: String) : Result(Record, Malformed)
  requires !line.contains?("\n")
  ensures result is Ok(r) implies r.status >= 100 and r.status <= 599 and !card?(r.path)

  fields = line.split(" ")
  return Error(Fields(count: fields.size)) if fields.size != 5
  at = try timestamp(field(fields, 0))
  method = try method_of(field(fields, 1))
  path = try path_of(field(fields, 2))
  status = try status_of(field(fields, 3))
  ms = try duration_of(field(fields, 4))
  Ok(Record(at: at, method: method, path: masked(path), status: status, ms: ms))
end

fn field(fields: List(String), i: UInt64) : String
  fields.get(i) or ""
end

fn timestamp(text: String) : Result(Time, Malformed)
  case Time.parse(text)
    Some(t): Ok(t)
    None: Error(Timestamp)
  end
end

# A method is one or more capital ASCII letters.
fn method_of(text: String) : Result(String, Malformed)
  return Error(Method) if text == ""
  return Error(Method) if !text.bytes.all?(fn(b) b >= 65 and b <= 90 end)
  Ok(text)
end

fn path_of(text: String) : Result(String, Malformed)
  return Error(Path) if !text.starts_with?("/")
  Ok(text)
end

fn status_of(text: String) : Result(Status, Malformed)
  n = text.to_u64 or 0
  return Error(StatusCode) if n < 100 or n > 599
  Ok(n.to_u16)
end

fn duration_of(text: String) : Result(UInt32, Malformed)
  case text.to_u64
    Some(n): duration_fits(n)
    None: Error(Duration)
  end
end

fn duration_fits(n: UInt64) : Result(UInt32, Malformed)
  case n.checked_to_u32
    Some(ms): Ok(ms)
    None: Error(Duration)
  end
end

# Every run of 16 or more ASCII digits becomes as many `*`; the rest is kept.
fn masked(text: String) : String
  ensures !card?(result)

  String.join(runs(text).map(fn(run) hidden(run) end), "")
end

fn card?(text: String) : Bool
  runs(text).any?(fn(run) card_run?(run) end)
end

fn hidden(run: String) : String
  return "*".repeat(run.size) if card_run?(run)
  run
end

fn card_run?(run: String) : Bool
  run.size >= 16 and digits?(run)
end

# The text cut into maximal runs of digits and of everything else, in order.
fn runs(text: String) : List(String)
  text.chars.reduce([], fn(so_far, c) extended(so_far, c) end)
end

fn extended(runs: List(String), c: String) : List(String)
  case runs.last
    Some(run):
      return runs.take(runs.size - 1).push("#{run}#{c}") if digits?(run) == digits?(c)
      runs.push(c)
    None: [c]
  end
end

fn digits?(text: String) : Bool
  text != "" and text.bytes.all?(fn(b) b >= 48 and b <= 57 end)
end

test "a line in the common format is a record"
  line = "2026-09-12T10:00:02Z POST /api/orders 500 340"
  assert parse_line(line) is Ok(r)
  assert r.at == Time.from_parts(2026, 9, 12, 10, 0, 2)
  assert r.method == "POST"
  assert r.path == "/api/orders"
  assert r.status == 500
  assert r.ms == 340
end

test "a line that does not fit names the first field that is wrong"
  assert parse_line("") is Error(Fields(1))
  assert parse_line("2026-09-12T10:00:02Z GET /a 200") is Error(Fields(4))
  assert parse_line("2026-09-12T10:00:02Z GET  /a 200 1") is Error(Fields(6))
  assert parse_line("yesterday GET /a 200 1") is Error(Timestamp)
  assert parse_line("2026-09-12T10:00:02Z get /a 200 1") is Error(Method)
  assert parse_line("2026-09-12T10:00:02Z GET a 200 1") is Error(Path)
  assert parse_line("2026-09-12T10:00:02Z GET /a 99 1") is Error(StatusCode)
  assert parse_line("2026-09-12T10:00:02Z GET /a 600 1") is Error(StatusCode)
  assert parse_line("2026-09-12T10:00:02Z GET /a ok 1") is Error(StatusCode)
  assert parse_line("2026-09-12T10:00:02Z GET /a 200 -1") is Error(Duration)
  assert parse_line("2026-09-12T10:00:02Z GET /a 200 4294967296") is Error(Duration)
end

test "the edges of status and duration are records"
  assert parse_line("2026-09-12T10:00:02Z GET /a 100 0") is Ok(_)
  assert parse_line("2026-09-12T10:00:02Z GET /a 599 4294967295") is Ok(_)
end

test "a card number in a path is masked, and shorter digit runs are kept"
  line = "2026-09-12T10:00:02Z GET /cards/4111111111111111/charge 200 9"
  assert parse_line(line) is Ok(r)
  assert r.path == "/cards/****************/charge"
  assert masked("/orders/123456789012345") == "/orders/123456789012345"
  assert masked("/x/12345678901234567") == "/x/*****************"
  assert masked("") == ""
  assert card?("/c/4111111111111111") and !card?("/c/4111-1111")
end

test rejects "a line that still holds its newline"
  parse_line("2026-09-12T10:00:02Z GET /a 200 1\n")
end

test rejects "a status outside 100 to 599"
  Record(at: Time.fixture(), method: "GET", path: "/a", status: 600, ms: 1)
end

property "any line either parses to a record in range or is malformed, and never crashes"
  for line in any(String) if !line.contains?("\n")
    if parse_line(line) is Ok(r)
      assert r.status >= 100 and r.status <= 599 and !card?(r.path)
    end
  end
end

verified: types, contracts, tests (7), property (200 seeds), sim (not run)
          proven: not run
