module Rejects.CapturedCapability
expose stamped

intent "An anonymous function holds no authority; capturing a capability or a handle does not compile."

# expect MO0409: the anonymous function captures clock, a Clock; pass clock as a parameter to a named function instead.
fn stamped(clock: Clock, names: List(String)) : List(String)
  names.map(fn(name) "#{name} at #{clock.now}" end)
end

test "every name is stamped"
  assert stamped(Clock.fixture(), []) == []
end
