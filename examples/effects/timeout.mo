module Effects.Timeout
expose ReadError, load, config

intent "A slow read is an ordinary error value, and the caller decides what a timeout means."

enum ReadError
  Missing(path: String)
  Timeout
end

fn load(fs: Fs, path: String) : Result(String, ReadError)
  text = try fs.read(path, within: 100.ms)
  Ok(text)
end

fn config(fs: Fs) : Result(String, ReadError)
  case load(fs, "/etc/app.conf")
    Ok(text): Ok(text)
    Error(Missing(path: _)): Ok("defaults")
    Error(Timeout): Error(Timeout)
  end
end

test "a missing file falls back to the defaults"
  assert config(Fs.fixture()) is Ok("defaults")
end

test "a timeout is passed on, not papered over"
  assert config(Fs.fixture(delay: 1.minute)) is Error(Timeout)
end
