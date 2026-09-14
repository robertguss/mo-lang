module Logstat.Report
expose text_of, json_of, grouped

use Logstat.Parse{Record, card_number?}
use Logstat.Stats{Hit, Summary, Top, counted_line, fresh, summary_of}

intent "Show a summary as the text report, with _ between thousands and the columns lined up, or as one JSON object on one line; a path is shown as its record holds it, card numbers already starred out, so no card number reaches the output."

# The counts, a blank line, the slowest, a blank line, the busiest.
fn text_of(summary: Summary) : String
  ensures result.ends_with?("\n") and !card_number?(result)

  String.join([counts_of(summary), slowest_of(summary.slowest), busiest_of(summary.busiest)], "\n")
end

fn counts_of(s: Summary) : String
  rows = [row("requests", grouped(s.requests), 5),
    "#{row("errors", grouped(s.errors), 5)}  (#{(s.error_rate * 100.0).to_string(1)}%)",
    row("malformed", grouped(s.malformed), 5),
    row("per minute", grouped_decimal(s.per_minute), 6)]
  section(rows)
end

# A label in an 11-column field, then its value right-aligned in width columns.
fn row(label: String, value: String, width: UInt64) : String
  requires label.size < 11

  "#{label.pad_right(11, " ")}#{value.pad_left(width, " ")}"
end

fn slowest_of(records: List(Record)) : String
  ms_width = widest(records.map(fn(r) grouped(r.duration_ms.to_u64) end))
  what_width = widest(records.map(fn(r) "#{r.method} #{r.path}" end))
  section(["slowest"].concat(records.map(fn(r) slow_row(r, ms_width, what_width) end)))
end

fn slow_row(r: Record, ms_width: UInt64, what_width: UInt64) : String
  ms = grouped(r.duration_ms.to_u64).pad_left(ms_width, " ")
  what = "#{r.method} #{r.path}".pad_right(what_width, " ")
  "  #{ms} ms  #{what}   #{r.at.to_iso8601}"
end

fn busiest_of(hits: List(Hit)) : String
  width = widest(hits.map(fn(h) grouped(h.count) end))
  section(["busiest"].concat(hits.map(fn(h) busy_row(h, width) end)))
end

fn busy_row(hit: Hit, width: UInt64) : String
  "  #{grouped(hit.count).pad_left(width, " ")}  #{hit.method} #{hit.path}"
end

fn widest(texts: List(String)) : UInt64
  texts.map(fn(t) t.size end).max or 0
end

# Each row on a line of its own.
fn section(rows: List(String)) : String
  String.join(rows.map(fn(r) "#{r}\n" end), "")
end

# 1204 as 1_204, as Mo writes its numbers.
fn grouped(n: UInt64) : String
  return "#{n}" if n < 1_000
  low = "#{n % 1_000}".pad_left(3, "0")
  "#{grouped(n / 1_000)}_#{low}"
end

# A float to one decimal, its whole part grouped.
fn grouped_decimal(value: Float64) : String
  parts = value.to_string(1).split(".")
  whole = (parts.first or "0").to_u64 or 0
  fraction = parts.last or "0"
  "#{grouped(whole)}.#{fraction}"
end

fn json_of(summary: Summary) : String
  ensures Json.decode(result) is Ok(_) and !card_number?(result)

  fields = ["\"requests\": #{summary.requests}",
    "\"errors\": #{summary.errors}",
    "\"error_rate\": #{summary.error_rate.to_string(3)}",
    "\"malformed\": #{summary.malformed}",
    "\"per_minute\": #{summary.per_minute.to_string(1)}",
    "\"slowest\": [#{String.join(summary.slowest.map(fn(r) slow_json(r) end), ", ")}]",
    "\"busiest\": [#{String.join(summary.busiest.map(fn(h) hit_json(h) end), ", ")}]"]
  "{#{String.join(fields, ", ")}}\n"
end

