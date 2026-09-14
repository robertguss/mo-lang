module Rejects.OneLineIfStatement
expose sign

intent "A one-line if is a value only: on a line of its own that is not a body's last, its value is dropped, and a statement takes the block form."

# expect MO0310: the String from if n < 0: "negative" else: "not negative" is dropped; a one-line if is a value, never a statement: bind it and use it, or, where a statement goes, write the block form, one part a line: if n < 0 / "negative" / else / "not negative" / end
fn sign(n: Int32) : String
  if n < 0: "negative" else: "not negative"
  "#{n}"
end

test "a negative number is negative"
  assert sign(-1) == "negative"
end
