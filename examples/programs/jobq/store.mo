# recipe: Recipes.Store.Store
module Jobq.Store
expose StoreError, Read, Reopened, Table, key?, value?, open, reopened, get, count, log, cut_short?, put, delete, keys, compact, put_all, writing_to, lines, bytes, blank, pairs, journaled, rewritten, emptied, line_of

intent "The store recipe (examples/recipes/store.mo) implemented for jobq over Fs, copied by hand from notes's Notes.Store, its keys spread over 256 small maps so a change copies one small map: String keys to String values, a log named jobq.log in a folder with a SET or DEL line per change, each change appended and on disk before it returns, and put_all appending many changes in one write, so one fsync covers them; replay leaves out a last line cut short, and compaction writes one line per live key beside the log and renames it over the log."

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

# The keys and values, over 256 small maps so a change copies one small map (changing an entry
# a map already has copies the whole map, TOOLCHAIN-BUGS.md, bug 1), and how many; the log they
# are written to, `name` in the folder `dir`, and its size in bytes; the lines open replayed or
# compact wrote, and whether open left out a last line cut short.
struct Table
  buckets: Map(UInt64, Map(String, String))
  size: UInt64
  dir: String
  name: String
  bytes: UInt64
  lines: UInt64
  cut: Bool
end

# A log being replayed: the table so far, the line read but not yet applied (the last line is
# applied only when the file ends with its newline), the lines applied, the bytes read, and the
# number of the first line that is not a SET or a DEL, or 0.
struct Replay
  table: Table
  pending: Option(String)
  lines: UInt64
  bytes: UInt64
  bad: UInt64
end

# A key is 1 to 256 bytes with no space and no control character.
fn key?(text: String) : Bool
  return false if text == "" or text.byte_size > 256
  text.bytes.all?(fn(b) b > 32 and b != 127 end)
end

# A value is at most 1 MiB and holds no line break.
fn value?(text: String) : Bool
  text.byte_size <= 1_048_576 and !text.contains?("\n") and !text.contains?("\r")
end

# The store whose log is jobq.log in the folder dir, replayed; a folder with no log yet holds an
# empty store.
fn open(fs: Fs, dir: String) : Result(Table, StoreError)
  folder = fs.scoped(dir)
  names = try names_in(folder)
  empty = blank(dir)
  return Ok(empty) if !names.contains?("jobq.log")
  size = try size_of(folder, "jobq.log")
  start = Replay(table: empty, pending: None, lines: 0, bytes: 0, bad: 0)
  replayed = try replayed_from(folder, start)
  return Error(BadLine(number: replayed.bad)) if replayed.bad > 0
  finished(replayed, size)
end

# The store a table names, opened again from its folder after a restart: jobq.log, then, for a
# table writing to another log as jobq check's does, that log replayed over it.
fn reopened(fs: Fs, table: Table) : Result(Table, StoreError)
  base = try open(fs, table.dir)
  return Ok(base) if table.name == base.name
  folder = fs.scoped(table.dir)
  names = try names_in(folder)
  over = writing_to(base, table.name)
  return Ok(over) if !names.contains?(table.name)
  size = try size_of(folder, table.name)
  start = Replay(table: over, pending: None, lines: 0, bytes: 0, bad: 0)
  replayed = try replayed_log(folder, table.name, start)
  return Error(BadLine(number: replayed.bad)) if replayed.bad > 0
  finished(replayed, size)
end

# An empty store over the log jobq.log in the folder dir.
fn blank(dir: String) : Table
  Table(buckets: Map.new(), size: 0, dir: dir, name: "jobq.log", bytes: 0, lines: 0, cut: false)
end

fn get(table: Table, key: String) : Option(String)
  bucket = try table.buckets.get(bucket_of(key))
  bucket.get(key)
end

fn count(table: Table) : UInt64
  table.size
end

# Every key and its value.
fn pairs(table: Table) : List((String, String))
  table.buckets.values.flat_map(fn(bucket) bucket.entries end)
end

