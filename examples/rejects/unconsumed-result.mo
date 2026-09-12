module Rejects.UnconsumedResult
expose ReadError, ignore
intent "Consume a Result even when its success value is not needed."
# expect error: The Result returned by read is discarded.

enum ReadError
  Missing
end

fn read() : Result(UInt32, ReadError)
  Ok(1)
end

fn ignore() : UInt32
  read()
  0
end

test "discarding the result prevents compilation"
  assert ignore() == 0
end
