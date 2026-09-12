module Tests.Rejects
expose clamp

intent "One requires, one rejects that trips it."

fn clamp(n: UInt32) : UInt32
  requires n > 0

  n
end

test "positive passes"
  assert clamp(2) == 2
end

test rejects "zero trips requires"
  clamp(0)
end
