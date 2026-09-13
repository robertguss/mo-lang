module Rejects.AliasedVar
expose raise_all

intent "A var is never aliased; an anonymous function that captures one does not compile."

# expect MO0314: bump is a var and cannot be captured by the anonymous function; bind a plain name first.
fn raise_all(prices: List(UInt32), extra: UInt32) : List(UInt32)
  var bump = 5
  bump += extra
  prices.map(fn(price) price + bump end)
end

test "every price is raised by the same amount"
  assert raise_all([100, 200], 5) == [110, 210]
  assert raise_all([], 0) == []
end
