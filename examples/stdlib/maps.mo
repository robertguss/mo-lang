module Stdlib.Maps
expose counted

intent "Count, group, and look up with maps and sets, whose keys keep the order they were first added."

fn counted(words: List(String)) : Map(String, UInt64)
  var counts = Map.new()
  for word in words
    counts = counts.update(word, 0, fn(n) n + 1 end)
  end
  counts
end

test "a map keeps the order its keys were first added"
  counts = counted(["b", "a", "b", "c", "b"])
  assert counts.keys == ["b", "a", "c"]
  assert counts.values == [3, 1, 1]
  assert counts.entries == [("b", 3), ("a", 1), ("c", 1)]
  assert counts.get("b") is Some(3)
  assert counts.get("z") is None
  assert counts.has?("a") and !counts.has?("z")
  assert counts.size == 3
end

test "set keeps a key's place, and a key removed and set again goes last"
  m = Map.new().set("x", 1).set("y", 2).set("x", 10)
  assert m.entries == [("x", 10), ("y", 2)]
  moved = m.remove("x").set("x", 1)
  assert moved.keys == ["y", "x"]
  assert m.remove("absent") == m
end

test "equal maps hold equal entries in the same order"
  assert Map.new().set("a", 1).set("b", 2) == Map.new().set("a", 1).set("b", 2)
  assert Map.new().set("a", 1).set("b", 2) != Map.new().set("b", 2).set("a", 1)
end

test "a set holds each element once, in the order first added"
  s = Set.new().add(3).add(1).add(3).add(2)
  assert s.to_list == [3, 1, 2]
  assert s.size == 3
  assert s.has?(1) and !s.has?(4)
  assert s.remove(1).to_list == [3, 2]
end

test "group_by gathers elements under their key, keys in the order first seen"
  groups = ["apple", "bean", "avocado", "beet", "corn"].group_by(fn(w) w.slice(0, 1) end)
  assert groups.keys == ["a", "b", "c"]
  assert groups.get("b") == Some(["bean", "beet"])
end

test "a var updated in place never changes a copy taken before"
  var m = Map.new().set("a", 1)
  before = m
  m = m.set("a", 2)
  m = m.set("b", 3)
  kept = m
  m = m.update("a", 0, fn(n) n * 10 end)
  m = m.remove("b")
  var s = Set.new().add("x")
  first = s
  s = s.add("y")
  s = s.remove("x")
  assert before.entries == [("a", 1)]
  assert kept.entries == [("a", 2), ("b", 3)]
  assert m.entries == [("a", 20)]
  assert first.to_list == ["x"]
  assert s.to_list == ["y"]
end

property "a map's keys never repeat, and its size counts them"
  for m in any(Map(String, UInt64))
    assert m.keys.unique == m.keys
    assert m.size == m.keys.size
  end
end

verified: types, contracts, tests (7), property (200 seeds), sim (not run)
          proven: not run
