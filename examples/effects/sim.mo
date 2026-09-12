module Effects.Sim
expose stamp
use Mo.Sim

intent "Tests run against Mo.Sim, swapped in with one use line."

fn stamp(clock: Clock) : Time
  clock.now(within: 10.ms)
end

test "sim clock is deterministic"
  clock = Clock.fixture
  assert stamp(clock, within: 10.ms) == stamp(clock, within: 10.ms)
end
