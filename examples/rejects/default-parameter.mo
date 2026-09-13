module Rejects.DefaultParameter
expose greet

intent "Every parameter is passed at every call; a default value on a parameter does not compile."

# expect MO0312: name has a default value; parameters have no defaults, so pass "friend" at the call.
fn greet(name: String = "friend") : String
  "Hello, #{name}!"
end

test "the name given is the name used"
  assert greet("Ada") == "Hello, Ada!"
  assert greet("friend") == "Hello, friend!"
  assert greet("").starts_with?("Hello")
end
