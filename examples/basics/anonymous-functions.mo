module Basics.AnonymousFunctions
expose scores
intent "Pass one-line and block anonymous functions directly to calls."

fn scores(xs: List(UInt32)) : List(UInt32)
  small = xs.filter(fn(x) x < 10 end)
  small.map(fn(x)
    doubled = x * 2
    doubled + 1
  end)
end

test "both anonymous function forms are call arguments"
  assert scores([1, 2, 10]) == [3, 5]
  assert scores([]) == []
end
