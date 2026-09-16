# recipe: Recipes.Store.Store
module Ledger.Store
expose StoreError, Read, Reopened, Table, Replay, key?, value?, open, get, count, log, cut_short?, put, delete, keys, compact, lines, placed, resized, set_line, batch_text, begun

intent "The store recipe (examples/recipes/store.mo) implemented for the ledger over Fs, copied by hand from jobq's Jobq.Store: String keys to String values over 256 small maps, a log named ledger.log in a folder with a SET or DEL line per change, each on disk before put or delete returns, replay that leaves out a last line cut short, and compaction to one line per live key written beside the log and renamed over it; beyond the recipe, a batch written as a BEGIN line and its changes replays whole or not at all."

never "a value read is not the last one written"
  for r in Read.all
    r.value != r.written
  end
end

never "a replay changes the number of live keys"
  for r in Reopened.all
    r.after != r.before
  end
end

# Every way opening or changing a store fails. Unwritten: the change is not in the log, and the
# table is as it was. Torn: the log may end in part of the change, so it is rewritten whole
# (compact) at the next change, and changes are taken from then on.
enum StoreError
  NoFolder
  Unreadable
  Slow
  BadLine(number: UInt64)
  Unwritten
  Torn
end

# A read of a key, beside the value the last change to that key wrote.
struct Read
  key: String
  value: Option(String)
  written: Option(String)
end

# A store opened again from its log, beside the live keys it held before it stopped.
struct Reopened
  before: UInt64
  after: UInt64
end

# The keys and values over 256 small maps; the log, `name` in the folder `dir`, and its size in
# bytes; the lines open replayed, and whether it left out a last line or a last batch cut short.
struct Table
  buckets: Map(UInt64, Map(String, String))
  size: UInt64
  dir: String
  name: String
  bytes: UInt64
  lines: UInt64
  cut: Bool
end

# A log being replayed: the table so far, the line read but not applied until the next, lines
# applied, bytes read, the first bad line, and the lines of a batch still open with how many
# more it said it holds.
struct Replay
  table: Table
  pending: Option(String)
  lines: UInt64
  bytes: UInt64
  bad: UInt64
  batch: List(String)
  expected: UInt64
end

# A key is 1 to 512 bytes with no space and no control character.
fn key?(text: String) : Bool
  return false if text == "" or text.byte_size > 512
  text.bytes.all?(fn(b) b > 32 and b != 127 end)
end

# A value is at most 1 MiB and holds no line break.
fn value?(text: String) : Bool
  text.byte_size <= 1_048_576 and !text.contains?("\n") and !text.contains?("\r")
end

# The store whose log is ledger.log in the folder dir, replayed; a folder with no log yet holds
# an empty store.
fn open(fs: Fs, dir: String) : Result(Table, StoreError)
  folder = fs.scoped(dir)
  names = try names_in(folder)
  empty = Table(buckets: Map.new(), size: 0, dir: dir, name: "ledger.log", bytes: 0, lines: 0,
    cut: false)
  return Ok(empty) if !names.contains?("ledger.log")
  bytes = try size_of(folder, "ledger.log")
  replayed = try replayed_from(folder, begun(empty), "ledger.log")
  return Error(BadLine(number: replayed.bad)) if replayed.bad > 0
  finished(replayed, bytes)
end

fn begun(table: Table) : Replay
  Replay(table: table, pending: None, lines: 0, bytes: 0, bad: 0, batch: [], expected: 0)
end

fn get(table: Table, key: String) : Option(String)
  case table.buckets.get(bucket_of(key))
    Some(bucket): bucket.get(key)
    None: None
  end
end

fn count(table: Table) : UInt64
  table.size
end

fn log(table: Table) : String
  "#{table.dir}/#{table.name}"
end

fn cut_short?(table: Table) : Bool
  table.cut
end

fn lines(table: Table) : UInt64
  table.lines
end

fn put(fs: Fs, table: Table, key: String, value: String) : Result(Table, StoreError)
  requires key?(key)
  requires value?(value)
  ensures result is Ok(after) implies get(after, key) == Some(value)

  bytes = try appended(fs, table, set_line(key, value))
  Ok(resized(placed(table, key, value), bytes))
end

fn delete(fs: Fs, table: Table, key: String) : Result(Table, StoreError)
  ensures result is Ok(after) implies get(after, key) is None

  return Ok(table) if get(table, key) is None
  bytes = try appended(fs, table, "DEL #{key}\n")
  Ok(resized(dropped(table, key), bytes))
