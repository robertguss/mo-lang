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
  through_slowest = head.concat(slowest_lines(summary.slowest)).push("").push("busiest")
  lines_text(through_slowest.concat(busiest_lines(summary.busiest)))
end

fn head_lines(summary: Summary) : List(String)
  labels = ["requests", "errors", "malformed", "per minute"]
  values = [grouped(summary.requests),
    grouped(summary.errors),
    grouped(summary.malformed),
    one_decimal(summary.per_minute)]
  label_width = widest(labels)
  value_width = widest(values)
  rows = labels.zip(values).map(fn(row)
    "#{row.0.pad_right(label_width, " ")} #{row.1.pad_left(value_width, " ")}"
  end)
  percent = one_decimal(summary.error_rate * 100.0)
  [rows.get(0) or "", "#{rows.get(1) or ""}  (#{percent}%)", rows.get(2) or "", rows.get(3) or ""]
end

fn slowest_lines(slowest: List(Record)) : List(String)
  durations = slowest.map(fn(r) grouped(r.ms.to_u64) end)
  requests = slowest.map(fn(r) "#{r.method} #{r.path}" end)
  stamps = slowest.map(fn(r) r.at.to_iso8601 end)
  duration_width = widest(durations)
  request_width = widest(requests)
  durations.zip(requests).zip(stamps).map(fn(row)
    left = row.0
    "  #{left.0.pad_left(duration_width, " ")} ms  #{left.1.pad_right(request_width, " ")}   #{row.1}"
  end)
end

fn busiest_lines(busiest: List(Count)) : List(String)
  counts = busiest.map(fn(c) grouped(c.count) end)
  count_width = widest(counts)
  counts.zip(busiest).map(fn(row)
    ranked = row.1
    "  #{row.0.pad_left(count_width, " ")}  #{ranked.method} #{ranked.path}"
  end)
end

fn json(summary: Summary) : String
  ensures !card?(result)

  rows = summary.slowest.map(fn(r) JsonSlow(ms: r.ms, method: r.method, path: r.path, at: r.at) end)
  object = JsonSummary(requests: summary.requests, errors: summary.errors,
    error_rate: summary.error_rate.round(3), malformed: summary.malformed,
    per_minute: summary.per_minute.round(1), slowest: rows, busiest: summary.busiest)
  "#{Json.encode(object)}\n"
end

# 1204 is "1_204": Mo's own thousands separator.
fn grouped(n: UInt64) : String
  String.grouped(n)
end

# 1234.56 is "1_234.6": one decimal, the whole part grouped.
fn one_decimal(x: Float64) : String
  requires x >= 0.0

  parts = x.to_string(1).split(".")
  whole = (parts.first or "0").to_u64 or 0
  "#{grouped(whole)}.#{parts.last or "0"}"
end

fn widest(texts: List(String)) : UInt64
  texts.map(fn(text) text.size end).max or 0
end

fn lines_text(lines: List(String)) : String
  "#{String.join(lines, "\n")}\n"
end

fn example_summary() : Summary
  slowest = [Record(at: Time.from_parts(2026, 9, 12, 10, 0, 21), method: "POST",
    path: "/api/orders", status: 503, ms: 1_204),
    Record(at: Time.from_parts(2026, 9, 12, 10, 0, 2), method: "GET", path: "/api/users",
    status: 500, ms: 340)]
  Summary(requests: 1_204, errors: 37, successes: 1_167, malformed: 2,
    error_rate: 37.to_f64 / 1_204.to_f64, per_minute: 40.1, slowest: slowest,
    busiest: [Count(count: 611, method: "GET", path: "/api/users"),
    Count(count: 2, method: "GET", path: "/api/cards/****************/charge")])
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
