module Types.Refinement
expose Money, take

intent "Refinement type Money; the boundary is a rejects test."

type Money = UInt64 where value <= 1_000_000_00

fn take(m: Money) : Money
  m
end

test "at the cap"
  assert take(1_000_000_00) == 1_000_000_00
end

test rejects "one over the cap"
  take(1_000_000_01)
end
