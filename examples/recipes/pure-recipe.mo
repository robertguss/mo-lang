module Recipes.PureRecipe
expose Clamp, ceiling
intent "Specify a bounded pure computation with needs nothing."

fn ceiling() : UInt32
  10
end

recipe Clamp
  intent "Keep a value at or below ten without any capability"
  needs nothing
  fn clamp(n: UInt32) : UInt32
    ensures result <= ceiling()
  end
  test "a small value stays unchanged"
    assert clamp(3) == 3
  end
  test "a large value reaches the ceiling"
    assert clamp(12) == ceiling()
  end
end

test "the recipe's ceiling is ten"
  assert ceiling() == 10
end
