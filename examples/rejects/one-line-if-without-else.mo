module Rejects.OneLineIfWithoutElse
expose label

intent "A one-line if is a value, so it takes both branches: else: is required."

# expect MO0101: expected `else:` after the value: a one-line if is a value, so it takes both branches: if n > 1: "lines" else: <the value otherwise>
fn label(n: UInt64) : String
  word = if n > 1: "lines"
  "#{n} #{word}"
end

test "one line is a line"
  assert label(1) == "1 line"
end
