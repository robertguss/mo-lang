module Types.Refinement
expose Money, balance
intent "Check a primitive refinement whenever a value crosses a boundary."

type Money = UInt64 where value <= 1_000_000_00

fn balance(amount: Money) : Money
  amount
end

test "the upper boundary is valid"
  assert balance(1_000_000_00) == 1_000_000_00
  assert balance(0) == 0
end

test rejects "one cent above the upper boundary"
  balance(1_000_000_01)
end
