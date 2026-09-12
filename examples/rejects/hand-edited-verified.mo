module Rejects.HandEditedVerified
expose one

intent "A hand-edited verified: line is a compile error."
# expect error: verified: is toolchain-owned and may not be edited by hand

fn one() : UInt32
  1
end

test "one is one"
  assert one() == 1
end

verified: types, contracts, tests (1)