# Which of the 256 maps holds a key.
fn bucket_of(key: String) : UInt64
  ensures result < 256

  key.bytes.reduce(0, fn(hash, b) (hash * 31 + b.to_u64) % 256 end)
end

# The log's path, from the Fs the store was opened on.
fn log(table: Table) : String
  "#{table.dir}/#{table.name}"
end

fn cut_short?(table: Table) : Bool
  table.cut
end

# The lines open replayed, or compact wrote.
fn lines(table: Table) : UInt64
  table.lines
end

# The log's size in bytes, as the store last knew it.
fn bytes(table: Table) : UInt64
  table.bytes
end

# The store with the key set to the value, once its SET line is on disk.
fn put(fs: Fs, table: Table, key: String, value: String) : Result(Table, StoreError)
  requires key?(key)
  requires value?(value)
  ensures result is Ok(after) implies get(after, key) == Some(value)

  put_all(fs, table, [(key, Some(value))])
end

# The store without the key, once its DEL line is on disk; a key it does not hold writes
# nothing.
fn delete(fs: Fs, table: Table, key: String) : Result(Table, StoreError)
  ensures result is Ok(after) implies get(after, key) is None

  return Ok(table) if get(table, key) is None
  put_all(fs, table, [(key, None)])
end

# Many changes, a value to set or None to delete, appended in order in one write and applied
# once that write is on disk; a change to a key the table does not hold that deletes it writes
# nothing.
fn put_all(fs: Fs, table: Table, changes: List((String, Option(String)))) : Result(Table,
  StoreError)
  requires changes.all?(fn(c) key?(c.0) and value?(c.1 or "") end)
  ensures result is Ok(after) implies changes.all?(fn(c)
    get(after, c.0) == last_of(changes, c.0)
  end)

  kept = kept_lines(table, changes)
  return Ok(table) if kept.size == 0
  size = try appended(fs, table, String.join(kept, ""))
  lines_before = table.lines
  var after = changes.reduce(table, fn(so_far, c) changed(so_far, c) end)
  after.bytes = size
  after.lines = lines_before + kept.size
  Ok(after)
end

# The lines a batch appends: a delete of a key not held at that point of the batch, in the table
# or set earlier in the batch, writes nothing. The table is only read here, and the batch's own
# keys are kept apart from it, so no step copies the table.
fn kept_lines(table: Table, changes: List((String, Option(String)))) : List(String)
  changes.reduce((Map.new(), [""].take(0)), fn(acc, c) kept_with(table, acc, c) end).1
end

fn kept_with(table: Table, acc: (Map(String, Bool), List(String)),
  change: (String, Option(String))) : (Map(String, Bool), List(String))
  held = acc.0.get(change.0) or get(table, change.0) is Some(_)
  return acc if change.1 is None and !held
  (acc.0.set(change.0, change.1 is Some(_)), acc.1.push(line_of(change)))
end

fn last_of(changes: List((String, Option(String))), key: String) : Option(String)
  case changes.filter(fn(c) c.0 == key end).last
    Some(change): change.1
    None: None
  end
end

fn line_of(change: (String, Option(String))) : String
  case change.1
    Some(value): "SET #{change.0} #{value}\n"
    None: "DEL #{change.0}\n"
  end
end

fn changed(table: Table, change: (String, Option(String))) : Table
  case change.1
    Some(value): placed(table, change.0, value)
    None: dropped(table, change.0)
  end
end

# Changes appended as lines in one write, the table keeping no values: for a caller that holds
# the values itself and needs only the log's name and size.
fn journaled(fs: Fs, table: Table, lines: List(String)) : Result(Table, StoreError)
  requires lines.all?(fn(line) line.ends_with?("\n") end)

  return Ok(table) if lines.size == 0
  size = try appended(fs, table, String.join(lines, ""))
  var after = table
  after.bytes = size
  after.lines = table.lines + lines.size
  Ok(after)
end

