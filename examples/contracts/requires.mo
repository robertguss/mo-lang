module Contracts.Requires
expose split

intent "State what a caller must guarantee before the body runs."

fn split(total: UInt32, people: UInt32) : UInt32
  requires people > 0

  total / people
end

test "a bill splits evenly"
  assert split(90, 3) == 30
end

test rejects "splitting a bill among nobody"
  split(90, 0)
end
