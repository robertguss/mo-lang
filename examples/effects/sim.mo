module Effects.Sim
expose Stamp, stamp

intent "mo test always runs on the deterministic simulator, so effectful code gives the same answer every time."

struct Stamp
  note: String
  at: Time
end

fn stamp(clock: Clock, note: String) : Stamp
  Stamp(note: note, at: clock.now)
end

test "the simulated clock stamps the same note the same way twice"
  clock = Clock.fixture()
  assert stamp(clock, "hello") == stamp(clock, "hello")
end
