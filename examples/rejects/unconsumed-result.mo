module Rejects.UnconsumedResult
expose Boom, go

intent "Every Result must be consumed."
# expect error: unconsumed Result is a compile error

enum Boom
  Fail
end

fn go() : Result(UInt32, Boom)
  Ok(1)
end

test "drops the Result"
  go()
end
