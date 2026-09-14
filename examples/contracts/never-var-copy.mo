module Contracts.NeverVarCopy
expose Pair, both, first_only

intent "A never reads values at rest: a var copy changed one field at a time is read once its last field is set, and a copy returned half changed still trips it."

never "a pair's halves differ"
  for p in Pair.all
    p.a != p.b
  end
end

struct Pair
  a: UInt64
  b: UInt64
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

test "both halves move together"
  assert both(Pair(a: 1, b: 1)) == Pair(a: 2, b: 2)
end

test rejects "a pair returned with one half moved trips the never"
  pair = first_only(Pair(a: 1, b: 1))
  assert pair.b == 1
end

verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run
