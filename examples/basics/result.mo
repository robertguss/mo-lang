module Basics.Result
expose parse, twice

intent "Ok, Error, and try through two calls."

enum ParseError
  Empty
end

fn parse(n: UInt32) : Result(UInt32, ParseError)
  if n == 0
    return Error(Empty)
  end
  Ok(n)
end

fn twice(n: UInt32) : Result(UInt32, ParseError)
  a = try parse(n)
  b = try parse(a)
  Ok(b + b)
end

test "try stops on Error"
  assert twice(1) is Ok(c)
  assert c == 2
  assert twice(0) is Error(Empty)
end
