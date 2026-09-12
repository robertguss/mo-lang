module Basics.Result
expose InputError, double
intent "Propagate expected failure through two calls with try."

enum InputError
  Empty
end

fn positive(n: UInt32) : Result(UInt32, InputError)
  return Error(Empty) if n == 0
  Ok(n)
end

fn bounded(n: UInt32) : Result(UInt32, InputError)
  value = try positive(n)
  Ok(value % 100)
end

fn double(n: UInt32) : Result(UInt32, InputError)
  value = try bounded(n)
  Ok(value * 2)
end

test "success and failure travel through both callers"
  case double(3)
    Ok(n):
      assert n == 6
    Error(Empty):
      assert false
  end
  case double(0)
    Ok(n):
      assert n == 0 and false
    Error(Empty):
      assert true
  end
end
