module Jobq.Journal
expose opened_by, continued, put_all, deleted_from, compacted

use Jobq.Store{Table, StoreError, Replay, key?, value?, open, get, count, cut_short?, put, keys, lines, writing_to, whole_text, rewritten, placed, dropped, resized, stepped, finished}

intent "The store's file calls on a caller's deadline: the queue service opens, replays, appends to, and rewrites jobq's log on what remains of the ask it answers, so nothing it does waits past its asker; the store's recipe functions keep their own deadlines for main and the recipe's tests."

# The store whose log is jobq.log in the folder dir, replayed on the deadline; a folder with no
# log yet holds an empty store.
fn opened_by(fs: Fs, dir: String, by: Deadline) : Result(Table, StoreError)
  folder = fs.scoped(dir)
  names = try names_in(folder, by)
  empty = Table(buckets: Map.new(), size: 0, dir: dir, name: "jobq.log", bytes: 0, lines: 0,
    cut: false)
  return Ok(empty) if !names.contains?("jobq.log")
  replayed_into(folder, empty, "jobq.log", by)
end

# The store with another log in its folder replayed over it, its changes appended to that log
# from now on: jobq check replays a folder's log, then the changes it made since it started.
fn continued(fs: Fs, table: Table, name: String, by: Deadline) : Result(Table, StoreError)
  folder = fs.scoped(table.dir)
  moved = writing_to(table, name)
  names = try names_in(folder, by)
  return Ok(moved) if !names.contains?(name)
  replayed_into(folder, moved, name, by)
end

# The store with every pair set, in order, once all their SET lines are on disk in one append:
# one wait for the disk however many changes a look makes.
fn put_all(fs: Fs, table: Table, pairs: List((String, String)), by: Deadline) : Result(Table,
  StoreError)
  requires pairs.all?(fn(pair) key?(pair.0) and value?(pair.1) end)

  return Ok(table) if pairs.size == 0
  text = String.join(pairs.map(fn(pair) "SET #{pair.0} #{pair.1}\n" end), "")
  bytes = try appended(fs, table, text, by)
  set = pairs.reduce(table, fn(so_far, pair) placed(so_far, pair.0, pair.1) end)
  Ok(resized(set, bytes))
end

# The store without the key, once its DEL line is on disk; a key it does not hold writes
# nothing.
fn deleted_from(fs: Fs, table: Table, key: String, by: Deadline) : Result(Table, StoreError)
  ensures result is Ok(after) implies get(after, key) is None

  return Ok(table) if get(table, key) is None
  bytes = try appended(fs, table, "DEL #{key}\n", by)
  Ok(resized(dropped(table, key), bytes))
end

# The log rewritten as one SET line per live key, beside the log and renamed over it; the write
# may take at most 20 seconds of what remains, so the rename has time left.
fn compacted(fs: Fs, table: Table, by: Deadline) : Result(Table, StoreError)
  ensures result is Ok(after) implies count(after) == count(table) and !cut_short?(after)

  folder = fs.scoped(table.dir)
  text = whole_text(table)
  fresh = "#{table.name}.new"
  return Error(Unwritten) if folder.write(fresh, text, within: by.at_most(20_000.ms)) is Error(_)
  return Error(Unwritten) if folder.rename(fresh, table.name, within: by) is Error(_)
  Ok(rewritten(table, text))
end

# Appends a line and gives the log's size after it. The append may take at most 5 seconds of
# what remains, so a failed one can be looked at again: a log that holds the whole line took it,
# one as long as before did not, and anything else, or a size that cannot be read, may end in
# part of the line.
fn appended(fs: Fs, table: Table, line: String, by: Deadline) : Result(UInt64, StoreError)
  folder = fs.scoped(table.dir)
  after = table.bytes + line.byte_size
  return Ok(after) if folder.append(table.name, line, within: by.at_most(5_000.ms)) is Ok(_)
  case folder.size(table.name, within: by)
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

fn replayed_into(folder: Fs, table: Table, name: String, by: Deadline) : Result(Table, StoreError)
  bytes = try size_of(folder, name, by)
  start = Replay(table: table, pending: None, lines: 0, bytes: 0, bad: 0)
  replayed = try replayed_from(folder, start, name, by)
  return Error(BadLine(number: replayed.bad)) if replayed.bad > 0
  finished(replayed, bytes)
end

fn replayed_from(folder: Fs, start: Replay, name: String, by: Deadline) : Result(Replay, StoreError)
  case folder.fold_lines(name, start, within: by, fn(replay, line) stepped(replay, line) end)
    Ok(replay): Ok(replay)
    Error(Missing(_)): Error(Unreadable)
    Error(Timeout): Error(Slow)
    Error(NotText): Error(Unreadable)
  end
end

fn names_in(folder: Fs, by: Deadline) : Result(List(String), StoreError)
  case folder.list(within: by)
    Ok(names): Ok(names)
    Error(Missing(_)): Error(NoFolder)
    Error(Timeout): Error(Slow)
    Error(NotText): Error(NoFolder)
  end
end

fn size_of(folder: Fs, name: String, by: Deadline) : Result(UInt64, StoreError)
  case folder.size(name, within: by)
    Ok(bytes): Ok(bytes)
    Error(Missing(_)): Error(Unreadable)
    Error(Timeout): Error(Slow)
    Error(NotText): Error(Unreadable)
  end
end

test rejects "a put of many with a key holding a space"
  fs = Fs.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(empty)
  assert put_all(fs, empty, [("a", "1"), ("b c", "2")], Deadline.fixture(1.minute)) is Error(_)
end

test "many pairs go to the log in one append, and another log replays over the first"
  fs = Fs.fixture()
  by = Deadline.fixture(1.minute)
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert opened_by(fs, "d", by) is Ok(empty)
  assert put(fs, empty, "a", "1") is Ok(one)
  assert put_all(fs, one, [("b", "2"), ("a", "3"), ("c", "4")], by) is Ok(many)
  assert get(many, "a") == Some("3") and count(many) == 3
  assert put_all(fs, many, [], by) == Ok(many)
  assert fs.read("d/jobq.log", within: 1.minute) == Ok("SET a 1\nSET b 2\nSET a 3\nSET c 4\n")
  assert continued(fs, many, "jobq.check.log", by) is Ok(moved)
  assert deleted_from(fs, moved, "b", by) is Ok(dropped)
  assert put_all(fs, dropped, [("d", "5")], by) is Ok(later)
  assert opened_by(fs, "d", by) is Ok(first)
  assert continued(fs, first, "jobq.check.log", by) is Ok(again)
  assert keys(again, "") == keys(later, "")
  assert get(again, "a") == Some("3") and lines(again) == 2
end

test "a deadline with nothing left writes nothing and may leave the log torn, and a compaction mends it"
  fs = Fs.fixture()
  by = Deadline.fixture(1.minute)
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert opened_by(fs, "d", by) is Ok(empty)
  assert put_all(fs, empty, [("a", "1")], by) is Ok(one)
  assert put_all(fs, one, [("b", "2")], Deadline.fixture(0.ms)) is Error(Torn)
  assert deleted_from(fs, one, "a", Deadline.fixture(0.ms)) is Error(Torn)
  assert opened_by(fs, "d", Deadline.fixture(0.ms)) is Error(Slow)
  assert compacted(fs, one, by) is Ok(whole)
  assert !cut_short?(whole) and lines(whole) == 1
  assert fs.read("d/jobq.log", within: 1.minute) == Ok("SET a 1\n")
end

verified: types, contracts, tests (3), property (0 seeds), sim (not run)
          proven: not run
