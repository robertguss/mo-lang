module Tests.Property
expose discount

intent "Check a claim across many generated inputs instead of a few hand-picked ones."

fn discount(price: UInt32) : UInt32
  price - price / 10
end

test "ten percent off a round price"
  assert discount(1_000) == 900
end

property "a discount always lowers a price of ten or more"
  for price in any(UInt32) if price >= 10
    assert discount(price) < price
  end
end