end

fn keys(table: Table, prefix: String) : List(String)
  ensures result.all?(fn(key) key.starts_with?(prefix) end)

  all = table.buckets.values.flat_map(fn(bucket) bucket.keys end)
  all.filter(fn(key) key.starts_with?(prefix) end).sort
end

# The log rewritten as one SET line per live key, keys in byte order, beside the log and renamed
# over it, so a compaction cut short leaves the old log as it was.
fn compact(fs: Fs, table: Table) : Result(Table, StoreError)
  ensures result is Ok(after) implies count(after) == count(table) and !cut_short?(after)

  folder = fs.scoped(table.dir)
  text = String.join(keys(table, "").map(fn(key) set_line(key, get(table, key) or "") end), "")
  beside = "#{table.name}.new"
  return Error(Unwritten) if folder.write(beside, text, within: 20_000.ms) is Error(_)
  return Error(Unwritten) if folder.rename(beside, table.name, within: 5_000.ms) is Error(_)
  var after = table
  after.bytes = text.byte_size
  after.lines = table.size
  after.cut = false
  Ok(after)
end

fn set_line(key: String, value: String) : String
  "SET #{key} #{value}\n"
end

# Pairs as one batch: a BEGIN line with their count, then a SET line for each, so a replay
# applies all of them or, when the log ends before the last, none.
fn batch_text(pairs: List((String, String))) : String
  return "" if pairs.size == 0
  "BEGIN #{pairs.size}\n#{String.join(pairs.map(fn(p) set_line(p.0, p.1) end), "")}"
end

fn appended(fs: Fs, table: Table, line: String) : Result(UInt64, StoreError)
  folder = fs.scoped(table.dir)
  after = table.bytes + line.byte_size
  return Ok(after) if folder.append(table.name, line, within: 5_000.ms) is Ok(_)
  case folder.size(table.name, within: 5_000.ms)
    Ok(size):
      return Ok(after) if size == after
      return Error(Unwritten) if size == table.bytes
      Error(Torn)
    Error(Missing(_)):
      return Error(Unwritten) if table.bytes == 0
      Error(Torn)
    Error(Timeout) | Error(NotText): Error(Torn)
  end
end

fn resized(table: Table, bytes: UInt64) : Table
  var after = table
  after.bytes = bytes
  after
end

fn bucket_of(key: String) : UInt64
  ensures result < 256

  key.bytes.reduce(0, fn(hash, b) (hash * 31 + b.to_u64) % 256 end)
end

fn placed(table: Table, key: String, value: String) : Table
  at = bucket_of(key)
  bucket = table.buckets.get(at) or Map.new()
  added = if bucket.has?(key): 0 else: 1
  var after = table
  after.buckets = table.buckets.set(at, bucket.set(key, value))
  after.size = table.size + added
  after
end

fn dropped(table: Table, key: String) : Table
  at = bucket_of(key)
  bucket = table.buckets.get(at) or Map.new()
  return table if !bucket.has?(key)
  var after = table
  after.buckets = table.buckets.set(at, bucket.remove(key))
  after.size = table.size - 1
  after
end

# One whole line applied: a SET with its key and the rest of the line as the value, or a DEL.
fn applied(table: Table, line: String) : Option(Table)
  if line.starts_with?("DEL ")
    gone = line.slice(4, line.size)
    return None if !key?(gone)
    return Some(dropped(table, gone))
  end
  return None if !line.starts_with?("SET ")
  rest = line.slice(4, line.size)
  at = rest.index_of(" ") or 0
  key = rest.slice(0, at)
  return None if !key?(key)
  Some(placed(table, key, rest.slice(at + 1, rest.size)))
end

# The next line read: the one before it is whole, since another came after it, so it is taken.
fn stepped(replay: Replay, line: String) : Replay
  var next = case replay.pending
    Some(previous): taken(replay, previous)
    None: replay
  end
  next.bytes = replay.bytes + line.byte_size + 1
  next.pending = Some(line)
  next
end

# A whole line taken: a BEGIN opens a batch, a line inside a batch waits for the rest of it, and
# any other line applies at once; a batch applies once its last line is taken.
fn taken(replay: Replay, line: String) : Replay
  return replay if replay.bad > 0
  var next = replay
  next.lines = replay.lines + 1
  if replay.expected > 0
    next.batch = replay.batch.push(line)
    return next if next.batch.size < replay.expected
    var done = applied_all(next, next.batch)
    done.batch = []
    done.expected = 0
    return done
  end
  if line.starts_with?("BEGIN ")
    held = line.slice(6, line.size).to_u64 or 0
    next.bad = if held == 0: replay.lines + 1 else: replay.bad
    next.expected = held
    next.batch = []
    return next
  end
  case applied(replay.table, line)
    Some(table):
      next.table = table
      next
    None:
      next.bad = replay.lines + 1
      next
  end
