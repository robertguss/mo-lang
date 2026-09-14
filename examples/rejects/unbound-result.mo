module Rejects.UnboundResult
expose clamped

intent "result is a keyword only inside an ensures: a body that reads result as the value it returns reads a name nothing binds."

# expect MO0201: there is no result in scope: result is a keyword only inside an ensures, where it is the value the function returns; elsewhere it is a name like any other, and no result is in scope
fn clamped(n: UInt32, most: UInt32) : UInt32
  ensures result <= most

  if n > most
    return most
  end
  result
end

test "a number past the most is clamped"
  assert clamped(5, 3) == 3
end