# The log written whole from the lines given, beside the log and renamed over it, so a rewrite
# cut short leaves the old log as it was.
fn rewritten(fs: Fs, table: Table, lines: List(String)) : Result(Table, StoreError)
  requires lines.all?(fn(line) line.ends_with?("\n") end)

  folder = fs.scoped(table.dir)
  text = String.join(lines, "")
  fresh = "#{table.name}.new"
  if folder.write(fresh, text, within: 60_000.ms) is Error(_)
    return Error(Unwritten)
  end
  if folder.rename(fresh, table.name, within: 10_000.ms) is Error(_)
    return Error(Unwritten)
  end
  var after = table
  after.bytes = text.byte_size
  after.lines = lines.size
  after.cut = false
  Ok(after)
end

# The table without its values, still naming its log and its size.
fn emptied(table: Table) : Table
  var after = table
  after.buckets = Map.new()
  after.size = 0
  after
end

# Every key that starts with the prefix, in byte order.
fn keys(table: Table, prefix: String) : List(String)
  ensures result.all?(fn(key) key.starts_with?(prefix) end)

  pairs(table).map(fn(p) p.0 end).filter(fn(key) key.starts_with?(prefix) end).sort
end

# The log rewritten as one SET line per live key, keys in byte order: written whole beside the
# log, then renamed over it, so a compaction cut short leaves the old log as it was.
fn compact(fs: Fs, table: Table) : Result(Table, StoreError)
  ensures result is Ok(after) implies count(after) == count(table) and !cut_short?(after)

  folder = fs.scoped(table.dir)
  text = String.join(keys(table, "").map(fn(key) set_line(table, key) end), "")
  fresh = "#{table.name}.new"
  if folder.write(fresh, text, within: 60_000.ms) is Error(_)
    return Error(Unwritten)
  end
  if folder.rename(fresh, table.name, within: 10_000.ms) is Error(_)
    return Error(Unwritten)
  end
  var after = table
  after.bytes = text.byte_size
  after.lines = count(table)
  after.cut = false
  Ok(after)
end

# The same keys and values, their changes appended from now on to the empty log `name` in the
# same folder: jobq check serves a folder's log without writing to it.
fn writing_to(table: Table, name: String) : Table
  var moved = table
  moved.name = name
  moved.bytes = 0
  moved
end

fn set_line(table: Table, key: String) : String
  "SET #{key} #{get(table, key) or ""}\n"
end

# Appends the text and gives the log's size after it. An append that fails is looked at again:
# a log that holds the whole text took it, one as long as before did not, and anything else,
# or a size that cannot be read, may end in part of it.
fn appended(fs: Fs, table: Table, text: String) : Result(UInt64, StoreError)
  folder = fs.scoped(table.dir)
  after = table.bytes + text.byte_size
  return Ok(after) if folder.append(table.name, text, within: 5_000.ms) is Ok(_)
  case folder.size(table.name, within: 5_000.ms)
    Ok(size):
      return Ok(after) if size == after
      return Error(Unwritten) if size == table.bytes
      Error(Torn)
    Error(Missing(_)):
      return Error(Unwritten) if table.bytes == 0
      Error(Torn)
    Error(Timeout): Error(Torn)
    Error(NotText): Error(Torn)
  end
end

fn placed(table: Table, key: String, value: String) : Table
  at = bucket_of(key)
  bucket = table.buckets.get(at) or Map.new()
  added = if bucket.has?(key): 0 else: 1
  var after = table
  after.buckets = after.buckets.set(at, bucket.set(key, value))
  after.size = table.size + added
  after
end

fn dropped(table: Table, key: String) : Table
  at = bucket_of(key)
  bucket = table.buckets.get(at) or Map.new()
  return table if !bucket.has?(key)
  var after = table
  after.buckets = after.buckets.set(at, bucket.remove(key))
  after.size = table.size - 1
  after
end

# One whole line of the log applied to the table: a SET with its key and the rest of the line
# as the value, or a DEL with its key; None for anything else.
fn applied(table: Table, line: String) : Option(Table)
  if line.starts_with?("DEL ")
    key = line.slice(4, line.size)
    return None if !key?(key)
    return Some(dropped(table, key))
  end
  return None if !line.starts_with?("SET ")
  rest = line.slice(4, line.size)
  at = rest.index_of(" ") or rest.size
  key = rest.slice(0, at)
  return None if !key?(key) or at == rest.size
  Some(placed(table, key, rest.slice(at + 1, rest.size)))
