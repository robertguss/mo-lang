module Rejects.OneLineIfStatement
expose sign

intent "A one-line if is a value only: an if that starts a line is a statement, and a statement takes the block form."

# expect MO0101: expected the if's body on the lines below it: a one-line if is a value, never a statement; as a statement, write the block form, one part a line: if n < 0 / "negative" / else / "not negative" / end
fn sign(n: Int32) : String
  if n < 0: "negative" else: "not negative"
end

test "a negative number is negative"
  assert sign(-1) == "negative"
end
