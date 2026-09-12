module Effects.PureVsEffectful
expose label, current
intent "Keep label formatting pure and obtain the clock input explicitly."

fn label(text: String) : String
  "at #{text}"
end

fn current(clock: Clock) : String
  now = clock.now(within: 200.ms)
  label("#{now}")
end

test "the shared formatting computation needs no capability"
  assert label("noon") == "at noon"
  assert label("midnight") == "at midnight"
end
