module Contracts.NeverVarCopy
expose Pair, Tally, both, first_only, added, counted

intent "A never reads values at rest: a var copy changed one field at a time is read once its last field is set, looking through the arms of an if between the writes, and a copy returned half changed still trips it."

never "a pair's halves differ"
  for p in Pair.all
    p.a != p.b
  end
end

never "a tally's requests are not its errors plus its successes"
  for t in Tally.all
    t.requests != t.errors + t.successes
  end
end

struct Pair
  a: UInt64
  b: UInt64
end

struct Tally
  requests: UInt64
  errors: UInt64
  successes: UInt64
  seen: UInt64
end

# Both halves move, one field at a time on a var copy.
fn both(p: Pair) : Pair
  var next = p
  next.a += 1
  next.b += 1
  next
end

# Only the first half moves, so the pair it returns is unequal.
fn first_only(p: Pair) : Pair
  var next = p
  next.a += 1
  next
end

# Logstat's shape (round 7): a write, then one in each arm of an if (step 28).
fn added(t: Tally, failed: Bool) : Tally
  var next = t
  next.requests += 1
  if failed
    next.errors += 1
  else
    next.successes += 1
  end
  next
end

# A write, one in the only arm of an if, and the writes after it: read once, at the last.
fn counted(t: Tally, failed: Bool) : Tally
  var next = t
  next.requests += 1
  if failed
    next.seen += 1
  end
  next.successes += if failed: 0 else: 1
  next.errors += if failed: 1 else: 0
  next
end

test "both halves move together"
  assert both(Pair(a: 1, b: 1)) == Pair(a: 2, b: 2)
end

test "a write, then a write in each arm of an if, is read once at its last write"
  start = Tally(requests: 0, errors: 0, successes: 0, seen: 0)
  assert added(added(start, true), false) == Tally(requests: 2, errors: 1, successes: 1, seen: 0)
  assert counted(counted(start, true), false) == Tally(requests: 2, errors: 1, successes: 1,
    seen: 1)
end

test rejects "a pair returned with one half moved trips the never"
  pair = first_only(Pair(a: 1, b: 1))
  assert pair.b == 1
end

verified: types, contracts, tests (3), property (0 seeds), sim (not run)
          proven: not run
