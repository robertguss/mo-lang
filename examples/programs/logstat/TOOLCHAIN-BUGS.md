# logstat: what the toolchain did that surprised the program

Round 6 of the control run. Each entry has a minimal reproduction; none is fixed here.

## 1. A `never` over `T.all` reads a `var` copy while it is changed field by field

Chapter 4's one way to change a struct is `var copy = x` then `copy.field = v`. A `never` that relates two fields of the struct reads every value of the type a run held, and that includes the copy between its two assignments, so a change that keeps the rule at every `return` still trips it. Found in `Logstat.Stats.added`, which counted a request and then its error or success: the never "a summary counts more errors than requests, or its requests are not its errors and successes" tripped on `requests: 1, errors: 0, successes: 0`.

```ruby
module Pair
expose Pair, both

intent "A never over a struct, and the struct changed through a var copy field by field."

never "a pair's halves differ"
  for p in Pair.all
    p.a != p.b
  end
end

struct Pair
  a: UInt64
  b: UInt64
end

fn both(p: Pair) : Pair
  var next = p
  next.a += 1
  next.b += 1
  next
end

test "both halves move together"
  assert both(Pair(a: 1, b: 1)) == Pair(a: 2, b: 2)
end
```

`mo test pair.mo`: `FAIL ... never "a pair's halves differ" tripped; p = Pair(a: 2, b: 1)`.

Whether this is a bug or the rule is not said anywhere the program could read: design-v0/04 says a `never` is checked "over the values the run held", and a half-changed copy is one. Workaround: `added` builds the next `Summary` in one construction. A reader should know that a `never` over a struct forbids changing that struct field by field in any function a test reaches.
