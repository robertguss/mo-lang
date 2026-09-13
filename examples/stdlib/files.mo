module Stdlib.Files
expose Problem, log_names, line_count, bytes_of

intent "List a folder, read a file as lines, and size it, through an Fs whose every call can wait and says how long."

enum Problem
  Unread(path: String)
  Slow
end

fn log_names(logs: Fs) : Result(List(String), Problem)
  case logs.list(within: 1.minute)
    Ok(names): Ok(names.filter(fn(name) name.ends_with?(".log") end))
    Error(Missing(path)): Error(Unread(path: path))
    Error(Timeout): Error(Slow)
  end
end

fn line_count(logs: Fs, name: String) : Result(UInt64, Problem)
  case logs.read_lines(name, within: 1.minute)
    Ok(lines): Ok(lines.size)
    Error(Missing(path)): Error(Unread(path: path))
    Error(Timeout): Error(Slow)
  end
end

fn bytes_of(logs: Fs, name: String) : Result(UInt64, Problem)
  case logs.size(name, within: 1.minute)
    Ok(n): Ok(n)
    Error(Missing(path)): Error(Unread(path: path))
    Error(Timeout): Error(Slow)
  end
end

test "an empty file system lists nothing and reads nothing"
  assert log_names(Fs.fixture()) is Ok(names)
  assert names.size == 0
  assert line_count(Fs.fixture(), "a.log") is Error(Unread("a.log"))
  assert bytes_of(Fs.fixture(), "a.log") is Error(Unread("a.log"))
end

test "a slow file system times out every call that waits less than its delay"
  slow = Fs.fixture(delay: 2.minute)
  assert log_names(slow) is Error(Slow)
  assert line_count(slow, "a.log") is Error(Slow)
  assert bytes_of(slow, "a.log") is Error(Slow)
end

verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run
