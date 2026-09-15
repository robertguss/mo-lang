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
  # body gone; regenerate
end

fn head_lines(summary: Summary) : List(String)
  # body gone; regenerate
end

fn slowest_lines(slowest: List(Record)) : List(String)
  # body gone; regenerate
end

fn busiest_lines(busiest: List(Count)) : List(String)
  # body gone; regenerate
end

fn json(summary: Summary) : String
  ensures !card?(result)
  # body gone; regenerate
end

# 1204 is "1_204": Mo's own thousands separator.
fn grouped(n: UInt64) : String
  # body gone; regenerate
end

# 1234.56 is "1_234.6": one decimal, the whole part grouped.
fn one_decimal(x: Float64) : String
  requires x >= 0.0
  # body gone; regenerate
end

fn widest(texts: List(String)) : UInt64
  # body gone; regenerate
end

fn lines_text(lines: List(String)) : String
  # body gone; regenerate
end

fn example_summary() : Summary
  # body gone; regenerate
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
