module Types.Refinement
expose Percent, discount

intent "Narrow a number with a where clause, so an out-of-range value is stopped at the boundary."

type Percent = UInt32 where value <= 100

fn discount(price: UInt32, off: Percent) : UInt32
  price - price * off / 100
end

test "ten percent off"
  assert discount(2_000, 10) == 1_800
end

test "both edges of the range are allowed"
  assert discount(2_000, 0) == 2_000
  assert discount(2_000, 100) == 0
end

test rejects "a percent above one hundred"
  discount(2_000, 150)
end

verified: types, contracts, tests (3), property (0 seeds), sim (not run)
          proven: not run
