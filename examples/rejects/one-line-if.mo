module Rejects.OneLineIf
expose sign

intent "An if has no one-line form, as a statement or as a value; the block form is the only one."

# expect MO0101: expected the if's body on the lines below it: an if has no one-line form, as a statement or as a value; write the block form, one part a line: if n < 0 / "negative" / else / "not negative" / end
fn sign(n: Int32) : String
  if n < 0: "negative" else: "not negative"
end

test "a negative number is negative"
  assert sign(-1) == "negative"
end