end

# The next line read: the one before it is whole, since another came after it, so it is
# applied. Replay stops applying at the first line that is not the store's.
fn stepped(replay: Replay, line: String) : Replay
  var next = replay
  next.bytes = replay.bytes + line.byte_size + 1
  next.pending = Some(line)
  return next if replay.bad > 0
  case replay.pending
    Some(previous):
      case applied(replay.table, previous)
        Some(table):
          next.table = table
          next.lines = replay.lines + 1
        None:
          next.bad = replay.lines + 1
      end
    None:
      next.bad = replay.bad
  end
  next
end

# The replay once the file is read: its last line applied when the file ends with its newline,
# and left out, cut short, when it does not.
fn finished(replay: Replay, size: UInt64) : Result(Table, StoreError)
  var table = replay.table
  table.bytes = size
  table.lines = replay.lines
  whole = replay.bytes <= size
  if replay.pending is Some(last)
    if !whole
      table.cut = true
      return Ok(table)
    end
    case applied(table, last)
      Some(done):
        table = done
        table.lines = replay.lines + 1
      None:
        return Error(BadLine(number: replay.lines + 1))
    end
  end
  Ok(table)
end

fn replayed_from(folder: Fs, start: Replay) : Result(Replay, StoreError)
  replayed_log(folder, "jobq.log", start)
end

fn replayed_log(folder: Fs, name: String, start: Replay) : Result(Replay, StoreError)
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
    Ok(size): Ok(size)
    Error(Missing(_)): Error(Unreadable)
    Error(Timeout): Error(Slow)
    Error(NotText): Error(Unreadable)
  end
end

# The recipe's tests rejects, here as well since every requires has one in its own module;
# mo check --recipe holds them to the recipe's, line for line.
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

test rejects "many changes, one of them to a key with a space in it"
  fs = Fs.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(empty)
  assert put_all(fs, empty, [("a", Some("1")), ("b c", Some("2"))]) is Error(_)
end

test "many changes are one append, applied in order, and read back once the store opens again"
  fs = Fs.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(empty)
  changes = [("j_1", Some("one")), ("j_2", Some("two")), ("j_1", None), ("j_3", None)]
  assert put_all(fs, empty, changes) is Ok(after)
  assert get(after, "j_1") is None and get(after, "j_2") == Some("two") and count(after) == 1
  assert fs.read("d/jobq.log", within: 1.minute) == Ok("SET j_1 one\nSET j_2 two\nDEL j_1\n")
  assert lines(after) == 3 and bytes(after) == 32
  assert put_all(fs, after, []) == Ok(after)
  assert open(fs, "d") is Ok(again)
  assert pairs(again) == pairs(after) and lines(again) == 3
end

test "lines journaled are one append, and a log rewritten whole replaces what it held"
  fs = Fs.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(empty)
  assert journaled(fs, emptied(empty), ["SET a 1\n", "SET b 2\n", "DEL a\n"]) is Ok(noted)
  assert count(noted) == 0 and lines(noted) == 3 and bytes(noted) == 22
  assert open(fs, "d") is Ok(replayed)
  assert get(replayed, "b") == Some("2") and count(replayed) == 1
  assert rewritten(fs, noted, ["SET c 3\n"]) is Ok(whole)
  assert bytes(whole) == 8 and lines(whole) == 1
  assert fs.read("d/jobq.log", within: 1.minute) == Ok("SET c 3\n")
  assert journaled(fs, whole, []) == Ok(whole)
end

test rejects "a journaled line with no newline"
  journaled(Fs.fixture(), blank("d"), ["SET a 1"])
end

test rejects "a rewrite with a line with no newline"
  rewritten(Fs.fixture(), blank("d"), ["SET a 1"])
end

