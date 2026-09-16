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
  # body gone; regenerate
end

# The value is everything after the key's space, spaces included, and may be empty.
fn set_of(words: List(String)) : Result(Request, Refusal)
  # body gone; regenerate
end

fn get_of(words: List(String)) : Result(Request, Refusal)
  # body gone; regenerate
end

fn del_of(words: List(String)) : Result(Request, Refusal)
  # body gone; regenerate
end

fn incr_of(words: List(String)) : Result(Request, Refusal)
  # body gone; regenerate
end

# KEYS alone, or KEYS with an empty prefix, lists every key.
fn keys_of(words: List(String)) : Result(Request, Refusal)
  # body gone; regenerate
end

fn only_key(words: List(String)) : Result(String, Refusal)
  # body gone; regenerate
end

fn bare(words: List(String), request: Request) : Result(Request, Refusal)
  # body gone; regenerate
end

# A key is 1 to 256 bytes, with no space and no control character.
fn key?(text: String) : Bool
  # body gone; regenerate
end

# A value is at most 60 KiB and holds no newline.
fn value?(text: String) : Bool
  # body gone; regenerate
end

# Whether the key a request names, if it names one, keeps the key rules.
fn keyed?(request: Request) : Bool
  # body gone; regenerate
end

# The line a request is written as, without its newline; parse reads it back.
fn line_of(request: Request) : String
  # body gone; regenerate
end

# The text a response is on the wire: one line, or for KEYS a count line and a line per key.
fn render(response: Response) : String
  # body gone; regenerate
end

fn listed(keys: List(String)) : String
  # body gone; regenerate
end

fn counted(c: Counts) : String
  # body gone; regenerate
end

fn word_of(reason: Refusal) : String
  # body gone; regenerate
end

# How many key lines follow a response's first line: the count after KEYS, else none.
fn follows(first: String) : UInt64
  # body gone; regenerate
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
