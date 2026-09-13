module Logstat.Parse
expose Record, Malformed, Status, Millis, parse_line, parse_bytes, timestamp, card?, slice, text_of, digits?, number

intent "Turn one log line into a record, or name why it is malformed; no line of bytes crashes it."

type Status = UInt64 where value >= 100 and value <= 599

type Millis = UInt64 where value <= 4_294_967_295

struct Record
  at: String
  seconds: UInt64
  method: String
  path: String
  status: Status
  ms: Millis
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
  requires !line.bytes.contains?(10)
  ensures result is Ok(r) implies r.status >= 100 and r.status <= 599

  parse_bytes(line.bytes)
end

fn parse_bytes(line: List(UInt8)) : Result(Record, Malformed)
  requires !line.contains?(10)
  ensures result is Ok(r) implies !card?(r.path.bytes)

  parts = split(line, 32)
  return Error(FieldCount(found: parts.size)) if parts.size != 5
  at = part(parts, 0)
  seconds = try seconds_of(at)
  method = try method_of(part(parts, 1))
  path = try path_of(part(parts, 2))
  status = try status_of(part(parts, 3))
  ms = try ms_of(part(parts, 4))
  Ok(Record(at: text_of(at), seconds: seconds, method: method, path: path, status: status, ms: ms))
end

fn seconds_of(bytes: List(UInt8)) : Result(UInt64, Malformed)
  case timestamp(bytes)
    Some(seconds): Ok(seconds)
    None: Error(BadTimestamp)
  end
end

fn method_of(bytes: List(UInt8)) : Result(String, Malformed)
  upper = bytes.filter(fn(b) b >= 65 and b <= 90 end)
  return Error(BadMethod) if bytes.size == 0 or upper.size != bytes.size
  Ok(text_of(bytes))
end

fn path_of(bytes: List(UInt8)) : Result(String, Malformed)
  plain = bytes.filter(fn(b) b >= 33 and b <= 126 and b != 34 and b != 92 end)
  return Error(BadPath) if bytes.first != Some(47) or plain.size != bytes.size
  Ok(text_of(mask_cards(bytes)))
end

fn status_of(bytes: List(UInt8)) : Result(UInt64, Malformed)
  return Error(BadStatus) if !digits?(bytes) or bytes.size > 3
  status = number(bytes)
  return Error(BadStatus) if status < 100 or status > 599
  Ok(status)
end

fn ms_of(bytes: List(UInt8)) : Result(UInt64, Malformed)
  return Error(BadDuration) if !digits?(bytes) or bytes.size > 10
  ms = number(bytes)
  return Error(BadDuration) if ms > 4_294_967_295
  Ok(ms)
end

fn timestamp(bytes: List(UInt8)) : Option(UInt64)
  return None if !shaped?(bytes)
  year = number(slice(bytes, 0, 4))
  month = number(slice(bytes, 5, 7))
  day = number(slice(bytes, 8, 10))
  hours = number(slice(bytes, 11, 13))
  mins = number(slice(bytes, 14, 16))
  secs = number(slice(bytes, 17, 19))
  return None if month < 1 or month > 12 or day < 1 or day > days_in(year, month)
  return None if hours > 23 or mins > 59 or secs > 59
  Some(days_since_origin(year, month, day) * 86_400 + hours * 3_600 + mins * 60 + secs)
end

fn shaped?(bytes: List(UInt8)) : Bool
  template = "0000-00-00T00:00:00Z".bytes
  return false if bytes.size != template.size
  checked = bytes.reduce((0, true), fn(acc, b)
    want = slice(template, acc.0, acc.0 + 1).first or 0
    (acc.0 + 1, acc.1 and fits?(b, want))
  end)
  checked.1
end

fn fits?(b: UInt8, want: UInt8) : Bool
  return digit?(b) if want == 48
  b == want
end

fn days_in(year: UInt64, month: UInt64) : UInt64
  requires month >= 1 and month <= 12

  case month
    2:
      if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
        29
      else
        28
      end
    4: 30
    6: 30
    9: 30
    11: 30
    _: 31
  end
end

# Days from a fixed origin 400 years before year 0, so every count is positive (Hinnant's
# days_from_civil). Only differences between two of these are ever shown.
fn days_since_origin(year: UInt64, month: UInt64, day: UInt64) : UInt64
  requires month >= 1 and month <= 12 and day >= 1

  y = if month <= 2
    year + 399
  else
    year + 400
  end
  era = y / 400
  of_era = y - era * 400
  of_year = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
  era * 146_097 + of_era * 365 + of_era / 4 - of_era / 100 + of_year
end

fn mask_cards(bytes: List(UInt8)) : List(UInt8)
  ensures !card?(result)
  ensures result.size == bytes.size

  done = bytes.reduce(([], []), fn(acc, b)
    if digit?(b)
      (acc.0, acc.1.push(b))
    else
      (append(acc.0, masked(acc.1)).push(b), [])
    end
  end)
  append(done.0, masked(done.1))
end

