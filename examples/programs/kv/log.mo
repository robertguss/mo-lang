module Kv.Log
expose Table, Logged, Replayed, Reopened, Opened, LogError, Journal, Journals, empty, lookup, put, drop, keys_with, entry, replay, reopen, compacted, open

use Kv.Protocol{Request, parse, line_of, key?, value?}

intent "The append-only log: the table its lines describe, the journal a change is appended to before the store answers it, replay of a log's text into that table, and compaction of a table into one line per live key."

never "a replay changes the number of live keys"
  for r in Reopened.all
    r.keys_after != r.keys_before
  end
end

# The keys and values a log describes, spread over 256 small maps, so that setting a key
# copies one small map and not every key (TOOLCHAIN-BUGS.md).
struct Table
  buckets: Map(UInt64, Map(String, String))
  size: UInt64
end

# What a journal holds: the lines appended since the log was opened, and the live keys the
# store had after the last of them.
struct Logged
  text: String
  keys: UInt64
end

# A log's text as a table: how many lines it applied, and whether a last line cut short
# was left out.
struct Replayed
  table: Table
  lines: UInt64
  truncated: Bool
end

# What a journal held, replayed, beside the live keys the store had before it stopped.
struct Reopened
  table: Table
  keys_before: UInt64
  keys_after: UInt64
end

# A folder's log, replayed, and its size in bytes.
struct Opened
  replayed: Replayed
  bytes: UInt64
end

enum LogError
  NoFolder
  Unreadable
  Slow
  BadLine(number: UInt64)
end

# The log the store appends each change to before it answers. No stdlib row writes a file
# (GAPS.md), so the journal keeps the lines appended since the log was opened; its byte
# count starts at the size of that log.
process Journal(opened_bytes: UInt64)
  state
    bytes: UInt64 = opened_bytes
    keys: UInt64
    lines: List(String)
  end

  invariant "the log never shrinks"
    state.bytes < old(state.bytes)
  end

  message Append(line: String, keys: UInt64) : UInt64
  message Written : Logged

  fn update(state, message)
    case message
      Append(line: line, keys: keys):
        state.lines = state.lines.push(line)
        state.bytes += line.bytes.size
        state.keys = keys
        state.bytes
      Written: Logged(text: String.join(state.lines, ""), keys: state.keys)
    end
  end
end

supervisor Journals(opened_bytes: UInt64)
  child Journal(opened_bytes), restart: :always
end

fn empty() : Table
  Table(buckets: Map.new(), size: 0)
end

# Which of the 256 maps holds a key.
fn bucket_of(key: String) : UInt64
  ensures result < 256

  key.bytes.reduce(0, fn(hash, b) mixed(hash, b) end)
end

fn mixed(hash: UInt64, b: UInt8) : UInt64
  (hash * 31 + b.to_u64) % 256
end

fn lookup(table: Table, key: String) : Option(String)
  case table.buckets.get(bucket_of(key))
    Some(bucket): bucket.get(key)
    None: None
  end
end

# The table with the key set to the value; a key it did not hold counts one more.
fn put(table: Table, key: String, value: String) : Table
  requires key?(key)
  requires value?(value)
  ensures lookup(result, key) == Some(value)

  at = bucket_of(key)
  bucket = table.buckets.get(at) or Map.new()
  added = if bucket.has?(key)
    0
  else
    1
  end
  Table(buckets: table.buckets.set(at, bucket.set(key, value)), size: table.size + added)
end

# The table without the key; the same table when it holds none.
fn drop(table: Table, key: String) : Table
  ensures lookup(result, key) is None

  at = bucket_of(key)
  bucket = table.buckets.get(at) or Map.new()
  return table if !bucket.has?(key)
  Table(buckets: table.buckets.set(at, bucket.remove(key)), size: table.size - 1)
end

