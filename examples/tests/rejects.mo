module Tests.Rejects
expose take

intent "Prove a requires fires with a test rejects, which passes only when its body trips the contract."

fn take(stock: UInt32, n: UInt32) : UInt32
  requires n <= stock

  stock - n
end

test "taking what is on the shelf"
  assert take(5, 2) == 3
  assert take(5, 5) == 0
end

test rejects "taking more than is on the shelf"
  take(5, 6)
end
