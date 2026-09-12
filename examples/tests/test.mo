module Tests.Test
expose ParseError, parse

intent "assert, and assert x is Ok(c)."

enum ParseError
  Empty
end

fn parse(n: UInt32) : Result(UInt32, ParseError)
  if n == 0
    return Error(Empty)
  end
  Ok(n)
end

test "binds the Ok payload"
  r = parse(4)
  assert r is Ok(c)
  assert c == 4
end
