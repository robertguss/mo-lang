module Kv.Protocol
expose Request, Response, Refusal, Counts, parse, render, line_of, follows, key?, value?

intent "Read one line of the kv protocol into a request, or refuse it as malformed, and write each response as the lines a client reads."

enum Request
  Set(key: String, value: String)
  Get(key: String)
  Del(key: String)
  Incr(key: String, by: Int64)
  Keys(prefix: String)
  Stats
  Quit
end

enum Refusal
  Malformed
  NotANumber
  Overflow
  Busy
  Io
  Full
end

struct Counts
  keys: UInt64
  sets: UInt64
  gets: UInt64
  log_bytes: UInt64
  uptime_ms: Int64
end

enum Response
  Done
  Found(value: String)
  Absent
  Listed(keys: List(String))
  Counted(counts: Counts)
  Bye
  Failed(reason: Refusal)
end

# One request line, without its newline. Every refusal here is Malformed.
fn parse(line: String) : Result(Request, Refusal)
  requires !line.contains?("\n")
  ensures result is Ok(request) implies keyed?(request)
  ensures result is Error(reason) implies reason == Malformed

  words = line.split(" ")
  case words.first or ""
    "SET": set_of(words)
    "GET": get_of(words)
    "DEL": del_of(words)
    "INCR": incr_of(words)
    "KEYS": keys_of(words)
    "STATS": bare(words, Stats)
    "QUIT": bare(words, Quit)
    _: Error(Malformed)
  end
end

# The value is everything after the key's space, spaces included, and may be empty.
fn set_of(words: List(String)) : Result(Request, Refusal)
  return Error(Malformed) if words.size < 3
  key = words.get(1) or ""
  value = String.join(words.drop(2), " ")
  return Error(Malformed) if !key?(key) or !value?(value)
  Ok(Set(key: key, value: value))
end

fn get_of(words: List(String)) : Result(Request, Refusal)
  key = try only_key(words)
  Ok(Get(key: key))
end

fn del_of(words: List(String)) : Result(Request, Refusal)
  key = try only_key(words)
  Ok(Del(key: key))
end

fn incr_of(words: List(String)) : Result(Request, Refusal)
  return Error(Malformed) if words.size != 3
  key = words.get(1) or ""
  return Error(Malformed) if !key?(key)
  case (words.get(2) or "").to_i64
    Some(by): Ok(Incr(key: key, by: by))
    None: Error(Malformed)
  end
end

# KEYS alone, or KEYS with an empty prefix, lists every key.
fn keys_of(words: List(String)) : Result(Request, Refusal)
  return Ok(Keys(prefix: "")) if words.size == 1
  return Error(Malformed) if words.size != 2
  Ok(Keys(prefix: words.get(1) or ""))
end

fn only_key(words: List(String)) : Result(String, Refusal)
  return Error(Malformed) if words.size != 2
  key = words.get(1) or ""
  return Error(Malformed) if !key?(key)
  Ok(key)
end

fn bare(words: List(String), request: Request) : Result(Request, Refusal)
  return Error(Malformed) if words.size != 1
  Ok(request)
end

# A key is 1 to 256 bytes, with no space and no control character.
fn key?(text: String) : Bool
  size = text.byte_size
  return false if size < 1 or size > 256
  text.bytes.all?(fn(b) b > 32 and b != 127 end)
end

# A value is at most 60 KiB and holds no newline.
fn value?(text: String) : Bool
  text.byte_size <= 61_440 and !text.contains?("\n")
end

# Whether the key a request names, if it names one, keeps the key rules.
fn keyed?(request: Request) : Bool
  case request
    Set(key: key, value: _): key?(key)
    Get(key): key?(key)
    Del(key): key?(key)
    Incr(key: key, by: _): key?(key)
    Keys(_) | Stats | Quit: true
  end
end

# The line a request is written as, without its newline; parse reads it back.
fn line_of(request: Request) : String
  case request
    Set(key: key, value: value): "SET #{key} #{value}"
    Get(key): "GET #{key}"
    Del(key): "DEL #{key}"
    Incr(key: key, by: by): "INCR #{key} #{by}"
    Keys(prefix): "KEYS #{prefix}"
    Stats: "STATS"
    Quit: "QUIT"
  end
end

# The text a response is on the wire: one line, or for KEYS a count line and a line per key.
fn render(response: Response) : String
  case response
    Done: "OK\n"
    Found(value): "VALUE #{value}\n"
    Absent: "MISSING\n"
    Listed(keys): listed(keys)
    Counted(counts): counted(counts)
    Bye: "BYE\n"
    Failed(reason): "ERR #{word_of(reason)}\n"
  end
end

fn listed(keys: List(String)) : String
  String.join(["KEYS #{keys.size}\n"].concat(keys.map(fn(key) "#{key}\n" end)), "")
end

fn counted(c: Counts) : String
  "STATS keys=#{c.keys} sets=#{c.sets} gets=#{c.gets} log_bytes=#{c.log_bytes} uptime_ms=#{c.uptime_ms}\n"
