module Logstat.Report
expose Slow, Printed, text, json, thousands, decimal

use Logstat.Parse{Record, card?}
use Logstat.Stats{Busy, Summary, Top, Window, busiest, empty, error_rate, per_minute, with_lines}

intent "Write a summary as the text report, counts then the slowest then the busiest, or as one JSON object, with integers in the text grouped by `_` like Mo's own."

struct Slow
  ms: UInt32
  method: String
  path: String
  at: Time
end

# The JSON object, in the spec's field order.
struct Printed
  requests: UInt64
  errors: UInt64
  error_rate: Float64
  malformed: UInt64
  per_minute: Float64
  slowest: List(Slow)
  busiest: List(Busy)
end

fn text(summary: Summary, top: Top) : String
  ensures !card?(result)

  String.join([counts(summary),
    slowest(summary.slowest.take(top)),
    busiest_rows(busiest(summary, top))],
    "\n")
end

# One line, with its newline. The error rate has three decimals, per minute one.
fn json(summary: Summary, top: Top) : String
  ensures !card?(result)

  slow = summary.slowest.take(top).map(fn(r)
    Slow(ms: r.ms, method: r.method, path: r.path, at: r.at)
  end)
  printed = Printed(requests: summary.requests, errors: summary.errors,
    error_rate: error_rate(summary).round(3), malformed: summary.malformed,
    per_minute: per_minute(summary).round(1), slowest: slow, busiest: busiest(summary, top))
  "#{Json.encode(printed)}\n"
end

# Labels in a column of 10, values right-aligned to the widest of them, at least 5.
fn counts(summary: Summary) : String
  requests = thousands(summary.requests)
  errors = thousands(summary.errors)
  malformed = thousands(summary.malformed)
  rate = decimal(per_minute(summary))
  width = widest([requests, errors, malformed, rate], 5)
  percent = decimal(error_rate(summary) * 100.0)
  rows = [row("requests", requests, width),
    "#{row("errors", errors, width)}  (#{percent}%)",
    row("malformed", malformed, width),
    row("per minute", rate, width)]
  lines(rows)
end

fn row(label: String, value: String, width: UInt64) : String
  "#{label.pad_right(10, " ")} #{value.pad_left(width, " ")}"
end

# Duration right-aligned, method and path left-aligned, then the instant.
fn slowest(records: List(Record)) : String
  ms_width = widest(records.map(fn(r) thousands(r.ms.to_u64) end), 0)
  asked_width = widest(records.map(fn(r) asked(r) end), 0)
  rows = records.map(fn(r) slow_row(r, ms_width, asked_width) end)
  lines(["slowest"].concat(rows))
end

fn slow_row(r: Record, ms_width: UInt64, asked_width: UInt64) : String
  ms = thousands(r.ms.to_u64).pad_left(ms_width, " ")
  "  #{ms} ms  #{asked(r).pad_right(asked_width, " ")}   #{r.at.to_iso8601}"
end

fn asked(r: Record) : String
  "#{r.method} #{r.path}"
end

fn busiest_rows(busy: List(Busy)) : String
  counts = busy.map(fn(b) thousands(b.count) end)
  width = widest(counts, 0)
  rows = busy.zip(counts).map(fn(t) "  #{t.1.pad_left(width, " ")}  #{t.0.method} #{t.0.path}" end)
  lines(["busiest"].concat(rows))
end

fn lines(rows: List(String)) : String
  "#{String.join(rows, "\n")}\n"
end

fn widest(texts: List(String), least: UInt64) : UInt64
  texts.reduce(least, fn(so_far, t) max_of(so_far, t.size) end)
end

# 1204 is 1_204; below a thousand there is no separator.
fn thousands(n: UInt64) : String
  return "#{n}" if n < 1_000
  "#{thousands(n / 1_000)}_#{"#{n % 1_000}".pad_left(3, "0")}"
end

# One decimal, with the whole part grouped as thousands groups it.
fn decimal(x: Float64) : String
  spelled = x.to_string(1)
  parts = spelled.split(".")
  case (parts.first or "").to_u64
    Some(whole): "#{thousands(whole)}.#{parts.get(1) or "0"}"
    None: spelled
  end
end

fn fixture() : Summary
  lines = ["2026-09-12T10:00:00Z GET /api/users 200 12",
    "2026-09-12T10:00:30Z POST /api/orders 500 1340",
    "2026-09-12T10:01:00Z GET /api/users 200 8",
    "2026-09-12T10:02:00Z GET /cards/4111111111111111 404 340",
    "bad line"]
  with_lines(empty(), lines, Window(top: 2, since: None))
end

test "the counts section: requests, errors with their rate, malformed, per minute"
  report = text(fixture(), 2)
  assert report.starts_with?(lines(["requests       4",
    "errors         1  (25.0%)",
    "malformed      1",
    "per minute   2.0"]))
end

test "the slowest section: duration, method and path, instant, card number masked"
  report = text(fixture(), 2)
  assert report.contains?(lines(["slowest",
    "  1_340 ms  POST /api/orders              2026-09-12T10:00:30Z",
    "    340 ms  GET /cards/****************   2026-09-12T10:02:00Z"]))
end

test "the busiest section, and the three sections apart by one blank line"
  report = text(fixture(), 2)
  assert report.ends_with?("\n\nbusiest\n  2  GET /api/users\n  1  POST /api/orders\n")
  assert report.lines.size == 12
  assert text(fixture(), 1).lines.size == 10
end

test "an empty summary still has every section"
  expected = lines(["requests       0",
    "errors         0  (0.0%)",
    "malformed      0",
    "per minute   0.0",
    "",
    "slowest",
    "",
    "busiest"])
  assert text(empty(), 5) == expected
end

test "the JSON form is one object in the spec's field order"
  expected = "{\"requests\": 4, \"errors\": 1, \"error_rate\": 0.25, \"malformed\": 1, \"per_minute\": 2.0, \"slowest\": [{\"ms\": 1340, \"method\": \"POST\", \"path\": \"/api/orders\", \"at\": \"2026-09-12T10:00:30Z\"}, {\"ms\": 340, \"method\": \"GET\", \"path\": \"/cards/****************\", \"at\": \"2026-09-12T10:02:00Z\"}], \"busiest\": [{\"count\": 2, \"method\": \"GET\", \"path\": \"/api/users\"}, {\"count\": 1, \"method\": \"POST\", \"path\": \"/api/orders\"}]}\n"
  assert json(fixture(), 2) == expected
  nothing = "{\"requests\": 0, \"errors\": 0, \"error_rate\": 0.0, \"malformed\": 0, \"per_minute\": 0.0, \"slowest\": [], \"busiest\": []}\n"
  assert json(empty(), 5) == nothing
end

test "integers group by thousands, and a decimal groups its whole part"
  assert thousands(0) == "0"
  assert thousands(999) == "999"
  assert thousands(1_204) == "1_204"
  assert thousands(1_000_005) == "1_000_005"
  assert decimal(40.06) == "40.1"
  assert decimal(12_345.0) == "12_345.0"
  assert decimal(1.0 / 3.0 * 100.0) == "33.3"
end

test "a wide count widens the counts column, and a narrow one keeps it at five"
  assert widest(["1_204_000", "37"], 5) == 9
  assert widest(["4", "2.0"], 5) == 5
  assert row("requests", "1_204_000", 9) == "requests   1_204_000"
  assert row("errors", "37", 9) == "errors            37"
end

verified: types, contracts, tests (7), property (0 seeds), sim (not run)
          proven: not run
