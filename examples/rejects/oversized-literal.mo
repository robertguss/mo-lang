module Rejects.OversizedLiteral
expose largest

intent "A literal is read whole and exactly: one past UInt64's largest is refused, not read as the largest (step 43)."

# expect MO0217: 18446744073709551616 does not fit in UInt64
fn largest() : UInt64
  18446744073709551616
end
