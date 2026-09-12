module Basics.AnonymousFunctions
expose scaled, positives

intent "Anonymous functions are one-line or block form, and only as call arguments."

fn scaled(xs: List(UInt32)) : List(UInt32)
  xs.map(fn(x) x + 1 end)
end

fn positives(xs: List(UInt32)) : List(UInt32)
  xs.filter(fn(x)
    x > 0
  end)
end

test "one-line and block callbacks"
  assert scaled([1]).size == 1
  assert positives([0, 2]).size == 1
end
