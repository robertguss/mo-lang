module Rejects.MissingWithin
expose ReadError, load

intent "Every effectful call carries a deadline; a capability call without within: does not compile."

# expect MO0401: fs.read has no within: deadline; add one, such as within: 100.ms.
enum ReadError
  Missing(path: String)
  Timeout
end

fn load(fs: Fs, path: String) : Result(String, ReadError)
  text = try fs.read(path)
  Ok(text)
end

test "a file that is not there is Missing"
  assert load(Fs.fixture(), "/etc/app.conf") is Error(Missing("/etc/app.conf"))
end
