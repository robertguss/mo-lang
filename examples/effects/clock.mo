module Effects.Clock
expose stamp

intent "A function taking Clock; the call carries within:."

fn stamp(clock: Clock) : Time
  clock.now(within: 10.ms)
end

test "the clock returns a time"
  t = stamp(Clock.fixture, within: 20.ms)
  assert t == t
end