test "replay applies SET and DEL in order, and stops open at a line that is neither"
  fs = Fs.fixture()
  log_text = "SET a 1\nSET b two words\nDEL a\nSET c \nSET b 3\n"
  assert fs.write("d/jobq.log", log_text, within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(table)
  assert lines(table) == 5
  assert count(table) == 2
  assert get(table, "b") == Some("3")
  assert get(table, "c") == Some("")
  assert !cut_short?(table)
  assert fs.write("d/jobq.log", "SET a 1\nGET a\nSET b 2\n", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Error(BadLine(2))
  assert fs.write("d/jobq.log", "SET a 1\nSET b", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(cut)
  assert cut_short?(cut) and count(cut) == 1
  assert fs.write("d/jobq.log", "SET a 1\nSET nospace\n", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Error(BadLine(2))
end

test "a store opened again from its log holds as many keys as before it stopped"
  fs = Fs.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(empty)
  assert put(fs, empty, "a", "1") is Ok(one)
  assert put(fs, one, "b", "2") is Ok(two)
  assert delete(fs, two, "a") is Ok(before)
  assert delete(fs, before, "zzz") is Ok(same)
  assert same == before
  assert open(fs, "d") is Ok(after)
  record = Reopened(before: count(before), after: count(after))
  assert record.after == record.before
end

test "a change the log cannot take leaves the table as it was"
  fs = Fs.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(empty)
  assert put(fs, empty, "a", "1") is Ok(one)
  assert put(Fs.fixture(delay: 1.minute), one, "b", "2") is Error(Torn)
  assert get(one, "b") is None
  assert put_all(Fs.fixture(delay: 1.minute), one, [("b", Some("2"))]) is Error(Torn)
end

test "a store writing to another log keeps its keys and leaves the first log alone"
  fs = Fs.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(empty)
  assert put(fs, empty, "a", "1") is Ok(one)
  moved = writing_to(one, "jobq.check.log")
  assert put(fs, moved, "b", "2") is Ok(two)
  assert get(two, "a") == Some("1")
  assert fs.read("d/jobq.check.log", within: 1.minute) == Ok("SET b 2\n")
  assert fs.read("d/jobq.log", within: 1.minute) == Ok("SET a 1\n")
end

test "a store opened again after a restart holds both logs when it writes to another"
  fs = Fs.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(empty)
  assert put(fs, empty, "a", "1") is Ok(one)
  assert reopened(fs, emptied(one)) is Ok(same)
  assert get(same, "a") == Some("1") and same.name == "jobq.log" and bytes(same) == 8
  moved = emptied(writing_to(one, "jobq.check.log"))
  assert reopened(fs, moved) is Ok(untouched)
  assert get(untouched, "a") == Some("1") and untouched.name == "jobq.check.log"
  assert bytes(untouched) == 0
  assert put(fs, writing_to(one, "jobq.check.log"), "b", "2") is Ok(two)
  assert delete(fs, two, "a") is Ok(_)
  assert reopened(fs, moved) is Ok(both)
  assert get(both, "a") is None and get(both, "b") == Some("2") and count(both) == 1
  assert bytes(both) == 14 and lines(both) == 2
  assert fs.write("d/jobq.check.log", "SET b 2\nSET c", within: 1.minute) is Ok(_)
  assert reopened(fs, moved) is Ok(cut)
  assert cut_short?(cut) and get(cut, "c") is None and get(cut, "a") == Some("1")
end

property "any valid key and value read back as written, and again once the store is opened again"
  for key in any(String), value in any(String) if key?(key) and value?(value)
    fs = Fs.fixture()
    assert fs.mkdir("d", within: 1.minute) is Ok(_)
    assert open(fs, "d") is Ok(empty)
    assert put(fs, empty, key, value) is Ok(one)
    read = Read(key: key, value: get(one, key), written: Some(value))
    assert read.value == read.written
    assert open(fs, "d") is Ok(again)
    assert get(again, key) == Some(value)
  end
end

verified: types, contracts, tests (13), property (200 seeds), sim (not run)
          proven: not run
