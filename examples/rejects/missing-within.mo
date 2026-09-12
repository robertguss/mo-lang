module Rejects.MissingWithin
expose read, budget
intent "Even a clock read must carry an explicit deadline."
# expect error: The effectful clock.now call omits within.

fn budget() : UInt32
  200
end

fn read(clock: Clock) : Time
  clock.now
end

test "a budget declaration is not a deadline on the call"
  assert budget().ms < 1.minute
end
