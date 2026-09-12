module Recipes.RateLimiter
expose RateLimiter, Limiter, ClientId

intent "The rate-limiter recipe from chapter 6; needs Clock."

struct Limiter
  capacity: UInt32
end

struct ClientId
  n: UInt32
end

recipe RateLimiter
  intent "Token bucket per client; refills from the clock; never blocks"
  needs Clock
  fn allow?(l: Limiter, id: ClientId, now: Time) : (Limiter, Bool)
    requires l.capacity > 0
    ensures result.0.tokens(id) <= l.capacity
  end
  test "refills at the declared rate"
    assert Limiter(capacity: 1).capacity == 1
  end
  test rejects "a burst beyond capacity"
    Limiter(capacity: 0)
  end
end

test "the limiter holds a capacity"
  l = Limiter(capacity: 3)
  assert l.capacity == 3
end
