module Recipes.Store
expose StoreError, Read, Reopened, Store

intent "Publish a durable string map over an append-only log as intent, signatures, and tests, for an agent to implement over Fs."

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

recipe Store
  # Session 5, step 22: the rewrite rule, jobq's, after notes refused every change past a torn
  # log until it started again, so its work never resumed once faults stopped.
  intent "A durable map from String keys to String values over an append-only log in a folder: each change is on disk before put or delete returns, open replays the log and leaves out a last line cut short, and compact rewrites the log as one line per live key; a log that may end in part of a change (Torn) is rewritten whole with compact at the next change, and changes are taken from then on, so work resumes once faults stop"
  needs Fs
  fn key?(text: String) : Bool
  end
  fn value?(text: String) : Bool
  end
  fn open(fs: Fs, dir: String) : Result(Table, StoreError)
  end
  fn get(table: Table, key: String) : Option(String)
  end
  fn count(table: Table) : UInt64
  end
  fn log(table: Table) : String
  end
  fn cut_short?(table: Table) : Bool
  end
  fn put(fs: Fs, table: Table, key: String, value: String) : Result(Table, StoreError)
    requires key?(key)
    requires value?(value)
    ensures result is Ok(after) implies get(after, key) == Some(value)
  end
  fn delete(fs: Fs, table: Table, key: String) : Result(Table, StoreError)
    ensures result is Ok(after) implies get(after, key) is None
  end
  fn keys(table: Table, prefix: String) : List(String)
    ensures result.all?(fn(key) key.starts_with?(prefix) end)
  end
  fn compact(fs: Fs, table: Table) : Result(Table, StoreError)
    ensures result is Ok(after) implies count(after) == count(table) and !cut_short?(after)
  end
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
  test "a value put reads back, and reads back again once the store is opened again"
    fs = Fs.fixture()
    assert fs.mkdir("d", within: 1.minute) is Ok(_)
    assert open(fs, "d") is Ok(empty)
    assert put(fs, empty, "a", "one") is Ok(one)
    assert put(fs, one, "a", "two words") is Ok(two)
    assert get(two, "a") == Some("two words")
    assert count(two) == 1
    assert open(fs, "d") is Ok(again)
    assert get(again, "a") == Some("two words")
    assert count(again) == count(two)
  end
  test "a deleted key is gone, and stays gone once the store is opened again"
    fs = Fs.fixture()
    assert fs.mkdir("d", within: 1.minute) is Ok(_)
    assert open(fs, "d") is Ok(empty)
    assert put(fs, empty, "a", "1") is Ok(one)
    assert delete(fs, one, "a") is Ok(none)
    assert get(none, "a") is None
    assert open(fs, "d") is Ok(again)
    assert count(again) == 0
  end
  test "keys under a prefix come in byte order"
    fs = Fs.fixture()
    assert fs.mkdir("d", within: 1.minute) is Ok(_)
    assert open(fs, "d") is Ok(empty)
    assert put(fs, empty, "b/2", "x") is Ok(first)
    assert put(fs, first, "a/1", "x") is Ok(second)
    assert put(fs, second, "b/10", "x") is Ok(third)
    assert keys(third, "b/") == ["b/10", "b/2"]
    assert keys(third, "") == ["a/1", "b/10", "b/2"]
  end
  test "a last line cut short is left out, and a compacted store takes changes again"
    fs = Fs.fixture()
    assert fs.mkdir("d", within: 1.minute) is Ok(_)
    assert open(fs, "d") is Ok(empty)
    assert put(fs, empty, "a", "1") is Ok(one)
    assert put(fs, one, "b", "2") is Ok(two)
    assert fs.read(log(two), within: 1.minute) is Ok(text)
    assert fs.write(log(two), text.slice(0, text.size - 1), within: 1.minute) is Ok(_)
    assert open(fs, "d") is Ok(cut)
    assert cut_short?(cut)
    assert get(cut, "b") is None
    assert compact(fs, cut) is Ok(whole)
    assert fs.read_lines(log(whole), within: 1.minute) is Ok(lines)
    assert lines.size == count(whole)
    assert put(fs, whole, "c", "3") is Ok(more)
    assert open(fs, "d") is Ok(again)
    assert !cut_short?(again)
    assert get(again, "a") == Some("1")
    assert get(again, "c") == Some("3")
    assert count(again) == count(more)
  end
  test "a change the log may have torn is taken once the log is rewritten whole"
    fs = Fs.fixture()
    assert fs.mkdir("d", within: 1.minute) is Ok(_)
    assert open(fs, "d") is Ok(empty)
    assert put(fs, empty, "a", "1") is Ok(one)
    assert put(Fs.fixture(delay: 1.minute), one, "b", "2") is Error(Torn)
    assert compact(fs, one) is Ok(whole)
    assert put(fs, whole, "b", "2") is Ok(two)
    assert open(fs, "d") is Ok(again)
    assert !cut_short?(again) and count(again) == count(two)
    assert get(again, "a") == Some("1") and get(again, "b") == Some("2")
  end
  test "a folder too slow to read is Slow"
    assert open(Fs.fixture(delay: 1.minute), "d") is Error(Slow)
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
end

verified: types, contracts, tests (0), property (0 seeds), sim (not run)
          proven: not run
