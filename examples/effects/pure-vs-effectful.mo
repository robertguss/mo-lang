module Effects.PureVsEffectful
expose AgeError, age_at, age_now

intent "Keep the arithmetic pure, and let a thin function that takes a Clock supply the time."

enum AgeError
  Timeout
end

fn age_at(born: Time, now: Time) : Duration
  now - born
end

fn age_now(clock: Clock, born: Time) : Result(Duration, AgeError)
  now = try clock.now(within: 10.ms)
  Ok(age_at(born, now))
end

test "the pure version needs only values"
  born = Time.fixture()
  assert age_at(born, born + 1.minute) == 1.minute
end

test "the effectful version reads the clock first"
  clock = Clock.fixture()
  assert clock.now(within: 10.ms) is Ok(born)
  assert age_now(clock, born) is Ok(age)
  assert age == 0.ms
end
