module Types.Nested
expose LoadError, unwrap

intent "Result(Option(T), E) handled on every arm."

enum LoadError
  Missing
  Timeout
end

fn unwrap(r: Result(Option(UInt32), LoadError)) : UInt32
  case r
    Ok(Some(n)): n
    Ok(None): 0
    Error(Missing): 0
    Error(Timeout): 0
  end
end

test "all four shapes"
  assert unwrap(Ok(Some(3))) == 3
  assert unwrap(Ok(None)) == 0
  assert unwrap(Error(Missing)) == 0
  assert unwrap(Error(Timeout)) == 0
end
