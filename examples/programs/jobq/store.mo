# recipe: Recipes.Store.Store
module Jobq.Store
expose StoreError, Read, Reopened, Table, Replay, key?, value?, open, get, count, log, cut_short?, put, delete, keys, compact, writing_to, lines, whole_text, rewritten, placed, dropped, resized, stepped, finished

intent "The store recipe (examples/recipes/store.mo) implemented for jobq over Fs, its own deadlines on each call (Jobq.Journal makes the same calls on a caller's), copied by hand from notes's Notes.Store, which took it from kv's Kv.Log: String keys to String values spread over 256 small maps, a log named jobq.log in a folder with a SET or DEL line per change, each appended and on disk before put or delete returns, replay that leaves out a last line cut short, and compaction to one line per live key written beside the log and renamed over it."

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

# The keys and values, over 256 small maps so a change copies one small map; the log they are
# written to, `name` in the folder `dir`, and its size in bytes; the lines open replayed, and
# whether it left out a last line cut short.
struct Table
  buckets: Map(UInt64, Map(String, String))
  size: UInt64
  dir: String
  name: String
  bytes: UInt64
  lines: UInt64
  cut: Bool
end

# A log being replayed: the table so far, the line read but not applied until the next (a last
# line only when the file ends with its newline), lines applied, bytes read, and the first bad line.
struct Replay
  table: Table
  pending: Option(String)
  lines: UInt64
  bytes: UInt64
  bad: UInt64
end

# A key is 1 to 256 bytes with no space and no control character.
fn key?(text: String) : Bool
  # body gone; regenerate
end

# A value is at most 1 MiB and holds no line break.
fn value?(text: String) : Bool
  # body gone; regenerate
end

# The store whose log is jobq.log in the folder dir, replayed; a folder with no log yet
# holds an empty store.
fn open(fs: Fs, dir: String) : Result(Table, StoreError)
  # body gone; regenerate
end

fn get(table: Table, key: String) : Option(String)
  # body gone; regenerate
end

fn count(table: Table) : UInt64
  # body gone; regenerate
end

# The log's path, from the Fs the store was opened on.
fn log(table: Table) : String
  # body gone; regenerate
end

fn cut_short?(table: Table) : Bool
  # body gone; regenerate
end

# The lines open replayed, or compact wrote.
fn lines(table: Table) : UInt64
  # body gone; regenerate
end

# The store with the key set to the value, once its SET line is on disk.
fn put(fs: Fs, table: Table, key: String, value: String) : Result(Table, StoreError)
  requires key?(key)
  requires value?(value)
  ensures result is Ok(after) implies get(after, key) == Some(value)
  # body gone; regenerate
end

# The store without the key, once its DEL line is on disk; a key it does not hold writes
# nothing.
fn delete(fs: Fs, table: Table, key: String) : Result(Table, StoreError)
  ensures result is Ok(after) implies get(after, key) is None
  # body gone; regenerate
end

# Every key that starts with the prefix, in byte order.
fn keys(table: Table, prefix: String) : List(String)
  ensures result.all?(fn(key) key.starts_with?(prefix) end)
  # body gone; regenerate
end

# The log rewritten as one SET line per live key, keys in byte order: written whole beside the
# log, then renamed over it, so a compaction cut short leaves the old log as it was.
fn compact(fs: Fs, table: Table) : Result(Table, StoreError)
  ensures result is Ok(after) implies count(after) == count(table) and !cut_short?(after)
  # body gone; regenerate
end

# Every live key as its SET line, keys in byte order: what a compaction writes.
fn whole_text(table: Table) : String
  # body gone; regenerate
end

# The table once its log holds exactly the text a compaction wrote.
fn rewritten(table: Table, text: String) : Table
  # body gone; regenerate
end

# The same keys and values, their changes appended from now on to the empty log `name` in the
# same folder: jobq check serves a folder's log without writing to it.
fn writing_to(table: Table, name: String) : Table
  # body gone; regenerate
end

fn set_line(table: Table, key: String) : String
  # body gone; regenerate
end

# Appends a line and gives the log's size after it. An append that fails is looked at again:
# a log that holds the whole line took it, one as long as before did not, and anything else,
# or a size that cannot be read, may end in part of the line.
fn appended(fs: Fs, table: Table, line: String) : Result(UInt64, StoreError)
  # body gone; regenerate
end

fn resized(table: Table, bytes: UInt64) : Table
  # body gone; regenerate
end

# Which of the 256 maps holds a key.
fn bucket_of(key: String) : UInt64
  ensures result < 256
  # body gone; regenerate
end

fn mixed(hash: UInt64, b: UInt8) : UInt64
  # body gone; regenerate
end

fn placed(table: Table, key: String, value: String) : Table
  # body gone; regenerate
end

fn dropped(table: Table, key: String) : Table
  # body gone; regenerate
end

# One whole line of the log applied to the table: a SET with its key and the rest of the line
# as the value, or a DEL with its key; None for anything else.
fn applied(table: Table, line: String) : Option(Table)
  # body gone; regenerate
end

# The next line read: the one before it is whole, since another came after it, so it is
# applied. Replay stops applying at the first line that is not the store's.
fn stepped(replay: Replay, line: String) : Replay
  # body gone; regenerate
end

# The replay once the file is read: its last line applied when the file ends with its newline,
# and left out, cut short, when it does not.
fn finished(replay: Replay, bytes: UInt64) : Result(Table, StoreError)
  # body gone; regenerate
end

fn replayed_from(folder: Fs, start: Replay, name: String) : Result(Replay, StoreError)
  # body gone; regenerate
end

fn names_in(folder: Fs) : Result(List(String), StoreError)
  # body gone; regenerate
end

fn size_of(folder: Fs, name: String) : Result(UInt64, StoreError)
  # body gone; regenerate
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
  moved = writing_to(one, "jobq.check.log")
  assert put(Fs.fixture(delay: 1.minute), moved, "b", "2") is Error(Torn)
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