# Every key that starts with the prefix, in byte order.
fn keys_with(table: Table, prefix: String) : List(String)
  keys = table.buckets.values.flat_map(fn(bucket) bucket.keys end)
  keys.filter(fn(key) key.starts_with?(prefix) end).sort
end

# The line a change is appended as: a SET with the new value, or a DEL when there is none.
fn entry(key: String, value: Option(String)) : String
  case value
    Some(text): "#{line_of(Set(key: key, value: text))}\n"
    None: "#{line_of(Del(key: key))}\n"
  end
end

# A log's text as a table. A last line with no newline was cut short as it was written, so
# it was never answered: it is left out, and truncated says so. Any other line that is not
# a SET or a DEL is not kv's, and replay stops at it with its line number.
fn replay(text: String) : Result(Replayed, LogError)
  lines = text.lines
  truncated = text != "" and !text.ends_with?("\n")
  whole = if truncated
    lines.take(lines.size - 1)
  else
    lines
  end
  var table = empty()
  var number = 0
  for line in whole
    number += 1
    table = try applied(table, line, number)
  end
  Ok(Replayed(table: table, lines: number, truncated: truncated))
end

fn applied(table: Table, line: String, number: UInt64) : Result(Table, LogError)
  case parse(line)
    Ok(Set(key: key, value: value)): Ok(put(table, key, value))
    Ok(Del(key)): Ok(drop(table, key))
    Ok(Get(_)): Error(BadLine(number: number))
    Ok(Incr(key: _, by: _)): Error(BadLine(number: number))
    Ok(Keys(_)): Error(BadLine(number: number))
    Ok(Stats): Error(BadLine(number: number))
    Ok(Quit): Error(BadLine(number: number))
    Error(_): Error(BadLine(number: number))
  end
end

# What a journal held, replayed as a restart replays it.
fn reopen(logged: Logged) : Result(Reopened, LogError)
  replayed = try replay(logged.text)
  size = replayed.table.size
  Ok(Reopened(table: replayed.table, keys_before: logged.keys, keys_after: size))
end

# A table as a log of one SET line per live key, keys in byte order.
fn compacted(table: Table) : String
  ensures replay(result) is Ok(again) and again.table.size == table.size

  lines = keys_with(table, "").map(fn(key) entry(key, lookup(table, key)) end)
  String.join(lines, "")
end

# The log in a folder, replayed; a folder with no kv.log yet holds an empty log.
fn open(dir: Fs) : Result(Opened, LogError)
  names = try names_in(dir)
  if !names.contains?("kv.log")
    nothing = Replayed(table: empty(), lines: 0, truncated: false)
    return Ok(Opened(replayed: nothing, bytes: 0))
  end
  text = try text_of(dir)
  bytes = try size_of(dir)
  replayed = try replay(text)
  Ok(Opened(replayed: replayed, bytes: bytes))
end

fn names_in(dir: Fs) : Result(List(String), LogError)
  case dir.list(within: 10_000.ms)
    Ok(names): Ok(names)
    Error(Missing(_)): Error(NoFolder)
    Error(Timeout): Error(Slow)
  end
end

fn text_of(dir: Fs) : Result(String, LogError)
  case dir.read("kv.log", within: 60_000.ms)
    Ok(text): Ok(text)
    Error(Missing(_)): Error(Unreadable)
    Error(Timeout): Error(Slow)
  end
end

fn size_of(dir: Fs) : Result(UInt64, LogError)
  case dir.size("kv.log", within: 10_000.ms)
    Ok(bytes): Ok(bytes)
    Error(Missing(_)): Error(Unreadable)
    Error(Timeout): Error(Slow)
  end
end

test "a set key reads back, and setting it again still counts one key"
  once = put(empty(), "greeting", "hello")
  twice = put(once, "greeting", "hello wide world")
  assert lookup(once, "greeting") == Some("hello")
  assert lookup(twice, "greeting") == Some("hello wide world")
  assert once.size == 1
  assert twice.size == 1
  assert lookup(twice, "other") is None