fn slow_json(r: Record) : String
  fields = ["\"ms\": #{r.duration_ms}",
    "\"method\": #{Json.encode(r.method)}",
    "\"path\": #{Json.encode(r.path)}",
    "\"at\": #{Json.encode(r.at.to_iso8601)}"]
  "{#{String.join(fields, ", ")}}"
end

fn hit_json(hit: Hit) : String
  fields = ["\"count\": #{hit.count}",
    "\"method\": #{Json.encode(hit.method)}",
    "\"path\": #{Json.encode(hit.path)}"]
  "{#{String.join(fields, ", ")}}"
end

fn summary_of_lines(lines: List(String), top: Top) : Summary
  summary_of(lines.reduce(fresh(), fn(tally, line) counted_line(tally, line, None, top) end), top)
end

fn sample() : Summary
  summary_of_lines(["2026-09-12T10:00:01Z GET /api/users 200 12",
    "2026-09-12T10:00:02Z POST /api/orders 500 340",
    "2026-09-12T10:00:31Z GET /api/users 200 1250",
    "2026-09-12T10:01:01Z POST /pay/4111111111111111/charge 200 9",
    "oops"],
    5)
end

test "numbers are grouped by thousands with _"
  assert grouped(0) == "0" and grouped(999) == "999" and grouped(1_000) == "1_000"
  assert grouped(1_204) == "1_204" and grouped(12_345_678) == "12_345_678"
  assert grouped(1_000_001) == "1_000_001"
  assert grouped_decimal(40.12) == "40.1" and grouped_decimal(12_345.06) == "12_345.1"
end

test "the counts section lines up requests, errors and their rate, malformed, and per minute"
  lines = text_of(sample()).lines
  assert lines.take(5) == ["requests       4",
    "errors         1  (25.0%)",
    "malformed      1",
    "per minute    4.0",
    ""]
end

test "the slowest section is duration descending, with the timestamp last"
  lines = text_of(sample()).lines
  assert lines.slice(5, 11) == ["slowest",
    "  1_250 ms  GET /api/users                      2026-09-12T10:00:31Z",
    "    340 ms  POST /api/orders                    2026-09-12T10:00:02Z",
    "     12 ms  GET /api/users                      2026-09-12T10:00:01Z",
    "      9 ms  POST /pay/****************/charge   2026-09-12T10:01:01Z",
    ""]
end

test "the busiest section is count descending, then path, and a card number is starred"
  lines = text_of(sample()).lines
  assert lines.drop(11) == ["busiest",
    "  2  GET /api/users",
    "  1  POST /api/orders",
    "  1  POST /pay/****************/charge"]
end

test "the JSON form is one object on one line, with every section"
  one = summary_of_lines(["2026-09-12T10:00:02Z POST /api/orders 500 340"], 1)
  none = summary_of_lines([], 5)
  assert json_of(one) == "{\"requests\": 1, \"errors\": 1, \"error_rate\": 1.000, \"malformed\": 0, \"per_minute\": 0.0, \"slowest\": [{\"ms\": 340, \"method\": \"POST\", \"path\": \"/api/orders\", \"at\": \"2026-09-12T10:00:02Z\"}], \"busiest\": [{\"count\": 1, \"method\": \"POST\", \"path\": \"/api/orders\"}]}\n"
  assert json_of(none) == "{\"requests\": 0, \"errors\": 0, \"error_rate\": 0.000, \"malformed\": 0, \"per_minute\": 0.0, \"slowest\": [], \"busiest\": []}\n"
end

test rejects "a label too wide for its column"
  row("requests per minute", "1", 5)
end

property "a card number in a path reaches neither the text nor the JSON"
  for digits in any(UInt64) if digits >= 1_000_000_000_000_000
    s = summary_of_lines(["2026-09-12T10:00:01Z GET /pay/#{digits}/x 200 1"], 5)
    assert !card_number?(text_of(s)) and !card_number?(json_of(s))
  end
end

verified: types, contracts, tests (7), property (200 seeds), sim (not run)
          proven: not run
