module Logstat.Report
expose Shown, Slow, Hot, shown, text, json, masked, card?, grouped, decimal

use Logstat.Stats{Summary, busiest, empty, error_rate, folded, per_minute}

intent "Turn a summary into the text report or one JSON object; every run of 16 or more digits in a path is printed as that many `*`, so a card number never reaches the output."

never "a card number reaches a slowest row"
  for s in Slow.all
    card?(s.path)
  end
end

never "a card number reaches a busiest row"
  for h in Hot.all
    card?(h.path)
  end
end

struct Slow
  ms: UInt32
  method: String
  path: String
  at: String
end

struct Hot
  count: UInt64
  method: String
  path: String
end

# What is printed, whichever form: the rates rounded, the paths masked.
struct Shown
  requests: UInt64
  errors: UInt64
  malformed: UInt64
  error_rate: Float64
  percent: Float64
  per_minute: Float64
  slowest: List(Slow)
  busiest: List(Hot)
end

fn shown(summary: Summary) : Shown
  rate = error_rate(summary)
  Shown(requests: summary.requests, errors: summary.errors, malformed: summary.malformed,
    error_rate: rate.round(3), percent: (rate * 100.0).round(1),
    per_minute: per_minute(summary).round(1), slowest: summary.slowest.map(fn(r)
    Slow(ms: r.ms, method: r.method, path: masked(r.path), at: r.at.to_iso8601)
  end), busiest: busiest(summary).map(fn(b)
    Hot(count: b.count, method: b.method, path: masked(b.path))
  end))
end

fn text(shown: Shown) : String
  requests = grouped(shown.requests)
  errors = grouped(shown.errors)
  malformed = grouped(shown.malformed)
  per_minute = decimal(shown.per_minute, 1)
  width = [requests, errors, malformed, per_minute].map(fn(v) v.size end).max or 0
  counts = [row("requests", requests, width),
    "#{row("errors", errors, width)}  (#{decimal(shown.percent, 1)}%)",
    row("malformed", malformed, width),
    row("per minute", per_minute, width)]
  lines = counts.concat([""]).concat(slow_lines(shown.slowest)).concat([""]).concat(hot_lines(shown.busiest))
  "#{String.join(lines, "\n")}\n"
end

fn row(label: String, value: String, width: UInt64) : String
  "#{label.pad_right(11, " ")}#{value.pad_left(width, " ")}"
end

fn slow_lines(rows: List(Slow)) : List(String)
  ms_width = rows.map(fn(r) grouped(r.ms.to_u64).size end).max or 0
  method_width = rows.map(fn(r) r.method.size end).max or 0
  path_width = rows.map(fn(r) r.path.size end).max or 0
  ["slowest"].concat(rows.map(fn(r)
    "  #{grouped(r.ms.to_u64).pad_left(ms_width, " ")} ms  #{r.method.pad_right(method_width, " ")} #{r.path.pad_right(path_width, " ")}  #{r.at}"
  end))
end

fn hot_lines(rows: List(Hot)) : List(String)
  count_width = rows.map(fn(h) grouped(h.count).size end).max or 0
  method_width = rows.map(fn(h) h.method.size end).max or 0
  ["busiest"].concat(rows.map(fn(h)
    "  #{grouped(h.count).pad_left(count_width, " ")}  #{h.method.pad_right(method_width, " ")} #{h.path}"
  end))
end

fn json(shown: Shown) : String
  slowest = shown.slowest.map(fn(r)
    "{\"ms\": #{r.ms}, \"method\": #{Json.encode(r.method)}, \"path\": #{Json.encode(r.path)}, \"at\": #{Json.encode(r.at)}}"
  end)
  busiest = shown.busiest.map(fn(h)
    "{\"count\": #{h.count}, \"method\": #{Json.encode(h.method)}, \"path\": #{Json.encode(h.path)}}"
  end)
  counts = "\"requests\": #{shown.requests}, \"errors\": #{shown.errors}, \"error_rate\": #{shown.error_rate.to_string(3)}, \"malformed\": #{shown.malformed}, \"per_minute\": #{shown.per_minute.to_string(1)}"
  "{#{counts}, \"slowest\": [#{String.join(slowest, ", ")}], \"busiest\": [#{String.join(busiest, ", ")}]}\n"
end

# A whole number with `_` between each three digits from the right, as Mo writes numbers.
fn grouped(n: UInt64) : String
  digits = "#{n}"
  size = digits.byte_size
  digits.chars.enumerate.reduce("",
    fn(so_far,
    e) if e.0 > 0 and (size - e.0) % 3 == 0: "#{so_far}_#{e.1}" else: "#{so_far}#{e.1}" end)
end

# A number that is not negative with `places` decimals, its whole part grouped.
fn decimal(x: Float64, places: UInt64) : String
  requires places <= 15

  spelled = x.to_string(places)
  parts = spelled.split(".")
  case (parts.first or "").to_u64
    Some(whole): if parts.size == 2: "#{grouped(whole)}.#{parts.last or ""}" else: grouped(whole)
    None: spelled
  end