end

fn applied_all(replay: Replay, lines: List(String)) : Replay
  lines.reduce(replay, fn(so_far, line)
    case applied(so_far.table, line)
      Some(table):
        var next = so_far
        next.table = table
        next
      None:
        var wrong = so_far
        wrong.bad = if so_far.bad > 0: so_far.bad else: so_far.lines
        wrong
    end
  end)
end

# The replay once the file is read: its last line taken when the file ends with its newline, and
# a last line or a last batch cut short left out.
fn finished(replay: Replay, bytes: UInt64) : Result(Table, StoreError)
  whole = replay.bytes <= bytes
  var done = replay
  if replay.pending is Some(last) and whole
    done = taken(replay, last)
  end
  return Error(BadLine(number: done.bad)) if done.bad > 0
  var table = done.table
  table.bytes = bytes
  table.lines = done.lines
  table.cut = done.expected > 0 or !whole
  Ok(table)
end

fn replayed_from(folder: Fs, start: Replay, name: String) : Result(Replay, StoreError)
  case folder.fold_lines(name, start, within: 600_000.ms,
    fn(replay, line) stepped(replay, line) end)
    Ok(replay): Ok(replay)
    Error(Missing(_)): Error(Unreadable)
    Error(Timeout): Error(Slow)
    Error(NotText): Error(Unreadable)
  end
end

fn names_in(folder: Fs) : Result(List(String), StoreError)
  case folder.list(within: 10_000.ms)
    Ok(names): Ok(names)
    Error(Missing(_)): Error(NoFolder)
    Error(Timeout): Error(Slow)
    Error(NotText): Error(NoFolder)
  end
end

fn size_of(folder: Fs, name: String) : Result(UInt64, StoreError)
  case folder.size(name, within: 10_000.ms)
    Ok(bytes): Ok(bytes)
    Error(Missing(_)): Error(Unreadable)
    Error(Timeout): Error(Slow)
    Error(NotText): Error(Unreadable)
  end
end

test rejects "a key with a space in it"
  fs = Fs.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(empty)
  assert put(fs, empty, "a b", "1") is Error(_)
end

test rejects "a value with a newline in it"
  fs = Fs.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(empty)
  assert put(fs, empty, "a", "one\ntwo") is Error(_)
end

test "replay applies SET and DEL in order, and stops open at a line that is neither"
  fs = Fs.fixture()
  assert fs.write("d/ledger.log", "SET a 1\nSET b two words\nDEL a\nSET c \nSET b 3\n",
    within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(table)
  assert lines(table) == 5 and count(table) == 2 and get(table, "c") == Some("")
  assert fs.write("d/ledger.log", "SET a 1\nGET a\nSET b 2\n", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Error(BadLine(_))
end

test "a batch replays whole, and a batch the log ends inside of is left out as cut short"
  fs = Fs.fixture()
  text = "SET a 1\n#{batch_text([("b", "2"), ("c", "3")])}SET d 4\n"
  assert text == "SET a 1\nBEGIN 2\nSET b 2\nSET c 3\nSET d 4\n"
  assert fs.write("d/ledger.log", text, within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(whole)
  assert count(whole) == 4 and !cut_short?(whole) and lines(whole) == 5
  assert fs.write("d/ledger.log", "SET a 1\nBEGIN 3\nSET b 2\nSET c 3\n", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(cut)
  assert cut_short?(cut) and count(cut) == 1 and get(cut, "b") is None
  assert fs.write("d/ledger.log", "SET a 1\nBEGIN 1\nSET b 2", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(torn)
  assert cut_short?(torn) and count(torn) == 1
end

test "a store opened again from its log holds as many keys as before it stopped"
  fs = Fs.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(empty)
  assert put(fs, empty, "a", "1") is Ok(one)
  assert put(fs, one, "b", "2") is Ok(two)
  assert delete(fs, two, "a") is Ok(before)
  assert open(fs, "d") is Ok(after)
  record = Reopened(before: count(before), after: count(after))
  assert record.after == record.before
end

verified: types, contracts, tests (5), property (0 seeds), sim (not run)
          proven: not run
