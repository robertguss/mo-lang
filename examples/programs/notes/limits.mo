# recipe: Recipes.RateLimiter.RateLimiter
module Notes.Limits
expose ClientId, Bucket, Limiter, limiter, tokens, allow?, retry_after, token?

intent "The rate limiter recipe (examples/recipes/rate-limiter.mo) implemented for notes: one bucket of tokens per client token, filled whole again once a refill period has passed since it was last filled, so a client gets capacity requests in each period; a refused request takes no token."

type ClientId = String

# A client's tokens left, and when the period they belong to began.
struct Bucket
  tokens: UInt32
  since: Time
end

struct Limiter
  capacity: UInt32
  refill: Duration
  buckets: Map(String, Bucket)
end

fn limiter(capacity: UInt32, refill: Duration) : Limiter
  requires capacity > 0

  Limiter(capacity: capacity, refill: refill, buckets: Map.new())
end

# The tokens a client had left after its last request; a client never seen has a full bucket.
fn tokens(l: Limiter, id: ClientId) : UInt32
  case l.buckets.get(id)
    Some(bucket): bucket.tokens
    None: l.capacity
  end
end

# Whether a request from the client may go on now, and the limiter after it: a token taken,
# or, when the bucket is empty, none.
fn allow?(l: Limiter, id: ClientId, now: Time) : (Limiter, Bool)
  ensures result.0.tokens(id) <= l.capacity

  bucket = refilled(l, id, now)
  return (kept(l, id, bucket), false) if bucket.tokens == 0
  (kept(l, id, Bucket(tokens: bucket.tokens - 1, since: bucket.since)), true)
end

# How long a refused client waits for its bucket to fill again; nothing when it has a token.
fn retry_after(l: Limiter, id: ClientId, now: Time) : Duration
  ensures result <= l.refill

  bucket = refilled(l, id, now)
  return 0.ms if bucket.tokens > 0
  l.refill - (now - bucket.since)
end

# A client token: 1 to 64 bytes of ASCII letters, digits, - and _.
fn token?(text: String) : Bool
  return false if text == "" or text.byte_size > 64
  text.bytes.all?(fn(b) token_byte?(b) end)
end

fn token_byte?(b: UInt8) : Bool
  digit = b >= 48 and b <= 57
  letter = (b >= 65 and b <= 90) or (b >= 97 and b <= 122)
  digit or letter or b == 45 or b == 95
end

# The client's bucket as of now: full for a client never seen, or once its period is over.
fn refilled(l: Limiter, id: ClientId, now: Time) : Bucket
  case l.buckets.get(id)
    Some(bucket):
      return Bucket(tokens: l.capacity, since: now) if now - bucket.since >= l.refill
      bucket
    None: Bucket(tokens: l.capacity, since: now)
  end
end

fn kept(l: Limiter, id: ClientId, bucket: Bucket) : Limiter
  var after = l
  after.buckets = l.buckets.set(id, bucket)
  after
end

# The recipe's test rejects, here as well since every requires has one in its own module;
# mo check --recipe holds it to the recipe's, line for line.
test rejects "a limiter with no capacity"
  limiter(0, 1.minute)
end

test "sixty requests pass in a minute, and the sixty-first is refused without taking a token"
  t0 = Time.fixture()
  var l = limiter(60, 1.minute)
  var passed = 0
  for i in 0..61
    step = allow?(l, "ada", t0 + i.ms)
    l = step.0
    if step.1
      passed += 1
    end
  end
  assert passed == 60
  assert tokens(l, "ada") == 0
  assert retry_after(l, "ada", t0 + 100.ms) == 59_900.ms
  assert allow?(l, "ada", t0 + 59_999.ms) is (_, false)
  assert allow?(l, "ada", t0 + 1.minute) is (refilled_one, true)
  assert tokens(refilled_one, "ada") == 59
end

test "each client has a bucket of its own"
  t0 = Time.fixture()
  assert allow?(limiter(1, 1.minute), "ada", t0) is (spent, true)
  assert allow?(spent, "grace", t0) is (_, true)
  assert tokens(spent, "grace") == 1
  assert retry_after(spent, "grace", t0) == 0.ms
end

test "a token is 1 to 64 letters, digits, - and _"
  assert token?("ada")
  assert token?("A-z_09")
  assert token?("k".repeat(64))
  assert !token?("k".repeat(65))
  assert !token?("")
  assert !token?("a b")
  assert !token?("a.b")
  assert !token?("é")
end

property "no run of requests leaves a client more tokens than the capacity"
  for capacity in any(UInt8), n in any(UInt8) if capacity > 0
    var l = limiter(capacity.to_u32, 1.minute)
    for i in 0..n.to_u64
      l = allow?(l, "ada", Time.fixture() + (i * 7_000).ms).0
    end
    assert tokens(l, "ada") <= capacity.to_u32
  end
end

verified: types, contracts, tests (5), property (200 seeds), sim (not run)
          proven: not run
