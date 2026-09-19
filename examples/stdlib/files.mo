module Stdlib.Files
expose Problem, log_names, log_files, line_count, bytes_of, bytes_read, echo_lines, text_bytes

intent "List a folder, telling its files from its folders, read a file as lines, one line at a time, folded, or as bytes, and size it, through an Fs whose every call can wait and says how long."

enum Problem
  Unread(path: String)
  Slow
  Binary(path: String)
end

fn log_names(logs: Fs) : Result(List(String), Problem)
  case logs.list(within: 1.minute)
    Ok(names): Ok(names.filter(fn(name) name.ends_with?(".log") end))
    Error(Missing(path)): Error(Unread(path: path))
    Error(Timeout): Error(Slow)
    Error(NotText): Error(Binary(path: "."))
  end
end

# The names ending in .log that are files: a folder named old.log is not one (step 28).
fn log_files(logs: Fs) : Result(List(String), Problem)
  case logs.list_kinds(within: 1.minute)
    Ok(entries):
      Ok(entries.filter(fn(e)
        e.kind == File and e.name.ends_with?(".log")
      end).map(fn(e) e.name end))
    Error(Missing(path)): Error(Unread(path: path))
    Error(Timeout): Error(Slow)
    Error(NotText): Error(Binary(path: "."))
  end
end

fn line_count(logs: Fs, name: String) : Result(UInt64, Problem)
  case logs.read_lines(name, within: 1.minute)
    Ok(lines): Ok(lines.size)
    Error(Missing(path)): Error(Unread(path: path))
    Error(Timeout): Error(Slow)
    Error(NotText): Error(Binary(path: name))
  end
end

fn bytes_of(logs: Fs, name: String) : Result(UInt64, Problem)
  case logs.size(name, within: 1.minute)
    Ok(n): Ok(n)
    Error(Missing(path)): Error(Unread(path: path))
    Error(Timeout): Error(Slow)
    Error(NotText): Error(Binary(path: name))
  end
end

# The bytes as they are on disk, which read_bytes gives whether or not they are UTF-8 text.
fn bytes_read(logs: Fs, name: String) : Result(List(UInt8), Problem)
  case logs.read_bytes(name, within: 1.minute)
    Ok(bytes): Ok(bytes)
    Error(Missing(path)): Error(Unread(path: path))
    Error(Timeout): Error(Slow)
    Error(NotText): Error(Binary(path: name))
  end
end

# Each line goes to out as it is read; the file is never held whole. The anonymous function
# captures no capability, so out is handed on as fold_lines' value.
fn echo_lines(logs: Fs, name: String, out: Out) : Option(Problem)
  echoed = logs.fold_lines(name, out, within: 1.minute, fn(to, line)
    to.write_line("> #{line}")
    to
  end)
  case echoed
    Ok(_): None
    Error(Missing(path)): Some(Unread(path: path))
    Error(Timeout): Some(Slow)
    Error(NotText): Some(Binary(path: name))
  end
end

# The bytes of a file's lines without their line ends, kept as the lines are read.
fn text_bytes(logs: Fs, name: String) : Result(UInt64, Problem)
  case logs.fold_lines(name, 0, within: 1.minute, fn(total, line) total + line.byte_size end)
    Ok(total): Ok(total)
    Error(Missing(path)): Error(Unread(path: path))
    Error(Timeout): Error(Slow)
    Error(NotText): Error(Binary(path: name))
  end
end

test "an empty file system lists nothing and reads nothing"
  assert log_names(Fs.fixture()) is Ok(names)
  assert names.size == 0
  assert line_count(Fs.fixture(), "a.log") is Error(Unread("a.log"))
  assert bytes_of(Fs.fixture(), "a.log") is Error(Unread("a.log"))
  assert bytes_read(Fs.fixture(), "a.log") is Error(Unread("a.log"))
end

test "list_kinds tells a file from a folder, sorted by name as list sorts"
  fs = Fs.fixture()
  assert fs.mkdir("old.log", within: 1.minute) is Ok(_)
  assert fs.mkdir("logs", within: 1.minute) is Ok(_)
  assert fs.write("logs/b.log", "two", within: 1.minute) is Ok(_)
  assert fs.write("a.log", "one", within: 1.minute) is Ok(_)
  assert fs.list(within: 1.minute) == Ok(["a.log", "logs", "old.log"])
  assert fs.list_kinds(within: 1.minute) == Ok([Entry(name: "a.log", kind: File, links: 1, setuid: false),
    Entry(name: "logs", kind: Folder, links: 1, setuid: false),
    Entry(name: "old.log", kind: Folder, links: 1, setuid: false)])
  assert log_names(fs) == Ok(["a.log", "old.log"])
  assert log_files(fs) == Ok(["a.log"])
  assert log_files(Fs.fixture(delay: 2.minute)) is Error(Slow)
end

test "fold_lines keeps a value across the lines, split as lines splits them"
  fs = Fs.fixture()
  assert fs.write("a.log", "one\r\ntwo\n\nlast", within: 1.minute) is Ok(_)
  assert text_bytes(fs, "a.log") is Ok(10)
  assert fs.write("empty.log", "", within: 1.minute) is Ok(_)
  assert text_bytes(fs, "empty.log") is Ok(0)
  assert text_bytes(fs, "b.log") is Error(Unread("b.log"))
  assert text_bytes(Fs.fixture(delay: 2.minute), "a.log") is Error(Slow)
end

test "read_bytes gives a file's bytes, as many as its size"
  fs = Fs.fixture()
  assert fs.write("a.log", "é\n", within: 1.minute) is Ok(_)
  assert bytes_read(fs, "a.log") == Ok([195, 169, 10])
  assert bytes_of(fs, "a.log") == Ok(3)
end

test "fold_lines hands out on from line to line, split as lines splits them"
  fs = Fs.fixture()
  assert fs.write("a.log", "one\r\ntwo\n\nlast", within: 1.minute) is Ok(_)
  out = Out.fixture()
  assert echo_lines(fs, "a.log", out) is None
  assert out.written == ["> one\n", "> two\n", "> \n", "> last\n"]
  assert echo_lines(fs, "b.log", out) is Some(Unread("b.log"))
  assert echo_lines(Fs.fixture(delay: 2.minute), "a.log", out) is Some(Slow)
end

test "a slow file system times out every call that waits less than its delay"
  slow = Fs.fixture(delay: 2.minute)
  assert log_names(slow) is Error(Slow)
  assert line_count(slow, "a.log") is Error(Slow)
  assert bytes_of(slow, "a.log") is Error(Slow)
  assert bytes_read(slow, "a.log") is Error(Slow)
end

verified: types, contracts, tests (6), property (0 seeds), sim (not run)
          proven: not run
