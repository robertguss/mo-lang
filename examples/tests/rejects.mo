module Tests.Rejects
expose share
intent "Use a rejects test as evidence for a function's requires clause."

fn share(total: UInt32, people: UInt32) : UInt32
  requires people > 0

  total / people
end

test "a nonzero group can share a total"
  assert share(12, 3) == 4
end

test rejects "zero people violates the precondition"
  share(12, 0)
end
