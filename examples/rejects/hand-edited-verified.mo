module Rejects.HandEditedVerified
expose split

intent "The verified: line belongs to the toolchain; a line written by hand does not compile."

# expect MO0317: the verified: line was written by hand; delete it and let the toolchain compute it.
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

verified: types, contracts, tests (2), property (200 seeds), sim (1_000 runs)
