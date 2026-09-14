module Basics.InPlace
expose Tally, Outer, bumped, fields, texts

intent "A field set on a var, and a string grown by interpolation, write in place (step 21), and never reach a copy taken before them."

struct Tally
  count: UInt64
  name: String
end

struct Outer
  inner: Tally
  total: UInt64
end

fn bumped(t: Tally) : Tally
  var u = t
  u.count += 100
  u
end

fn fields() : List(UInt64)
  var a = Tally(count: 0, name: "a")
  a.count += 1
  var b = a
  a.count += 1
  b.count += 10
  c = bumped(a)
  a.count += 1
  var o = Outer(inner: a, total: 0)
  o.inner.count += 5
  kept = o.inner
  o.inner.count += 5
  [a.count, b.count, c.count, o.inner.count, kept.count]
end

fn texts() : List(String)
  var s = "x"
  s = "#{s}y"
  t = s
  s = "#{s}z"
  var u = t
  u = "#{u}w"
  s = "#{s}!"
  var v = s
  s = "#{s}a"
  v = "#{v}b"
  [s, t, u, v]
end

test "a field set never reaches a copy taken before it"
  assert fields() == [3, 11, 102, 13, 8]
end

test "a string grown in place never changes a copy taken before it"
  assert texts() == ["xyz!a", "xy", "xyw", "xyz!b"]
end

verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run