end

fn word_of(reason: Refusal) : String
  case reason
    Malformed: "malformed"
    NotANumber: "not_a_number"
    Overflow: "overflow"
    Busy: "busy"
    Io: "io"
    Full: "full"
  end
end

# How many key lines follow a response's first line: the count after KEYS, else none.
fn follows(first: String) : UInt64
  return 0 if !first.starts_with?("KEYS ")
  first.slice(5, first.size).to_u64 or 0
end

test "each command parses into its request"
  greeting = Set(key: "greeting", value: "hello wide world")
  assert parse("SET greeting hello wide world") == Ok(greeting)
  assert parse("SET empty ") == Ok(Set(key: "empty", value: ""))
  assert parse("SET k  two  spaces ") == Ok(Set(key: "k", value: " two  spaces "))
  assert parse("GET greeting") == Ok(Get(key: "greeting"))
  assert parse("DEL greeting") == Ok(Del(key: "greeting"))
  assert parse("INCR hits 5") == Ok(Incr(key: "hits", by: 5))
  assert parse("INCR hits -9223372036854775808") is Ok(Incr(key: "hits", by: -9223372036854775808))
  assert parse("KEYS user:") == Ok(Keys(prefix: "user:"))
  assert parse("KEYS") == Ok(Keys(prefix: ""))
  assert parse("KEYS ") == Ok(Keys(prefix: ""))
  assert parse("STATS") == Ok(Stats)
  assert parse("QUIT") == Ok(Quit)
end

test "a line that is not a request is malformed"
  assert parse("") == Error(Malformed)
  assert parse("set a b") == Error(Malformed)
  assert parse("SET a") == Error(Malformed)
  assert parse("SET  value") == Error(Malformed)
  assert parse("GET") == Error(Malformed)
  assert parse("GET a b") == Error(Malformed)
  assert parse("GET a ") == Error(Malformed)
  assert parse("DEL") == Error(Malformed)
  assert parse("INCR a") == Error(Malformed)
  assert parse("INCR a x") == Error(Malformed)
  assert parse("INCR a 1 2") == Error(Malformed)
  assert parse("INCR a 9223372036854775808") == Error(Malformed)
  assert parse("KEYS a b") == Error(Malformed)
  assert parse("STATS now") == Error(Malformed)
  assert parse("QUIT ") == Error(Malformed)
  assert parse(" GET a") == Error(Malformed)
end

test "a key is 1 to 256 bytes, counted in bytes, with no space or control character"
  assert key?("k".repeat(256))
  assert !key?("k".repeat(257))
  assert key?("é".repeat(128))
  assert !key?("é".repeat(129))
  assert !key?("")
  assert !key?("a b")
  assert !key?("a\tb")
  assert !key?(String.from_bytes([97, 127]) or "a b")
  assert parse("GET #{"k".repeat(257)}") == Error(Malformed)
end

test "a value is up to 60 KiB, counted in bytes, and may hold spaces"
  assert value?("")
  assert value?("x".repeat(61_440))
  assert !value?("x".repeat(61_441))
  assert !value?("é".repeat(30_721))
  assert parse("SET big #{"x".repeat(61_441)}") == Error(Malformed)
end

test "every response renders as the lines a client reads"
  assert render(Done) == "OK\n"
  assert render(Found(value: "hello world")) == "VALUE hello world\n"
  assert render(Found(value: "")) == "VALUE \n"
  assert render(Absent) == "MISSING\n"
  assert render(Listed(keys: ["a", "b"])) == "KEYS 2\na\nb\n"
  assert render(Listed(keys: [])) == "KEYS 0\n"
  counts = Counts(keys: 2, sets: 3, gets: 4, log_bytes: 12_345, uptime_ms: 1_000)
  assert render(Counted(counts: counts)) == "STATS keys=2 sets=3 gets=4 log_bytes=12345 uptime_ms=1000\n"
  assert render(Bye) == "BYE\n"
  assert render(Failed(reason: NotANumber)) == "ERR not_a_number\n"
  assert render(Failed(reason: Busy)) == "ERR busy\n"
end

test "follows counts the key lines after a KEYS line, and nothing after any other"
  assert follows("KEYS 2") == 2
  assert follows("KEYS 0") == 0
  assert follows("VALUE KEYS 2") == 0
  assert follows("OK") == 0
end

test rejects "a line handed over with its newline"
  parse("GET a\n")
end

property "every request's line parses back to the request"
  for key in any(String), value in any(String), by in any(Int64) if key?(key) and value?(value)
    named = [Get(key: key), Del(key: key), Keys(prefix: key), Incr(key: key, by: by)]
    for request in named.push(Set(key: key, value: value))
      assert parse(line_of(request)) == Ok(request)
    end
  end
end

verified: types, contracts, tests (8), property (200 seeds), sim (not run)
          proven: not run
