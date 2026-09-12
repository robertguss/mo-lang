module Effects.Clock
expose read, budget
intent "Pass Clock explicitly and bound its now call with within."

fn budget() : UInt32
  200
end

fn read(clock: Clock) : Time
  clock.now(within: budget().ms)
end

test "the read budget is positive and below a minute"
  assert budget() > 0
  assert budget().ms < 1.minute
end
