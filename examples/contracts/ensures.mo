module Contracts.Ensures
expose StepError, advance
intent "Relate a successful result to the entry value of an inout argument."

enum StepError
  Full
end

fn advance(inout n: UInt32) : Result(UInt32, StepError)
  ensures result is Ok(c) implies c == old(n) + 1

  return Error(Full) if n >= 100
  n += 1
  Ok(n)
end

test "success changes the caller's value"
  var n = 2
  assert advance(n) is Ok(c)
  assert c == 3
  assert n == 3
end

test "a full counter stays unchanged"
  var n = 100
  case advance(n)
    Ok(_):
      assert false
    Error(Full):
      assert n == 100
  end
end
