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
  # body gone; regenerate
end

# A value is at most 1 MiB and holds no line break.
fn value?(text: String) : Bool
  # body gone; regenerate
end

# The store whose log is ledger.log in the folder dir, replayed; a folder with no log yet holds
# an empty store.
fn open(fs: Fs, dir: String) : Result(Table, StoreError)
  # body gone; regenerate
end

fn begun(table: Table) : Replay
  # body gone; regenerate
end

fn get(table: Table, key: String) : Option(String)
  # body gone; regenerate
end

fn count(table: Table) : UInt64
  # body gone; regenerate
end

fn log(table: Table) : String
  # body gone; regenerate
end

fn cut_short?(table: Table) : Bool
  # body gone; regenerate
end

fn lines(table: Table) : UInt64
  # body gone; regenerate
end

fn put(fs: Fs, table: Table, key: String, value: String) : Result(Table, StoreError)
  requires key?(key)
  requires value?(value)
  ensures result is Ok(after) implies get(after, key) == Some(value)
  # body gone; regenerate
end

fn delete(fs: Fs, table: Table, key: String) : Result(Table, StoreError)
  ensures result is Ok(after) implies get(after, key) is None
  # body gone; regenerate
end

fn keys(table: Table, prefix: String) : List(String)
  ensures result.all?(fn(key) key.starts_with?(prefix) end)
  # body gone; regenerate
end

# The log rewritten as one SET line per live key, keys in byte order, beside the log and renamed
# over it, so a compaction cut short leaves the old log as it was.
fn compact(fs: Fs, table: Table) : Result(Table, StoreError)
  ensures result is Ok(after) implies count(after) == count(table) and !cut_short?(after)
  # body gone; regenerate
end

fn set_line(key: String, value: String) : String
  # body gone; regenerate
end

# Pairs as one batch: a BEGIN line with their count, then a SET line for each, so a replay
# applies all of them or, when the log ends before the last, none.
fn batch_text(pairs: List((String, String))) : String
  # body gone; regenerate
end

fn appended(fs: Fs, table: Table, line: String) : Result(UInt64, StoreError)
  # body gone; regenerate
end

fn resized(table: Table, bytes: UInt64) : Table
  # body gone; regenerate
end

fn bucket_of(key: String) : UInt64
  ensures result < 256
  # body gone; regenerate
end

fn placed(table: Table, key: String, value: String) : Table
  # body gone; regenerate
end

fn dropped(table: Table, key: String) : Table
  # body gone; regenerate
end

# One whole line applied: a SET with its key and the rest of the line as the value, or a DEL.
fn applied(table: Table, line: String) : Option(Table)
  # body gone; regenerate
end

# The next line read: the one before it is whole, since another came after it, so it is taken.
fn stepped(replay: Replay, line: String) : Replay
  # body gone; regenerate
end

# A whole line taken: a BEGIN opens a batch, a line inside a batch waits for the rest of it, and
# any other line applies at once; a batch applies once its last line is taken.
fn taken(replay: Replay, line: String) : Replay
  # body gone; regenerate
end

fn applied_all(replay: Replay, lines: List(String)) : Replay
  # body gone; regenerate
end

# The replay once the file is read: its last line taken when the file ends with its newline, and
# a last line or a last batch cut short left out.
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
