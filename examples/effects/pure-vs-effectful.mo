module Effects.PureVsEffectful
expose Summed, total, total_logged

intent "The same sum, once pure and once with an Events capability."

struct Summed
  n: UInt32
end

fn total(xs: List(UInt32)) : UInt32
  xs.reduce(0, fn(acc, x) acc + x end)
end

fn total_logged(xs: List(UInt32), events: Events) : UInt32
  n = total(xs)
  events.emit(Summed(n: n), within: 50.ms)
  n
end

test "the pure path needs no capability"
  assert total([1, 2, 3]) == 6
end
