module Logstat.Report
expose text, json, grouped

use Logstat.Parse{Record, card?}
use Logstat.Stats{Summary, Hit, empty, counted, busiest, per_minute, error_rate}

intent "Print a summary as the text report or as one JSON object: counts with _ between thousands, the error rate, requests per minute, the slowest requests, and the busiest paths."

struct Slow
  ms: UInt32
  method: String
  path: String
  at: Time
end

# The JSON object, its keys in the spec's order.
struct Whole
  requests: UInt64
  errors: UInt64
  error_rate: Float64
  malformed: UInt64
  per_minute: Float64
  slowest: List(Slow)
  busiest: List(Hit)
end

fn text(summary: Summary) : String
  ensures result.ends_with?("\n")
  ensures !card?(result)

  slowest = ["", "slowest"].concat(slow_lines(summary.slowest))
  busy = ["", "busiest"].concat(busy_lines(busiest(summary)))
  "#{String.join(counts(summary).concat(slowest).concat(busy), "\n")}\n"
end

fn json(summary: Summary) : String
  ensures !card?(result)

  Json.encode(Whole(requests: summary.requests, errors: summary.errors,
    error_rate: error_rate(summary).round(3), malformed: summary.malformed,
    per_minute: per_minute(summary).round(1), slowest: summary.slowest.map(fn(r) slow(r) end),
    busiest: busiest(summary)))
end

fn slow(record: Record) : Slow
  Slow(ms: record.duration_ms, method: record.method, path: record.path, at: record.at)
end

# The four counts, labels in a column of 11 and values right-aligned to the widest of them.
fn counts(summary: Summary) : List(String)
  values = [grouped(summary.requests),
    grouped(summary.errors),
    grouped(summary.malformed),
    decimal(per_minute(summary))]
  width = values.map(fn(v) v.size end).max or 0
  labels = ["requests", "errors", "malformed", "per minute"]
  rows = labels.zip(values).map(fn(pair)
    "#{pair.0.pad_right(11, " ")}#{pair.1.pad_left(width, " ")}"
  end)
  percent = decimal(error_rate(summary) * 100.0)
  [rows.get(0) or "", "#{rows.get(1) or ""}  (#{percent}%)"].concat(rows.drop(2))
end

fn slow_lines(slowest: List(Record)) : List(String)
  ms = slowest.map(fn(r) grouped(r.duration_ms.to_u64) end)
  asked = slowest.map(fn(r) "#{r.method} #{r.path}" end)
  ms_width = ms.map(fn(m) m.size end).max or 0
  asked_width = asked.map(fn(a) a.size end).max or 0
  times = slowest.map(fn(r) r.at.to_iso8601 end)
  ms.zip(asked.zip(times)).map(fn(row) slow_line(row, ms_width, asked_width) end)
end

fn slow_line(row: (String, (String, String)), ms_width: UInt64, asked_width: UInt64) : String
  rest = row.1
  "  #{row.0.pad_left(ms_width, " ")} ms  #{rest.0.pad_right(asked_width, " ")}  #{rest.1}"
end

fn busy_lines(hits: List(Hit)) : List(String)
  counts = hits.map(fn(h) grouped(h.count) end)
  width = counts.map(fn(c) c.size end).max or 0
  counts.zip(hits).map(fn(pair)
    "  #{pair.0.pad_left(width, " ")}  #{pair.1.method} #{pair.1.path}"
  end)
end

# A whole number with _ between each three digits from the right, as Mo writes its own.
fn grouped(n: UInt64) : String
  ensures !result.starts_with?("_") and !result.ends_with?("_")

  digits = "#{n}"
  lead = digits.size % 3
  head = if lead == 0: [] else: [digits.slice(0, lead)]
  threes = (0..digits.size / 3).map(fn(i) digits.slice(lead + i * 3, lead + i * 3 + 3) end)
  String.join(head.concat(threes), "_")
end

# A number to one decimal, its whole part grouped.
fn decimal(x: Float64) : String
  spelled = x.to_string(1)
  parts = spelled.split(".")
  whole = (parts.first or "").to_u64 or 0
  "#{grouped(whole)}.#{parts.last or "0"}"
end

fn summary_of(lines: List(String), top: UInt64) : Summary
  lines.reduce(empty(top, None), fn(s, line) counted(s, line) end)
end

fn sample() : List(String)
  ["2026-09-12T10:00:00Z GET /api/users 200 12",
    "2026-09-12T10:00:30Z POST /api/orders 500 340",
    "2026-09-12T10:01:00Z GET /api/users 200 1250",
    "2026-09-12T10:01:30Z GET /cards/4111111111111111 404 340",
    "2026-09-12T10:02:00Z GET /api/users 503 7",
    "malformed"]
end

test "numbers are grouped by thousands with _"
  assert grouped(0) == "0"
  assert grouped(999) == "999"
  assert grouped(1_204) == "1_204"
  assert grouped(100_000) == "100_000"
  assert grouped(12_345_678) == "12_345_678"
  assert decimal(40.06) == "40.1"
  assert decimal(12_345.0) == "12_345.0"
end

test "the counts section aligns its values and gives the error rate"
  lines = text(summary_of(sample(), 5)).lines
  assert lines.take(4) == ["requests     5",
    "errors       2  (40.0%)",
    "malformed    1",
    "per minute 2.5"]
end

test "the slowest section lists duration, request, and time, slowest first, then earliest"
  lines = text(summary_of(sample(), 3)).lines
  assert lines.slice(4, 9) == ["",
    "slowest",
    "  1_250 ms  GET /api/users               2026-09-12T10:01:00Z",
    "    340 ms  POST /api/orders             2026-09-12T10:00:30Z",
    "    340 ms  GET /cards/****************  2026-09-12T10:01:30Z"]
end

test "the busiest section lists count and request, busiest first, then by path"
  lines = text(summary_of(sample(), 2)).lines
  assert lines.drop(8) == ["", "busiest", "  3  GET /api/users", "  1  POST /api/orders"]
end

test "a summary of nothing still prints every section"
  nothing = "requests     0\nerrors       0  (0.0%)\nmalformed    0\nper minute 0.0\n\nslowest\n\nbusiest\n"
  assert text(empty(5, None)) == nothing
end

test "the JSON form is one object with the spec's keys in order"
  two = "{\"requests\": 2, \"errors\": 1, \"error_rate\": 0.5, \"malformed\": 0, \"per_minute\": 4.0, \"slowest\": [{\"ms\": 340, \"method\": \"POST\", \"path\": \"/api/orders\", \"at\": \"2026-09-12T10:00:30Z\"}], \"busiest\": [{\"count\": 1, \"method\": \"POST\", \"path\": \"/api/orders\"}]}"
  assert json(summary_of(sample().take(2), 1)) == two
  nothing = "{\"requests\": 0, \"errors\": 0, \"error_rate\": 0.0, \"malformed\": 0, \"per_minute\": 0.0, \"slowest\": [], \"busiest\": []}"
  assert json(empty(5, None)) == nothing
end

verified: types, contracts, tests (6), property (0 seeds), sim (not run)
          proven: not run
