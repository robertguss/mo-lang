# logstat: toolchain bugs

What writing `logstat` (program 2, round 7 of the control run) found in the toolchain. Each is worked around in the program, never fixed in `toolchain/`.

## 1. A `never` reads a `var` copy between two writes when the second sits inside an `if`

Step 27 says a `never` reads values at rest: "a field write followed by another write of the same `var` records nothing". That holds for two writes in a row, but not when the second write is inside an `if` (either branch): the value after the first write is recorded, and a `never` over it trips.

```
module Pair
expose Pair, bumped, plain

never "a pair's halves differ"
  for p in Pair.all
    p.a != p.b
  end
end

struct Pair
  a: UInt64
  b: UInt64
end

fn plain(p: Pair) : Pair
  var next = p
  next.a += 1
  next.b += 1
  next
end

fn bumped(p: Pair, up: Bool) : Pair
  var next = p
  next.a += 1
  if up
    next.b += 1
  else
    next.b += 1
  end
  next
end

test "two writes in a row"
  assert plain(Pair(a: 0, b: 0)) == Pair(a: 1, b: 1)
end

test "a write, then a write inside an if"
  assert bumped(Pair(a: 0, b: 0), true) == Pair(a: 1, b: 1)
end
```

`mo test pair.mo`:

```
pass  test "two writes in a row"
FAIL  test "a write, then a write inside an if": pair.mo:4:1: never "a pair's halves differ" tripped; p = Pair(a: 1, b: 0)
```

Found by `Logstat.Stats.added`, which counted a record as `next.requests += 1` and then `next.errors += 1` or `next.successes += 1` in an `if`; the never "a summary's requests are not its errors plus its successes" tripped in every test. Workaround: the branch moves into the value, `next.errors += if error: 1 else: 0` and `next.successes += if error: 0 else: 1`, three writes in a row.
