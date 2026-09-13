module Rejects.MissingRejectsTest
expose split

intent "Every requires comes with a test rejects that trips it; a requires without one does not compile."
# expect MO0311: split has requires people > 0, but no test rejects trips it.

fn split(total: UInt32, people: UInt32) : UInt32
  requires people > 0

  total / people
end

test "a bill splits evenly"
  assert split(90, 3) == 30
  assert split(0, 3) == 0
end
