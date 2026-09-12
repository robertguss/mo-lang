module Effects.Timeout
expose WorkError, tick, run

intent "Timeout is an ordinary error variant the caller must handle."

enum WorkError
  Timeout
end

fn tick(clock: Clock) : Result(Time, WorkError)
  Ok(clock.now(within: 50.ms))
end

fn run(clock: Clock) : Time
  case tick(clock)
    Ok(t): t
    Error(Timeout): clock.now(within: 50.ms)
  end
end

test "the Timeout arm is present"
  t = run(Clock.fixture, within: 50.ms)
  assert t == t
end
