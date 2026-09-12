module Rejects.MissingWithin
expose Tick, ping

intent "Every effectful call must pass within:."
# expect error: effectful emit is missing within:

struct Tick
  n: UInt32
end

fn ping(events: Events) : UInt32
  events.emit(Tick(n: 1))
  1
end

test "never reached"
  assert ping(Events.fixture) == 1
end
