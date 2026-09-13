module Stdlib.Files
expose Problem, log_names, line_count, bytes_of, bytes_read, echo_lines, text_bytes

intent "List a folder, read a file as lines, one line at a time, folded, or as bytes, and size it, through an Fs whose every call can wait and says how long."

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

# Each line goes to out as it is read; the file is never held whole.
fn echo_lines(logs: Fs, name: String, out: Out) : Option(Problem)
  case logs.each_line(name, within: 1.minute, fn(line) out.write_line("> #{line}") end)
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

test "each_line hands the function one line at a time, split as lines splits them"
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

verified: types, contracts, tests (5), property (0 seeds), sim (not run)
          proven: not run
