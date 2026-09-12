module Tests.Property
expose double
intent "Generate bounded inputs and check the same property for each one."

fn double(n: UInt32) : UInt32
  n * 2
end

test "a concrete example doubles"
  assert double(3) == 6
end

property "doubling small values is reversible"
  for n in any(UInt32) if n <= 1_000
    assert double(n) / 2 == n
  end
end
