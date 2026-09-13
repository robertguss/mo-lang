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

  head = lines_text(head_lines(summary))
  slowest = lines_text(slowest_lines(summary.slowest))
  busiest = lines_text(busiest_lines(summary.busiest))
  "#{head}\nslowest\n#{slowest}\nbusiest\n#{busiest}"
end

fn head_lines(summary: Summary) : List(String)
  requests = grouped(summary.requests)
  errors = grouped(summary.errors)
  malformed = grouped(summary.malformed)
  per_minute = one_decimal(summary.per_minute)
  width = widest([requests, errors, malformed, per_minute])
  error_percent = (summary.error_rate * 100.0).to_string(1)
  requests_line = "requests   #{requests.pad_left(width, " ")}"
  errors_line = "errors     #{errors.pad_left(width, " ")}  (#{error_percent}%)"
  malformed_line = "malformed  #{malformed.pad_left(width, " ")}"
  per_minute_line = "per minute #{per_minute.pad_left(width, " ")}"
  [requests_line, errors_line, malformed_line, per_minute_line]
end

fn slowest_lines(slowest: List(Record)) : List(String)
  ms_width = widest(slowest.map(fn(r) grouped(r.ms.to_u64) end))
  request_width = widest(slowest.map(fn(r) "#{r.method} #{r.path}" end))
  slowest.map(fn(r)
    ms = grouped(r.ms.to_u64).pad_left(ms_width, " ")
    request = "#{r.method} #{r.path}".pad_right(request_width, " ")
    "  #{ms} ms  #{request}   #{r.at.to_iso8601}"
  end)
end

fn busiest_lines(busiest: List(Count)) : List(String)
  count_width = widest(busiest.map(fn(c) grouped(c.count) end))
  busiest.map(fn(c) "  #{grouped(c.count).pad_left(count_width, " ")}  #{c.method} #{c.path}" end)
end

fn json(summary: Summary) : String
  ensures !card?(result)

  slowest = summary.slowest.map(fn(r)
    JsonSlow(ms: r.ms, method: r.method, path: r.path, at: r.at)
  end)
  shaped = JsonSummary(requests: summary.requests, errors: summary.errors,
    error_rate: summary.error_rate.round(3), malformed: summary.malformed,
    per_minute: summary.per_minute.round(1), slowest: slowest, busiest: summary.busiest)
  "#{Json.encode(shaped)}\n"
end

# 1204 is "1_204": Mo's own thousands separator.
fn grouped(n: UInt64) : String
  return "#{n}" if n < 1_000
  low = "#{n % 1_000}".pad_left(3, "0")
  "#{grouped(n / 1_000)}_#{low}"
end

# 1234.56 is "1_234.6": one decimal, the whole part grouped.
fn one_decimal(x: Float64) : String
  requires x >= 0.0

  parts = x.to_string(1).split(".")
  whole = (parts.first or "0").to_u64 or 0
  "#{grouped(whole)}.#{parts.last or "0"}"
end

fn widest(texts: List(String)) : UInt64
  texts.map(fn(t) t.size end).max or 0
end

fn lines_text(lines: List(String)) : String
  String.join(lines.map(fn(line) "#{line}\n" end), "")
end

fn example_summary() : Summary
  slowest = [Record(at: Time.from_parts(2026, 9, 12, 10, 0, 21), method: "POST",
    path: "/api/orders", status: 503, ms: 1_204), Record(at: Time.from_parts(2026, 9, 12, 10, 0, 2),
    method: "GET", path: "/api/users", status: 200, ms: 340)]
  busiest = [Count(count: 611, method: "GET", path: "/api/users"), Count(count: 2, method: "GET",
    path: "/api/cards/****************/charge")]
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
