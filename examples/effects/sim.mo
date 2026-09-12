module Effects.Sim
expose StampError, Stamp, stamp

use Mo.Sim

intent "Run effectful code in a test against the deterministic simulator, swapped in with one use line."

enum StampError
  Timeout
end

struct Stamp
  note: String
  at: Time
end

fn stamp(clock: Clock, note: String) : Result(Stamp, StampError)
  now = try clock.now(within: 10.ms)
  Ok(Stamp(note: note, at: now))
end

test "the simulated clock stamps the same note the same way twice"
  clock = Clock.fixture()
  assert stamp(clock, "hello") == stamp(clock, "hello")
end
