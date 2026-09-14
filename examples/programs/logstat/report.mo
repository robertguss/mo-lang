module Logstat.Report
expose Slow, Document, text, json, grouped, decimal, percent

use Logstat.Parse{Entry, card?, entries}
use Logstat.Stats{Busy, Summary, counted, empty, error_rate, malformed_line, per_minute, summary}

intent "Print a summary as the text report, whole numbers carrying _ between thousands, or as one JSON object; a path or timestamp is printed only as its entry holds it, already masked."

# One of the slowest requests, as the JSON object names its fields.
struct Slow
  ms: UInt32
  method: String
  path: String
  at: String
end

# The JSON object, field for field.
struct Document
  requests: UInt64
  errors: UInt64
  error_rate: Float64
  malformed: UInt64
  per_minute: Float64
  slowest: List(Slow)
  busiest: List(Busy)
end

fn text(s: Summary) : String
  sections = [counts(s),
    ["", "slowest"],
    slow_lines(s.slowest),
    ["", "busiest"],
    busy_lines(s.busiest)]
  "#{String.join(sections.flat_map(fn(lines) lines end), "\n")}\n"
end

# Each label padded to 11 characters, each value right-aligned in 5 after it.
fn counts(s: Summary) : List(String)
  ["#{label("requests")}#{column(grouped(s.requests))}",
    "#{label("errors")}#{column(grouped(s.errors))}  (#{percent(s.errors, s.requests)}%)",
    "#{label("malformed")}#{column(grouped(s.malformed))}",
    "#{label("per minute")}#{column(decimal(per_minute(s)))}"]
end

fn label(name: String) : String
  name.pad_right(11, " ")
end

fn column(value: String) : String
  value.pad_left(5, " ")
end

# Durations right-aligned, method and path padded to the widest, then the timestamp.
fn slow_lines(slowest: List(Entry)) : List(String)
  ms_width = widest(slowest.map(fn(e) grouped(e.duration_ms.to_u64) end))
  asked_width = widest(slowest.map(fn(e) "#{e.method} #{e.path}" end))
  slowest.map(fn(e) slow_line(e, ms_width, asked_width) end)
end

fn slow_line(e: Entry, ms_width: UInt64, asked_width: UInt64) : String
  ms = grouped(e.duration_ms.to_u64).pad_left(ms_width, " ")
  asked = "#{e.method} #{e.path}".pad_right(asked_width, " ")
  "  #{ms} ms  #{asked}   #{e.stamp}"
end

fn busy_lines(busiest: List(Busy)) : List(String)
  width = widest(busiest.map(fn(b) grouped(b.count) end))
  busiest.map(fn(b) "  #{grouped(b.count).pad_left(width, " ")}  #{b.method} #{b.path}" end)
end

fn widest(texts: List(String)) : UInt64
  texts.map(fn(t) t.size end).max or 0
end

# A whole number with _ between thousands: 1_204.
fn grouped(n: UInt64) : String
  return "#{n}" if n < 1_000
  low = "#{n % 1_000}".pad_left(3, "0")
  "#{grouped(n / 1_000)}_#{low}"
end

# A number with one decimal and _ between the thousands of its whole part: 1_204.5.
fn decimal(x: Float64) : String
  written = x.to_string(1)
  parts = written.split(".")
  case (parts.first or "").to_u64
    Some(whole): "#{grouped(whole)}.#{parts.last or "0"}"
    None: written
  end
end

# A part of a whole as a percentage with one decimal: 3.1; 0.0 of nothing.
fn percent(part: UInt64, whole: UInt64) : String
  requires part <= whole

  return "0.0" if whole == 0
  (part.to_f64 * 100.0 / whole.to_f64).to_string(1)
end

# The error rate to three decimals and the requests per minute to one.
fn json(s: Summary) : String
  Json.encode(document(s))
end

fn document(s: Summary) : Document
  Document(requests: s.requests, errors: s.errors, error_rate: error_rate(s).round(3),
    malformed: s.malformed, per_minute: per_minute(s).round(1),
    slowest: s.slowest.map(fn(e) slow(e) end), busiest: s.busiest)
end

fn slow(e: Entry) : Slow
  Slow(ms: e.duration_ms, method: e.method, path: e.path, at: e.stamp)
end

# The summary of four requests over one minute, two of them errors, and one malformed line.
fn sample(top: UInt64) : Summary
  lines = ["2026-09-12T10:00:01Z GET /api/users 200 12",
    "2026-09-12T10:00:02Z POST /api/orders 500 340",
    "2026-09-12T10:00:31Z GET /api/users 200 1250",
    "2026-09-12T10:01:01Z GET /c/4111111111111111 502 88"]
  summary(malformed_line(entries(lines).reduce(empty(top), fn(t, e) counted(t, e) end)))
end

test "the counts section aligns its values and gives the error rate and requests per minute"
  assert text(sample(5)).lines.take(4) == ["requests       4",
    "errors         2  (50.0%)",
    "malformed      1",
    "per minute   4.0"]
end

test "the slowest section is by duration, with method and path padded to the widest"
  assert text(sample(5)).lines.slice(4, 10) == ["",
    "slowest",
    "  1_250 ms  GET /api/users            2026-09-12T10:00:31Z",
    "    340 ms  POST /api/orders          2026-09-12T10:00:02Z",
    "     88 ms  GET /c/****************   2026-09-12T10:01:01Z",
    "     12 ms  GET /api/users            2026-09-12T10:00:01Z"]
end

test "the busiest section is by count, then path"
  assert text(sample(5)).lines.drop(10) == ["",
    "busiest",
    "  2  GET /api/users",
    "  1  POST /api/orders",
    "  1  GET /c/****************"]
end

test "a summary of nothing still prints every section"
  assert text(summary(empty(5))) == "requests       0\nerrors         0  (0.0%)\nmalformed      0\nper minute   0.0\n\nslowest\n\nbusiest\n"
end

test "the JSON object holds the counts, the rates, and the top lists"
  assert json(sample(2)) == "{\"requests\": 4, \"errors\": 2, \"error_rate\": 0.5, \"malformed\": 1, \"per_minute\": 4.0, \"slowest\": [{\"ms\": 1250, \"method\": \"GET\", \"path\": \"/api/users\", \"at\": \"2026-09-12T10:00:31Z\"}, {\"ms\": 340, \"method\": \"POST\", \"path\": \"/api/orders\", \"at\": \"2026-09-12T10:00:02Z\"}], \"busiest\": [{\"count\": 2, \"method\": \"GET\", \"path\": \"/api/users\"}, {\"count\": 1, \"method\": \"POST\", \"path\": \"/api/orders\"}]}"
end

test "no card number reaches the text or the JSON"
  assert !card?(text(sample(5)))
  assert !card?(json(sample(5)))
end

test "whole numbers carry _ between thousands, and decimals keep one place"
  assert grouped(0) == "0"
  assert grouped(999) == "999"
  assert grouped(1_000) == "1_000"
  assert grouped(1_204) == "1_204"
  assert grouped(12_000_005) == "12_000_005"
  assert decimal(40.13) == "40.1"
  assert decimal(1_234.56) == "1_234.6"
  assert percent(37, 1_204) == "3.1"
  assert percent(0, 0) == "0.0"
end

test rejects "a percentage of a part larger than its whole"
  percent(2, 1)
end
