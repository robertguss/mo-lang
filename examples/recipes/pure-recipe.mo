module Recipes.PureRecipe
expose Twice, Box

intent "A recipe that needs nothing is pure."

struct Box
  n: UInt32
end

recipe Twice
  intent "Double a number; no effects"
  needs nothing
  fn apply(b: Box) : Box
    ensures result.n == b.n + b.n
  end
end

test "the box is just a number"
  b = Box(n: 2)
  assert b.n == 2
end