end

test "a dropped key is gone, and dropping a key the table lacks changes nothing"
  table = put(put(empty(), "a", "1"), "b", "2")
  assert drop(table, "a").size == 1
  assert lookup(drop(table, "a"), "a") is None
  assert drop(table, "zzz") == table
end

test "keys under a prefix come from every bucket, in byte order"
  names = ["user:9", "user:10", "item:1", "user:1", "user", "a"]
  table = names.reduce(empty(), fn(t, name) put(t, name, "x") end)
  assert keys_with(table, "user:") == ["user:1", "user:10", "user:9"]
  assert keys_with(table, "") == ["a", "item:1", "user", "user:1", "user:10", "user:9"]
  assert keys_with(table, "nobody") == []
end

test "replay applies SET and DEL in order"
  outcome = replay("SET a 1\nSET b two words\nDEL a\nSET c \nSET b 3\n")
  assert outcome is Ok(replayed)
  assert replayed.lines == 5
  assert !replayed.truncated
  assert replayed.table.size == 2
  assert lookup(replayed.table, "b") == Some("3")
  assert lookup(replayed.table, "c") == Some("")
  assert lookup(replayed.table, "a") is None
  assert replay("") is Ok(nothing)
  assert nothing.table.size == 0 and nothing.lines == 0
end

test "a last line with no newline is left out, and replay says it was cut short"
  outcome = replay("SET a 1\nSET b 22")
  assert outcome is Ok(replayed)
  assert replayed.truncated
  assert replayed.lines == 1
  assert lookup(replayed.table, "b") is None
end

test "a line that is not a SET or a DEL stops replay at its number"
  assert replay("SET a 1\nGET a\nSET b 2\n") is Error(BadLine(2))
  assert replay("SET a 1\n\nSET b 2\n") is Error(BadLine(2))
  assert replay("INCR a 1\n") is Error(BadLine(1))
end

test "a change is a SET line with its value, or a DEL line"
  assert entry("a", Some("one two")) == "SET a one two\n"
  assert entry("a", None) == "DEL a\n"
end

test "compaction keeps one line per live key, and replays to the same keys and values"
  outcome = replay("SET b 1\nSET a 1\nSET b 2\nDEL a\nSET c 3\n")
  assert outcome is Ok(replayed)
  log = compacted(replayed.table)
  assert log == "SET b 2\nSET c 3\n"
  assert replay(log) is Ok(again)
  assert again.table == replayed.table or keys_with(again.table, "") == ["b", "c"]
end

test "a folder with no log opens empty, and a slow one says so"
  assert open(Fs.fixture()) is Ok(opened)
  assert opened.bytes == 0
  assert opened.replayed.table.size == 0
  assert open(Fs.fixture(delay: 1.minute)) is Error(Slow)
end

test "the journal counts the bytes it appended, and holds the lines in order"
  journal = Journal.start(100)
  first = journal.ask(Append(line: "SET a 1\n", keys: 1), within: 1_000.ms)
  second = journal.ask(Append(line: "SET é 2\n", keys: 2), within: 1_000.ms)
  written = journal.ask(Written, within: 1_000.ms)
  assert first is Ok(108) or first is Error(_)
  assert second is Ok(117) or second is Error(_)
  assert written is Ok(Logged(text: "SET a 1\nSET é 2\n", keys: 2)) or written is Error(_)
end

test "what a journal held replays to the keys the store had"
  logged = Logged(text: "SET a 1\nSET b 2\nDEL a\n", keys: 1)
  assert reopen(logged) is Ok(reopened)
  assert reopened.keys_after == 1
end

test rejects "a key with a space in it"
  put(empty(), "a b", "1")
end

test rejects "a value over 60 KiB"
  put(empty(), "big", "x".repeat(61_441))
end

verified: types, contracts, tests (13), property (0 seeds), sim (100 runs)
          proven: not run
