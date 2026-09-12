module Rejects.HandEditedVerified
expose keep
intent "Verification evidence is computed by the toolchain, never claimed by hand."
# expect error: The verified line was authored instead of computed by the toolchain.

fn keep(n: UInt32) : UInt32
  n
end

test "passing assertions do not authorize a verification claim"
  assert keep(1) == 1
  assert keep(0) == 0
end

verified: types, contracts, tests (1)