end

# The path with every run of 16 or more ASCII digits printed as that many `*`.
fn masked(path: String) : String
  ensures !card?(result)

  return path if !card?(path)
  ended = path.chars.reduce(("", ""),
    fn(acc,
    ch) if digit?(ch): (acc.0, "#{acc.1}#{ch}") else: ("#{acc.0}#{hidden(acc.1)}#{ch}", "") end)
  "#{ended.0}#{hidden(ended.1)}"
end

fn hidden(run: String) : String
  if run.byte_size >= 16: "*".repeat(run.byte_size) else: run
end

fn digit?(ch: String) : Bool
  ch.byte_size == 1 and ch >= "0" and ch <= "9"
end

# Whether the text holds a run of 16 or more ASCII digits.
fn card?(text: String) : Bool
  longest = text.bytes.reduce((0, 0),
    fn(acc, b) if b >= 48 and b <= 57: (acc.0 + 1, max_of(acc.1, acc.0 + 1)) else: (0, acc.1) end)
  longest.1 >= 16
end

fn summary_of(lines: List(String), top: UInt64) : Summary
  lines.reduce(empty(top, None), fn(s, line) folded(s, line) end)
end

fn sample() : List(String)
  ["2026-09-12T10:00:01Z GET /api/users 200 12",
    "2026-09-12T10:00:02Z POST /api/orders 500 340",
    "2026-09-12T10:01:01Z GET /pay/4242424242424242/receipt 200 1204",
    "junk"]
end

test "the counts section: requests, errors with their rate, malformed, per minute"
  lines = text(shown(summary_of(sample(), 5))).lines
  assert lines.take(4) == ["requests     3",
    "errors       1  (33.3%)",
    "malformed    1",
    "per minute 3.0"]
end

test "the slowest section: duration, method, path, and time in columns"
  lines = text(shown(summary_of(sample(), 5))).lines
  assert lines.slice(4, 9) == ["",
    "slowest",
    "  1_204 ms  GET  /pay/****************/receipt  2026-09-12T10:01:01Z",
    "    340 ms  POST /api/orders                    2026-09-12T10:00:02Z",
    "     12 ms  GET  /api/users                     2026-09-12T10:00:01Z"]
end

test "the busiest section: count, method, and path, the report ending in one newline"
  report = text(shown(summary_of(sample(), 5)))
  assert report.lines.drop(9) == ["",
    "busiest",
    "  1  POST /api/orders",
    "  1  GET  /api/users",
    "  1  GET  /pay/****************/receipt"]
  assert report.ends_with?("t\n")
end

test "a summary of nothing prints its zeros and empty sections"
  assert text(shown(summary_of([],
    5))) == "requests     0\nerrors       0  (0.0%)\nmalformed    0\nper minute 0.0\n\nslowest\n\nbusiest\n"
  assert json(shown(summary_of([],
    5))) == "{\"requests\": 0, \"errors\": 0, \"error_rate\": 0.000, \"malformed\": 0, \"per_minute\": 0.0, \"slowest\": [], \"busiest\": []}\n"
end

test "the JSON form is one object on one line"
  assert json(shown(summary_of(sample(),
    1))) == "{\"requests\": 3, \"errors\": 1, \"error_rate\": 0.333, \"malformed\": 1, \"per_minute\": 3.0, \"slowest\": [{\"ms\": 1204, \"method\": \"GET\", \"path\": \"/pay/****************/receipt\", \"at\": \"2026-09-12T10:01:01Z\"}], \"busiest\": [{\"count\": 1, \"method\": \"POST\", \"path\": \"/api/orders\"}]}\n"
end

test "a card number in a path is printed as stars, and a shorter run of digits is kept"
  assert masked("/pay/4242424242424242/receipt") == "/pay/****************/receipt"
  assert masked("/a/12345678901234567") == "/a/*****************"
  assert masked("/users/123456789012345") == "/users/123456789012345"
  assert masked("/x/4242424242424242-4242424242424242") == "/x/****************-****************"
  assert !text(shown(summary_of(sample(), 5))).contains?("4242")
  assert !json(shown(summary_of(sample(), 5))).contains?("4242")
end

test "numbers use _ between thousands, as Mo writes them"
  assert grouped(0) == "0"
  assert grouped(999) == "999"
  assert grouped(1_204) == "1_204"
  assert grouped(1_234_567) == "1_234_567"
  assert decimal(40.06, 1) == "40.1"
  assert decimal(12_345.25, 2) == "12_345.25"
  assert decimal(7.0, 0) == "7"
end

test rejects "a decimal with more places than a float holds"
  decimal(1.5, 16)
end

property "a masked path holds no card number and keeps its length"
  for prefix in any(String), run in any(UInt8)
    path = "#{prefix}/#{"4".repeat(run.to_u64)}/x"
    assert !card?(masked(path))
    assert masked(path).size == path.size
  end
end

verified: types, contracts, tests (9), property (200 seeds), sim (not run)
          proven: not run
