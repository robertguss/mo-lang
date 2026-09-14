module Rejects.MethodOnRangeEnd
expose doubled

intent "A call binds tighter than `..`, so a method written after a range's end is called on the end, not on the range."

# expect MO0206: expected the range, found `.map` called on 60: a call binds tighter than `..`; write (0..60).map(...)
fn doubled() : List(UInt64)
  0..60.map(fn(i) i * 2 end)
end

test "sixty doubled numbers"
  assert doubled().size == 60
end
