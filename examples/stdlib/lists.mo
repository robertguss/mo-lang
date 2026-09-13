module Stdlib.Lists
expose Request, slowest

intent "Cut, order, and fold lists with the list rows: a stable sort by a key, folds that stop early, and pairs by position."

struct Request
  path: String
  ms: UInt64
end

# Slowest first; requests that took as long keep the order they came in.
fn slowest(requests: List(Request), n: UInt64) : List(Request)
  requests.sort_by(fn(r) 18_446_744_073_709_551_615 - r.ms end).take(n)
end

test "get, slice, take, and drop clamp instead of crashing"
  xs = [10, 20, 30, 40]
  assert xs.get(1) is Some(20)
  assert xs.get(4) is None
  assert xs.slice(1, 3) == [20, 30]
  assert xs.slice(3, 99) == [40]
  assert xs.take(2) == [10, 20]
  assert xs.drop(3) == [40]
  assert xs.drop(9).size == 0
  assert xs.concat([50]).reverse == [50, 40, 30, 20, 10]
end

test "sort is stable, and orders strings by byte and tuples left to right"
  assert [3, 1, 2].sort == [1, 2, 3]
  assert ["b", "a", "B"].sort == ["B", "a", "b"]
  assert [(2, "x"), (1, "z"), (1, "y")].sort == [(1, "y"), (1, "z"), (2, "x")]
  requests = [Request(path: "/a", ms: 5), Request(path: "/b", ms: 9), Request(path: "/c", ms: 5)]
  assert requests.sort_by(fn(r) r.ms end).map(fn(r) r.path end) == ["/a", "/c", "/b"]
  assert slowest(requests, 2).map(fn(r) r.path end) == ["/b", "/a"]
end

test "folds that stop early, and folds that count"
  xs = [4, 8, 15, 16, 23, 42]
  assert xs.any?(fn(x) x > 40 end)
  assert !xs.all?(fn(x) x % 2 == 0 end)
  assert xs.find(fn(x) x > 10 end) is Some(15)
  assert xs.count(fn(x) x % 2 == 0 end) == 4
  assert xs.sum == 108
  assert xs.min is Some(4)
  assert xs.max is Some(42)
  assert xs.drop(6).max is None
end

test "zip, enumerate, flat_map, and unique keep order"
  assert [1, 2, 3].zip(["a", "b"]) == [(1, "a"), (2, "b")]
  assert ["x", "y"].enumerate == [(0, "x"), (1, "y")]
  assert [1, 2].flat_map(fn(x) [x, x * 10] end) == [1, 10, 2, 20]
  assert [3, 1, 3, 2, 1].unique == [3, 1, 2]
end

verified: types, contracts, tests (4), property (0 seeds), sim (not run)
          proven: not run
