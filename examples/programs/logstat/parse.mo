module Logstat.Parse
expose Record, Malformed, parse_line, status_code, masked, card_number?

intent "Read one log line into a record, or say why it is malformed; a card number in a path never survives the reading."

never "a record holds a card number"
  for r in Record.all
    card_number?(r.path)
  end
end

struct Record
  at: Time
  method: String
  path: String
  status: UInt16
  duration_ms: UInt32
end

enum Malformed
  Fields(count: UInt64)
  Timestamp(text: String)
  Method(text: String)
  Path(text: String)
  Status(text: String)
  Duration(text: String)
end

fn parse_line(line: String) : Result(Record, Malformed)
  ensures result is Ok(r) implies r.status >= 100 and r.status <= 599

  parts = line.split(" ").filter(fn(p) p != "" end)
  return Error(Fields(count: parts.size)) if parts.size != 5

  at = try timestamp(parts.get(0) or "")
  method = try method_name(parts.get(1) or "")
  path = try path_text(parts.get(2) or "")
  status = try status_text(parts.get(3) or "")
  duration = try duration_text(parts.get(4) or "")
  Ok(Record(at: at, method: method, path: masked(path), status: status, duration_ms: duration))
end

fn timestamp(text: String) : Result(Time, Malformed)
  case Time.parse(text)
    Some(t): Ok(t)
    None: Error(Timestamp(text: text))
  end
end

fn method_name(text: String) : Result(String, Malformed)
  return Error(Method(text: text)) if !text.bytes.all?(fn(b) b >= 65 and b <= 90 end)
  Ok(text)
end

fn path_text(text: String) : Result(String, Malformed)
  return Error(Path(text: text)) if !text.starts_with?("/")
  Ok(text)
end

fn status_text(text: String) : Result(UInt16, Malformed)
  case text.to_u64
    Some(n): status_in_range(n, text)
    None: Error(Status(text: text))
  end
end

fn status_in_range(n: UInt64, text: String) : Result(UInt16, Malformed)
  return Error(Status(text: text)) if n < 100 or n > 599
  Ok(status_code(n))
end

# A status the caller has already found in range, as the record's width.
fn status_code(n: UInt64) : UInt16
  requires n >= 100 and n <= 599

  n.to_u16
end

fn duration_text(text: String) : Result(UInt32, Malformed)
  case text.to_u64
    Some(n): duration_width(n, text)
    None: Error(Duration(text: text))
  end
end

fn duration_width(n: UInt64, text: String) : Result(UInt32, Malformed)
  case n.checked_to_u32
    Some(ms): Ok(ms)
    None: Error(Duration(text: text))
  end
end

fn digit?(c: String) : Bool
  c.bytes.size == 1 and c.bytes.all?(fn(b) b >= 48 and b <= 57 end)
end

# The text cut into runs: each run is all digits or holds no digit.
fn runs(text: String) : List(String)
  text.chars.reduce([], fn(so_far, c) grown(so_far, c) end)
end

fn grown(runs: List(String), c: String) : List(String)
  last = runs.last or ""
  if last != "" and digit?(last.slice(0, 1)) == digit?(c)
    return runs.take(runs.size - 1).push("#{last}#{c}")
  end
  runs.push(c)
end

fn card_run?(run: String) : Bool
  run.size >= 16 and digit?(run.slice(0, 1))
end

fn card_number?(text: String) : Bool
  runs(text).any?(fn(run) card_run?(run) end)
end

# Every run of 16 or more digits becomes as many stars.
fn masked(text: String) : String
  String.join(runs(text).map(fn(run) hidden(run) end), "")
end

fn hidden(run: String) : String
  return "*".repeat(run.size) if card_run?(run)
  run
end

test "a well-formed line is a record"
  line = "2026-09-12T10:00:02Z POST /api/orders 500 340"
  assert parse_line(line) is Ok(r)
  assert r.at == Time.from_parts(2026, 9, 12, 10, 0, 2)
  assert r.method == "POST"
  assert r.path == "/api/orders"
  assert r.status == 500
  assert r.duration_ms == 340
end

test "a line that does not fit says which part is wrong"
  assert parse_line("") is Error(Fields(0))
  assert parse_line("2026-09-12T10:00:02Z GET /a 200") is Error(Fields(4))
  assert parse_line("yesterday GET /a 200 1") is Error(Timestamp("yesterday"))
  assert parse_line("2026-09-12T10:00:02Z get /a 200 1") is Error(Method("get"))
  assert parse_line("2026-09-12T10:00:02Z GET a 200 1") is Error(Path("a"))
  assert parse_line("2026-09-12T10:00:02Z GET /a 99 1") is Error(Status("99"))
  assert parse_line("2026-09-12T10:00:02Z GET /a 600 1") is Error(Status("600"))
  assert parse_line("2026-09-12T10:00:02Z GET /a 2xx 1") is Error(Status("2xx"))
  assert parse_line("2026-09-12T10:00:02Z GET /a 200 -1") is Error(Duration("-1"))
  assert parse_line("2026-09-12T10:00:02Z GET /a 200 4294967296") is Error(Duration("4294967296"))
end

test "the edges of status and duration are records"
  assert parse_line("2026-09-12T10:00:02Z GET /a 100 0") is Ok(low)
  assert low.status == 100
  assert parse_line("2026-09-12T10:00:02Z GET /a 599 4294967295") is Ok(high)
  assert high.duration_ms == 4_294_967_295
end

test "a card number in a path is starred, and shorter digit runs are kept"
  assert masked("/pay/4111111111111111/refund") == "/pay/****************/refund"
  assert masked("/users/123456789012345") == "/users/123456789012345"
  assert card_number?("/x/12345678901234567")
  assert !card_number?("/x/1234-5678-9012-3456")
  line = "2026-09-12T10:00:02Z GET /cards/4111111111111111 200 5"
  assert parse_line(line) is Ok(r)
  assert r.path == "/cards/****************"
end

test "a status in range keeps its value"
  assert status_code(404) == 404
end

test rejects "a status below 100"
  status_code(99)
end

test rejects "a status above 599"
  status_code(600)
end
