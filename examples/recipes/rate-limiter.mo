module Recipes.RateLimiter
expose ClientId, RateLimiter

intent "Publish a rate limiter as intent, signatures, and tests, for an agent to implement locally."

type ClientId = String

recipe RateLimiter
  intent "Token bucket per client; refills from the clock; never blocks"
  needs Clock
  fn limiter(capacity: UInt32, refill: Duration) : Limiter
    requires capacity > 0
  end
  fn tokens(l: Limiter, id: ClientId) : UInt32
  end
  fn allow?(l: Limiter, id: ClientId, now: Time) : (Limiter, Bool)
    ensures result.0.tokens(id) <= l.capacity
  end
  test "a burst beyond capacity is refused"
    t0 = Time.fixture()
    assert allow?(limiter(1, 1.minute), "ada", t0) is (spent, true)
    assert allow?(spent, "ada", t0) is (_, false)
  end
  test "refills at the declared rate"
    t0 = Time.fixture()
    assert allow?(limiter(1, 1.minute), "ada", t0) is (spent, true)
    assert allow?(spent, "ada", t0 + 1.minute) is (_, true)
  end
  test rejects "a limiter with no capacity"
    limiter(0, 1.minute)
  end
end

verified: types, contracts, tests (1), property (0 seeds), sim (not run)
          proven: not run
