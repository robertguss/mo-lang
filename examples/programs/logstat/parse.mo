module Logstat.Parse
expose Entry, Malformed, Printable, Status, parse, entries, masked, card?

intent "Read one log line, <ISO-8601 timestamp> <method> <path> <status> <duration_ms> separated by single spaces, as an entry, or say which part does not fit; a run of 16 digits in the timestamp or the path is masked before the entry exists, so no entry holds a card number."

never "an entry holds a card number"
  for e in Entry.all
    card?(e.path) or card?(e.stamp)
  end
end

# An HTTP status, 100 to 599.
type Status = UInt16 where value >= 100 and value <= 599

# Text that may be printed: no run of 16 digits, a card number's length, is in it.
type Printable = String where !card?(value)

# One well-formed line. stamp is the timestamp as written, masked; at is what it means.
struct Entry
  at: Time
  stamp: Printable
  method: String
  path: Printable
  status: Status
  duration_ms: UInt32
end

enum Malformed
  FieldCount
  BadTime
  BadMethod
  BadPath
  BadStatus
  BadDuration
end

fn parse(line: String) : Result(Entry, Malformed)
  ensures result is Ok(e) implies e.status >= 100 and e.status <= 599 and !card?(e.path)

  fields = line.split(" ")
  return Error(FieldCount) if fields.size != 5
  stamp = fields.get(0) or ""
  at = try time_of(stamp)
  method = try method_of(fields.get(1) or "")
  path = try path_of(fields.get(2) or "")
  status = try status_of(fields.get(3) or "")
  duration_ms = try duration_of(fields.get(4) or "")
  Ok(Entry(at: at, stamp: masked(stamp), method: method, path: masked(path), status: status,
    duration_ms: duration_ms))
end

# The entries among some lines, the malformed ones left out.
fn entries(lines: List(String)) : List(Entry)
  lines.flat_map(fn(line) well_formed(line) end)
end

fn well_formed(line: String) : List(Entry)
  case parse(line)
    Ok(e): [e]
    Error(_): []
  end
end

# A timestamp is whatever Time.parse reads as an ISO-8601 instant.
fn time_of(text: String) : Result(Time, Malformed)
  case Time.parse(text)
    Some(at): Ok(at)
    None: Error(BadTime)
  end
end

# A method is one or more ASCII capital letters.
fn method_of(text: String) : Result(String, Malformed)
  return Error(BadMethod) if text == "" or !text.bytes.all?(fn(b) b >= 65 and b <= 90 end)
  Ok(text)
end

# A path starts with a slash.
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
    Some(n): fitting(n)
    None: Error(BadDuration)
  end
end

fn fitting(n: UInt64) : Result(UInt32, Malformed)
  case n.checked_to_u32
    Some(ms): Ok(ms)
    None: Error(BadDuration)
  end
end

fn digit?(b: UInt8) : Bool
  b >= 48 and b <= 57
end

# Whether the text holds a run of 16 or more digits.
fn card?(text: String) : Bool
  text.bytes.reduce((0, 0), fn(runs, b) stepped(runs, digit?(b)) end).0 >= 16
end

# The longest run of digits so far, and the run that ends at this byte.
fn stepped(runs: (UInt64, UInt64), digit: Bool) : (UInt64, UInt64)
  return (runs.0, 0) if !digit
  (max_of(runs.0, runs.1 + 1), runs.1 + 1)
end

# The text with every digit of each run of 16 or more replaced by *.
fn masked(text: String) : Printable
  return text if !card?(text)
  pieces = text.chars.reduce(("", ""), fn(so_far, c) masking(so_far, c) end)
  "#{pieces.0}#{hidden(pieces.1)}"
end

# What is written so far, and the run of digits not yet written.
fn masking(so_far: (String, String), c: String) : (String, String)
  if c.byte_size == 1 and digit?(c.bytes.first or 0)
    return (so_far.0, "#{so_far.1}#{c}")
  end
  ("#{so_far.0}#{hidden(so_far.1)}#{c}", "")
end

fn hidden(run: String) : String
  return "*".repeat(run.size) if run.size >= 16
  run
end

test "a line of five fields is an entry"
  parsed = parse("2026-09-12T10:00:02Z POST /api/orders 500 340")
  assert parsed is Ok(e)
  assert e.stamp == "2026-09-12T10:00:02Z"
  assert e.at == Time.from_parts(2026, 9, 12, 10, 0, 2)
  assert e.method == "POST"
  assert e.path == "/api/orders"
  assert e.status == 500
  assert e.duration_ms == 340
end

test "a line that does not fit says which part"
  assert parse("") == Error(FieldCount)
  assert parse("2026-09-12T10:00:02Z POST /api/orders 500") == Error(FieldCount)
  assert parse("2026-09-12T10:00:02Z  POST /api/orders 500 340") == Error(FieldCount)
  assert parse("yesterday POST /api/orders 500 340") == Error(BadTime)
  assert parse("2026-09-12T10:00:02Z post /api/orders 500 340") == Error(BadMethod)
  assert parse("2026-09-12T10:00:02Z POST api/orders 500 340") == Error(BadPath)
  assert parse("2026-09-12T10:00:02Z POST /api/orders ok 340") == Error(BadStatus)
  assert parse("2026-09-12T10:00:02Z POST /api/orders 500 -1") == Error(BadDuration)
end

test "a status outside 100 to 599 or a duration past UInt32 is malformed"
  assert parse("2026-09-12T10:00:02Z GET /a 99 1") == Error(BadStatus)
  assert parse("2026-09-12T10:00:02Z GET /a 600 1") == Error(BadStatus)
  assert parse("2026-09-12T10:00:02Z GET /a 100 4294967295") is Ok(_)
  assert parse("2026-09-12T10:00:02Z GET /a 599 4294967296") == Error(BadDuration)
end

test "a run of 16 digits in a path is masked, and a shorter run is kept"
  assert parse("2026-09-12T10:00:02Z GET /cards/4111111111111111/charges 200 5") is Ok(e)
  assert e.path == "/cards/****************/charges"
  assert masked("/a/123456789012345") == "/a/123456789012345"
  assert masked("/a/41111111111111112/b/1") == "/a/*****************/b/1"
  assert card?("4111111111111111")
  assert !card?("411111111111111")
end

test "the entries of some lines leave the malformed ones out"
  lines = ["2026-09-12T10:00:01Z GET /a 200 1", "oops", "2026-09-12T10:00:02Z GET /b 200 2"]
  assert entries(lines).map(fn(e) e.path end) == ["/a", "/b"]
end

test rejects "an entry built with a card number in its path"
  e = Entry(at: Time.fixture(), stamp: "t", method: "GET", path: "/c/4111111111111111", status: 200,
    duration_ms: 1)
  assert e.status == 200
end

property "any status and duration parse exactly when the status is 100 to 599 and the duration fits UInt32"
  for code in any(UInt16), ms in any(UInt64)
    fits = code >= 100 and code <= 599 and ms <= 4_294_967_295
    assert (parse("2026-09-12T10:00:02Z GET /a #{code} #{ms}") is Ok(_)) == fits
  end
end

property "no masked text holds a card number"
  for text in any(String)
    assert !card?(masked(text))
  end
end
