module Rejects.StoredAnonymousFunction
expose cheap

intent "An anonymous function is only ever a call argument; binding one to a name does not compile."

# expect MO0313: an anonymous function is bound to under; pass it straight into filter instead.
fn cheap(prices: List(UInt32)) : List(UInt32)
  under = fn(price) price < 100 end
  prices.filter(under)
end

test "only prices under one hundred are kept"
  assert cheap([50, 150, 90]) == [50, 90]
  assert cheap([]) == []
end
