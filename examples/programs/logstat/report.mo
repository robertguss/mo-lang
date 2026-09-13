module Logstat.Report
expose text, json, grouped, tenths_text, permille_text

intent "Print a summary as the text report or as one JSON object, and never show a card number in either."

# copy of Logstat.Parse
type Status = UInt64 where value >= 100 and value <= 599

# copy of Logstat.Parse
type Millis = UInt64 where value <= 4_294_967_295

# copy of Logstat.Parse
struct Record
  at: String
  seconds: UInt64
  method: String
  path: String
  status: Status
  ms: Millis
end

# copy of Logstat.Stats
struct Count
  method: String
  path: String
  count: UInt64
end

# copy of Logstat.Stats
struct Summary
  requests: UInt64
  errors: UInt64
  successes: UInt64
  malformed: UInt64
  error_permille: UInt64
  per_minute_tenths: UInt64
  slowest: List(Record)
  busiest: List(Count)
end

fn text(summary: Summary) : String
  ensures !shows_card?(result)

  head = joined(head_lines(summary))
  slowest = joined(slowest_lines(summary.slowest))
  busiest = joined(busiest_lines(summary.busiest))
  "#{head}\nslowest\n#{slowest}\nbusiest\n#{busiest}"
end

fn head_lines(summary: Summary) : List(String)
  requests = grouped(summary.requests)
  errors = grouped(summary.errors)
  malformed = grouped(summary.malformed)
  per_minute = tenths_text(summary.per_minute_tenths, "_")
  width = widest([requests, errors, malformed, per_minute])
  error_rate = permille_text(summary.error_permille, 1)
  requests_line = "requests   #{pad_left(requests, width)}"
  errors_line = "errors     #{pad_left(errors, width)}  (#{error_rate}%)"
  malformed_line = "malformed  #{pad_left(malformed, width)}"
  per_minute_line = "per minute #{pad_left(per_minute, width)}"
  [requests_line, errors_line, malformed_line, per_minute_line]
end

fn slowest_lines(slowest: List(Record)) : List(String)
  ms_width = widest(slowest.map(fn(r) grouped(r.ms) end))
  request_width = widest(slowest.map(fn(r) request(r.method, r.path) end))
  slowest.map(fn(r)
    ms = pad_left(grouped(r.ms), ms_width)
    "  #{ms} ms  #{pad_right(request(r.method, r.path), request_width)}   #{r.at}"
  end)
end

fn busiest_lines(busiest: List(Count)) : List(String)
  count_width = widest(busiest.map(fn(c) grouped(c.count) end))
  busiest.map(fn(c)
    "  #{pad_left(grouped(c.count), count_width)}  #{request(c.method, c.path)}"
  end)
end

fn json(summary: Summary) : String
  ensures !shows_card?(result)

  error_rate = permille_text(summary.error_permille, 3)
  per_minute = tenths_text(summary.per_minute_tenths, "")
  slowest = listed(summary.slowest.map(fn(r) slow_json(r) end))
  busiest = listed(summary.busiest.map(fn(c) busy_json(c) end))
  counts = "\"requests\": #{summary.requests}, \"errors\": #{summary.errors}"
  rates = "\"error_rate\": #{error_rate}, \"malformed\": #{summary.malformed}, \"per_minute\": #{per_minute}"
  "{#{counts}, #{rates}, \"slowest\": [#{slowest}], \"busiest\": [#{busiest}]}\n"
end

fn slow_json(r: Record) : String
  "{\"ms\": #{r.ms}, \"method\": \"#{r.method}\", \"path\": \"#{r.path}\", \"at\": \"#{r.at}\"}"
end

fn busy_json(c: Count) : String
  "{\"count\": #{c.count}, \"method\": \"#{c.method}\", \"path\": \"#{c.path}\"}"
end

fn request(method: String, path: String) : String
  "#{method} #{path}"
end

# 1204 is "1_204": Mo's own thousands separator.
fn grouped(n: UInt64) : String
  return "#{n}" if n < 1_000
  "#{grouped(n / 1_000)}_#{three_digits(n % 1_000)}"
end

fn three_digits(n: UInt64) : String
  requires n < 1_000

  return "00#{n}" if n < 10
  return "0#{n}" if n < 100
  "#{n}"
end

# 401 tenths is "40.1"; the whole part takes the separator given, "_" or none.
fn tenths_text(tenths: UInt64, separator: String) : String
  whole = if separator == ""
    "#{tenths / 10}"
  else
    grouped(tenths / 10)
  end
  "#{whole}.#{tenths % 10}"
end

# 31 permille is "3.1" as a percent (one decimal) or "0.031" as a rate (three).
fn permille_text(permille: UInt64, decimals: UInt64) : String
  requires decimals == 1 or decimals == 3

  return "#{permille / 10}.#{permille % 10}" if decimals == 1
  "#{permille / 1_000}.#{three_digits(permille % 1_000)}"
