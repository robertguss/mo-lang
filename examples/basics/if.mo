module Basics.If
expose sign, abs, positive

intent "if as a statement, as an expression, and trailing if on return."

fn sign(n: Int32) : Int32
  var s = 0
  if n > 0
    s = 1
  end
  s
end

fn abs(n: Int32) : Int32
  x = if n < 0
    -n
  else
    n
  end
  x
end

fn positive(n: Int32) : Int32
  return n if n > 0
  0
end

test "all three if forms"
  assert sign(2) == 1
  assert abs(-3) == 3
  assert positive(4) == 4
  assert positive(0) == 0
end
