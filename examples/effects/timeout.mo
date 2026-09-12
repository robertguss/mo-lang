module Effects.Timeout
expose ReadError, describe
intent "Handle Timeout as ordinary data alongside another expected error."

enum ReadError
  Missing
  Timeout
end

fn describe(reply: Result(String, ReadError)) : String
  case reply
    Ok(text): text
    Error(Missing): "missing"
    Error(Timeout): "timed out"
  end
end

test "the caller consumes every read outcome"
  assert describe(Ok("ready")) == "ready"
  assert describe(Error(Missing)) == "missing"
  assert describe(Error(Timeout)) == "timed out"
end