end

fn pad_left(s: String, width: UInt64) : String
  requires s.size <= width

  "#{spaces(width - s.size)}#{s}"
end

fn pad_right(s: String, width: UInt64) : String
  requires s.size <= width

  "#{s}#{spaces(width - s.size)}"
end

fn spaces(n: UInt64) : String
  return "" if n == 0
  " #{spaces(n - 1)}"
end

fn widest(texts: List(String)) : UInt64
  texts.reduce(0, fn(width, t)
    if t.size > width
      t.size
    else
      width
    end
  end)
end

fn joined(lines: List(String)) : String
  lines.reduce("", fn(all, line) "#{all}#{line}\n" end)
end

fn listed(items: List(String)) : String
  items.reduce("", fn(all, item)
    if all == ""
      item
    else
      "#{all}, #{item}"
    end
  end)
end

# Sixteen digits in a row anywhere in the output.
fn shows_card?(output: String) : Bool
  runs = output.bytes.reduce((0, 0), fn(acc, b)
    if b >= 48 and b <= 57
      (acc.0 + 1, larger(acc.0 + 1, acc.1))
    else
      (0, acc.1)
    end
  end)
  runs.1 >= 16
end

fn larger(a: UInt64, b: UInt64) : UInt64
  return a if a > b
  b
end

fn example_summary() : Summary
  slowest = [Record(at: "2026-09-12T10:00:21Z", seconds: 21, method: "POST", path: "/api/orders",
    status: 503, ms: 1_204), Record(at: "2026-09-12T10:00:02Z", seconds: 2, method: "GET",
    path: "/api/users", status: 200, ms: 340)]
  busiest = [Count(method: "GET", path: "/api/users", count: 611), Count(method: "GET",
    path: "/api/cards/****************/charge", count: 2)]
  Summary(requests: 1_204, errors: 37, successes: 1_167, malformed: 2, error_permille: 31,
    per_minute_tenths: 401, slowest: slowest, busiest: busiest)
end

test "the counts line up on their right edge"
  lines = head_lines(example_summary())
  assert lines.size == 4
  assert lines.first is Some("requests   1_204")
  assert lines.last is Some("per minute  40.1")
end

test "the slowest section lines up durations and requests"
  lines = slowest_lines(example_summary().slowest)
  assert lines.first is Some("  1_204 ms  POST /api/orders   2026-09-12T10:00:21Z")
  assert lines.last is Some("    340 ms  GET /api/users     2026-09-12T10:00:02Z")
end

test "the busiest section lines up counts, and a card number is already starred"
  lines = busiest_lines(example_summary().busiest)
  assert lines.first is Some("  611  GET /api/users")
  assert lines.last is Some("    2  GET /api/cards/****************/charge")
end

test "the text report is the three sections with a blank line between"
  expected = """
  requests   1_204
  errors        37  (3.1%)
  malformed      2
  per minute  40.1

  slowest
    1_204 ms  POST /api/orders   2026-09-12T10:00:21Z
      340 ms  GET /api/users     2026-09-12T10:00:02Z

  busiest
    611  GET /api/users
      2  GET /api/cards/****************/charge
  """
  assert text(example_summary()) == "#{expected}\n"
end

test "the JSON form is one object on one line"
  one = Summary(requests: 1, errors: 0, successes: 1, malformed: 3, error_permille: 0,
    per_minute_tenths: 0, slowest: [Record(at: "2026-09-12T10:00:01Z", seconds: 1, method: "GET",
    path: "/a", status: 200, ms: 12)], busiest: [Count(method: "GET", path: "/a", count: 1)])
  expected = "{\"requests\": 1, \"errors\": 0, \"error_rate\": 0.000, \"malformed\": 3, \"per_minute\": 0.0, \"slowest\": [{\"ms\": 12, \"method\": \"GET\", \"path\": \"/a\", \"at\": \"2026-09-12T10:00:01Z\"}], \"busiest\": [{\"count\": 1, \"method\": \"GET\", \"path\": \"/a\"}]}\n"
  assert json(one) == expected
end

test "numbers group by thousands and rates keep their decimals"
  assert grouped(0) == "0"
  assert grouped(1_000) == "1_000"
  assert grouped(1_234_005) == "1_234_005"
  assert tenths_text(12_345, "_") == "1_234.5"
  assert tenths_text(12_345, "") == "1234.5"
  assert permille_text(31, 3) == "0.031"
  assert permille_text(1_000, 1) == "100.0"
end

test rejects "three digits of a thousand"
  three_digits(1_000)
end

test rejects "a rate with two decimals"
  permille_text(31, 2)
end

test rejects "text wider than its column, padded on the left"
  pad_left("toolong", 3)
end

test rejects "text wider than its column, padded on the right"
  pad_right("toolong", 3)
end
