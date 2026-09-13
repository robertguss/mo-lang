module Effects.PureVsEffectful
expose age_at, age_now

intent "Keep the arithmetic pure, and let a thin function that takes a Clock supply the time."

fn age_at(born: Time, now: Time) : Duration
  now - born
end

fn age_now(clock: Clock, born: Time) : Duration
  age_at(born, clock.now)
end

test "the pure version needs only values"
  born = Time.fixture()
  assert age_at(born, born + 1.minute) == 1.minute
end

test "the effectful version reads the clock"
  clock = Clock.fixture()
  assert age_now(clock, clock.now) == 0.ms
end
