module Logstat.Report
expose text, json, grouped, one_decimal

use Logstat.Parse{Record, card?}
use Logstat.Stats{Count, Summary}

intent "Print a summary as the text report or as one JSON object, and never show a card number in either."

# The JSON object's shape: its keys, in order, are these fields.
struct JsonSummary
  requests: UInt64
  errors: UInt64
  error_rate: Float64
  malformed: UInt64
  per_minute: Float64
  slowest: List(JsonSlow)
  busiest: List(Count)
end

struct JsonSlow
  ms: UInt32
  method: String
  path: String
  at: Time
end

fn text(summary: Summary) : String
  ensures !card?(result)

  head = head_lines(summary).push("").push("slowest")
  slow = head.concat(slowest_lines(summary.slowest)).push("").push("busiest")
  lines_text(slow.concat(busiest_lines(summary.busiest)))
end

# The counts, each right-aligned in the width of the widest, the error line with its rate.
fn head_lines(summary: Summary) : List(String)
  values = [grouped(summary.requests), grouped(summary.errors),
    grouped(summary.malformed), one_decimal(summary.per_minute)]
  labels = ["requests", "errors", "malformed", "per minute"]
  rates = ["", "  (#{one_decimal(summary.error_rate * 100.0)}%)", "", ""]
  label_width = widest(labels)
  value_width = widest(values)
  rows = labels.zip(values).zip(rates)
  rows.map(fn(row) head_line(row, label_width, value_width) end)
end

fn head_line(row: ((String, String), String), label_width: UInt64, value_width: UInt64) : String
  case row
    ((label, value), rate):
      "#{label.pad_right(label_width, " ")} #{value.pad_left(value_width, " ")}#{rate}"
  end
end

fn slowest_lines(slowest: List(Record)) : List(String)
  ms_width = widest(slowest.map(fn(r) grouped(r.ms.to_u64) end))
  request_width = widest(slowest.map(fn(r) requested(r) end))
  slowest.map(fn(r) slow_line(r, ms_width, request_width) end)
end

fn requested(r: Record) : String
  "#{r.method} #{r.path}"
end

fn slow_line(r: Record, ms_width: UInt64, request_width: UInt64) : String
  took = grouped(r.ms.to_u64).pad_left(ms_width, " ")
  "  #{took} ms  #{requested(r).pad_right(request_width, " ")}   #{r.at.to_iso8601}"
end

fn busiest_lines(busiest: List(Count)) : List(String)
  count_width = widest(busiest.map(fn(c) grouped(c.count) end))
  busiest.map(fn(c) busy_line(c, count_width) end)
end

fn busy_line(c: Count, count_width: UInt64) : String
  "  #{grouped(c.count).pad_left(count_width, " ")}  #{c.method} #{c.path}"
end

fn json(summary: Summary) : String
  ensures !card?(result)

  slowest = summary.slowest.map(fn(r) JsonSlow(ms: r.ms, method: r.method, path: r.path,
    at: r.at) end)
  object = JsonSummary(requests: summary.requests, errors: summary.errors,
    error_rate: summary.error_rate, malformed: summary.malformed,
    per_minute: summary.per_minute, slowest: slowest, busiest: summary.busiest)
  "#{Json.encode(object)}\n"
end

# 1204 is "1_204": Mo's own thousands separator.
fn grouped(n: UInt64) : String
  String.grouped(n)
end

# 1234.56 is "1_234.6": one decimal, the whole part grouped.
fn one_decimal(x: Float64) : String
  requires x >= 0.0

  spelled = x.to_string(1)
  point = spelled.index_of(".") or 0
  whole = spelled.slice(0, point).to_u64 or 0
  "#{String.grouped(whole)}#{spelled.slice(point, spelled.size)}"
end

fn widest(texts: List(String)) : UInt64
  texts.map(fn(t) t.size end).max or 0
end

fn lines_text(lines: List(String)) : String
  "#{String.join(lines, "\n")}\n"
end

# The spec's own example report, the fixture of the three section tests below.
fn example_summary() : Summary
  slowest = [Record(at: Time.from_parts(2026, 9, 12, 10, 0, 21), method: "POST",
      path: "/api/orders", status: 503, ms: 1_204),
    Record(at: Time.from_parts(2026, 9, 12, 10, 0, 2), method: "GET",
      path: "/api/users", status: 200, ms: 340)]
  busiest = [Count(count: 611, method: "GET", path: "/api/users"),
    Count(count: 2, method: "GET", path: "/api/cards/****************/charge")]
  Summary(requests: 1_204, errors: 37, successes: 1_167, malformed: 2, error_rate: 0.031,
    per_minute: 40.1, slowest: slowest, busiest: busiest)
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
  at = Time.from_parts(2026, 9, 12, 10, 0, 1)
  one = Summary(requests: 1, errors: 0, successes: 1, malformed: 3, error_rate: 0.0,
    per_minute: 0.0, slowest: [Record(at: at, method: "GET", path: "/a", status: 200, ms: 12)],
    busiest: [Count(count: 1, method: "GET", path: "/a")])
  expected = "{\"requests\": 1, \"errors\": 0, \"error_rate\": 0.0, \"malformed\": 3, \"per_minute\": 0.0, \"slowest\": [{\"ms\": 12, \"method\": \"GET\", \"path\": \"/a\", \"at\": \"2026-09-12T10:00:01Z\"}], \"busiest\": [{\"count\": 1, \"method\": \"GET\", \"path\": \"/a\"}]}\n"
  assert json(one) == expected
end

test "numbers group by thousands and rates keep one decimal"
  assert grouped(0) == "0"
  assert grouped(1_000) == "1_000"
  assert grouped(1_234_005) == "1_234_005"
  assert one_decimal(1234.5) == "1_234.5"
  assert one_decimal(40.06) == "40.1"
end

test rejects "a negative rate has no decimal text"
  one_decimal(0.0 - 1.0)
end

verified: types, contracts, tests (7), property (0 seeds), sim (not run)
          proven: not run
