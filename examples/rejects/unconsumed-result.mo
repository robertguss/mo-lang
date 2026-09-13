module Rejects.UnconsumedResult
expose SaveError, save, touch

intent "Every Result is consumed; calling a function and dropping its Result does not compile."
# expect MO0310: the Result from save(count) is dropped; match it with case or pass it up with try.

enum SaveError
  Full
end

fn save(count: UInt32) : Result(UInt32, SaveError)
  return Error(Full) if count >= 10
  Ok(count + 1)
end

fn touch(count: UInt32) : UInt32
  save(count)
  count
end

test "touch hands back the count it was given"
  assert touch(3) == 3
  assert save(3) is Ok(4)
end
