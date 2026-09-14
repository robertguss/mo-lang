module Stdlib.Json
expose Level, Hit, Report, field_text

intent "Write any value as JSON text, and read JSON text back as a Json value to take apart with case, its whole numbers as Int64."

enum Level
  Quiet
  Loud(volume: UInt8)
end

struct Hit
  path: String
  ms: UInt64
  level: Level
end

struct Report
  total: UInt64
  rate: Float64
  hits: List(Hit)
  by_method: Map(String, UInt64)
  since: Option(Time)
end

fn field_text(json: Json, name: String) : Option(String)
  if json is Object(fields)
    if fields.get(name) is Some(String(text))
      return Some(text)
    end
  end
  None
end

test "a struct is an object in field order, and an enum value names its variant"
  hit = Hit(path: "/a\"b", ms: 12, level: Loud(volume: 3))
  assert Json.encode(hit) == "{\"path\": \"/a\\\"b\", \"ms\": 12, \"level\": {\"Loud\": {\"volume\": 3}}}"
  assert Json.encode(Quiet) == "\"Quiet\""
end

test "lists, maps, options, floats, and times each have one spelling"
  counts = Map.new().set("GET", 7).set("POST", 4)
  report = Report(total: 11, rate: 0.5, hits: [], by_method: counts, since: None)
  assert Json.encode(report) == "{\"total\": 11, \"rate\": 0.5, \"hits\": [], \"by_method\": {\"GET\": 7, \"POST\": 4}, \"since\": null}"
  assert Json.encode(3.0) == "3.0"
  assert Json.encode(Some(Time.from_parts(2026, 9, 12, 10, 0, 2))) == "\"2026-09-12T10:00:02Z\""
  assert Json.encode(Map.new().set(1, true)) == "[[1, true]]"
  assert Json.encode([(1, "a")]) == "[[1, \"a\"]]"
end

test "decoded text is a Json value to take apart, and encodes back as it was"
  text = "{\"path\": \"/a\", \"ms\": 12.5, \"tags\": [true, null]}"
  assert Json.decode(text) is Ok(json)
  assert field_text(json, "path") is Some("/a")
  assert field_text(json, "ms") is None
  assert Json.encode(json) == text
  assert Json.decode(" [1, 2e2, -0.5] ") == Ok(Array(items: [Number(value: 1.0),
    Number(value: 200.0),
    Number(value: 0.0 - 0.5)]))
  assert Json.decode("\"caf\\u00e9\"") == Ok(String(text: "café"))
end

test "a decoded number is a whole Int64 below 2^53 either side of 0, and nothing else is"
  assert Json.decode("[3, -42, 1e3, 2.5, 9007199254740991, 9007199254740992, \"7\", null]") is Ok(Array(items))
  wanted = [Some(3), Some(-42), Some(1_000), None, Some(9_007_199_254_740_991), None, None, None]
  assert items.map(fn(item) item.to_i64 end) == wanted
end

test "text that is not JSON names the byte where it stops being JSON"
  assert Json.decode("[1, 2") is Error(Syntax(5))
  assert Json.decode("{\"a\" 1}") is Error(Syntax(5))
  assert Json.decode("[1] x") is Error(Syntax(4))
  assert Json.decode("01") is Error(Syntax(1))
  assert Json.decode("") is Error(Syntax(0))
end

property "any Json value survives encode then decode"
  for json in any(Json)
    assert Json.decode(Json.encode(json)) == Ok(json)
  end
end

verified: types, contracts, tests (6), property (200 seeds), sim (not run)
          proven: not run
