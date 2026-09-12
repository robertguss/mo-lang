module Recipes.RateLimiter
expose Limiter, ClientId, tokens, RateLimiter
intent "Specify a per-client token bucket that refills from the clock."
type ClientId = UInt32
struct Limiter
  client: ClientId
  capacity: UInt32
  available: UInt32
  at: Time
end
fn tokens(l: Limiter, id: ClientId) : UInt32
  if id == l.client
    l.available
  else
    0
  end
end
recipe RateLimiter
  intent "Token bucket per client; refills from the clock; never blocks"
  needs Clock
  fn allow?(l: Limiter, id: ClientId, now: Time) : (Limiter, Bool)
    ensures result.0.tokens(id) <= l.capacity
  end
  test "an empty bucket refills to capacity after a minute"
    l = Limiter.fixture(client: 1, capacity: 2, available: 0)
    reply = allow?(l, 1, l.at + 1.minute)
    assert reply.1
    assert reply.0.tokens(1) == 1
  end
  test "a burst against an empty bucket is denied"
    l = Limiter.fixture(client: 1, capacity: 2, available: 0)
    assert !allow?(l, 1, l.at).1
  end
end

test "tokens belong to the matching client"
  l = Limiter.fixture(client: 1, capacity: 2, available: 2)
  assert tokens(l, 1) == 2
  assert tokens(l, 2) == 0
end