fn masked(run: List(UInt8)) : List(UInt8)
  return run if run.size < 16
  run.map(fn(b) b - b + 42 end)
end

fn card?(bytes: List(UInt8)) : Bool
  runs = bytes.reduce((0, 0), fn(acc, b)
    if digit?(b)
      (acc.0 + 1, longer(acc.0 + 1, acc.1))
    else
      (0, acc.1)
    end
  end)
  runs.1 >= 16
end

fn longer(a: UInt64, b: UInt64) : UInt64
  return a if a > b
  b
end

fn split(bytes: List(UInt8), separator: UInt8) : List(List(UInt8))
  parts = bytes.reduce(([], []), fn(acc, b)
    if b == separator
      (acc.0.push(acc.1), [])
    else
      (acc.0, acc.1.push(b))
    end
  end)
  parts.0.push(parts.1)
end

fn part(parts: List(List(UInt8)), index: UInt64) : List(UInt8)
  found = parts.reduce((0, []), fn(acc, p)
    if acc.0 == index
      (acc.0 + 1, p)
    else
      (acc.0 + 1, acc.1)
    end
  end)
  found.1
end

fn slice(bytes: List(UInt8), from: UInt64, to: UInt64) : List(UInt8)
  requires from <= to

  picked = bytes.reduce((0, []), fn(acc, b)
    if acc.0 >= from and acc.0 < to
      (acc.0 + 1, acc.1.push(b))
    else
      (acc.0 + 1, acc.1)
    end
  end)
  picked.1
end

fn append(front: List(UInt8), back: List(UInt8)) : List(UInt8)
  back.reduce(front, fn(acc, b) acc.push(b) end)
end

fn digit?(b: UInt8) : Bool
  b >= 48 and b <= 57
end

fn digits?(bytes: List(UInt8)) : Bool
  bytes.size > 0 and bytes.filter(fn(b) !digit?(b) end).size == 0
end

fn number(bytes: List(UInt8)) : UInt64
  requires digits?(bytes) and bytes.size <= 10

  bytes.reduce(0, fn(n, b) n * 10 + digit(b) end)
end

# The stdlib has no conversion between integer widths, so a digit's value is spelled out.
fn digit(b: UInt8) : UInt64
  requires digit?(b)

  case b
    48: 0
    49: 1
    50: 2
    51: 3
    52: 4
    53: 5
    54: 6
    55: 7
    56: 8
    _: 9
  end
end

# The stdlib cannot turn bytes back into a String, so each printable ASCII byte is looked
# up in this table and the text is built by interpolation.
fn text_of(bytes: List(UInt8)) : String
  requires bytes.filter(fn(b) b < 32 or b > 126 end).size == 0

  bytes.reduce("", fn(text, b) "#{text}#{char(b)}" end)
end

fn char(b: UInt8) : String
  requires b >= 32 and b <= 126

  found = ascii().reduce((32, ""), fn(acc, c)
    if acc.0 == b
      (acc.0 + 1, c)
    else
      (acc.0 + 1, acc.1)
    end
  end)
  found.1
end

fn ascii() : List(String)
  [" ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~"]
end

test "a line in the common format is a record"
  outcome = parse_line("2026-09-12T10:00:02Z POST /api/orders 500 340")
  assert outcome is Ok(r)
  assert r.at == "2026-09-12T10:00:02Z"
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

test "timestamps count seconds, so a span is a subtraction"
  a = timestamp("2026-09-12T10:00:02Z".bytes) or 0
  b = timestamp("2026-09-13T10:01:03Z".bytes) or 0
  assert b - a == 86_461
  new_year = timestamp("2025-01-01T00:00:00Z".bytes) or 0
  last_second = timestamp("2024-12-31T23:59:59Z".bytes) or 0
  assert new_year - last_second == 1
  assert timestamp("2024-02-29T00:00:00Z".bytes) is Some(_)
  assert timestamp("2023-02-29T00:00:00Z".bytes) is None
  assert timestamp("2026-09-12T24:00:00Z".bytes) is None
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

test rejects "bytes that still hold a newline"
  parse_bytes("2026-09-12T10:00:02Z GET /a 200 1\n".bytes)
end

test rejects "a slice that ends before it starts"
  slice("abc".bytes, 2, 1)
end

test rejects "a month that does not exist has no length"
  days_in(2026, 13)
end

test rejects "a day zero has no count"
  days_since_origin(2026, 9, 0)
end

test rejects "a number with a letter in it"
  number("12a".bytes)
end

test rejects "a letter is not a digit"
  digit(65)
end

test rejects "a control byte has no text"
  text_of("a\tb".bytes)
end

test rejects "a byte above ASCII has no character"
  char(200)
end

property "no sixteen-digit run survives a parse"
  for n in any(UInt64)
    card = n % 9_000_000_000_000_000 + 1_000_000_000_000_000
    outcome = parse_line("2026-09-12T10:00:09Z GET /c/#{card}/x 200 1")
    assert outcome is Ok(r) and !card?(r.path.bytes)
  end
end
