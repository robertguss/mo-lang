module Rejects.DefaultParameter
expose greet

intent "No default parameters."
# expect error: default parameters are a compile error

fn greet(name: String = "Mo") : String
  name
end

test "never reached"
  assert greet("Mo") == "Mo"
end
