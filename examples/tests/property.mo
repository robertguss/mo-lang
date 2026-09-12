module Tests.Property
expose inc

intent "property with any(Type) and a guard."

fn inc(n: UInt32) : UInt32
  n + 1
end

test "one plus one"
  assert inc(1) == 2
end

property "inc is above its input"
  for n in any(UInt32) if n < 10
    assert inc(n) > n
  end
end
