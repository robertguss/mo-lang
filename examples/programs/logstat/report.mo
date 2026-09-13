module Logstat.Report
expose text, json, grouped, percent

use Logstat.Stats{Slow, Busy, Summary, empty_tally, add_lines, summarize}

intent "Print a summary as the text report or as one JSON object, numbers grouped by _ like Mo's own."

fn text(summary: Summary) : String
  String.join([counts(summary), slowest(summary.slowest), busiest(summary.busiest)], "\n")
end

fn json(summary: Summary) : String
  "#{Json.encode(summary)}\n"
end

fn counts(s: Summary) : String
  values = [grouped(s.requests), grouped(s.errors), grouped(s.malformed), decimal(s.per_minute)]
  width = values.map(fn(v) v.size end).max or 0
  labels = ["requests", "errors", "malformed", "per minute"]
  rows = labels.zip(values).map(fn(pair) count_row(pair, width) end)
  error_row = "#{rows.get(1) or ""}  (#{percent(s.errors, s.requests)})"
  lines = [rows.get(0) or "", error_row, rows.get(2) or "", rows.get(3) or ""]
  String.join(lines.map(fn(line) "#{line}\n" end), "")
end

fn count_row(pair: (String, String), width: UInt64) : String
  case pair
    (label, value): "#{label.pad_right(10, " ")} #{value.pad_left(width, " ")}"
  end
end

fn slowest(rows: List(Slow)) : String
  ms = rows.map(fn(s) "#{grouped(s.ms.to_u64)} ms" end)
  requests = rows.map(fn(s) "#{s.method} #{s.path}" end)
  ms_width = ms.map(fn(m) m.size end).max or 0
  request_width = requests.map(fn(r) r.size end).max or 0
  cells = ms.zip(requests).zip(rows.map(fn(s) s.at.to_iso8601 end))
  lines = cells.map(fn(cell) slow_row(cell, ms_width, request_width) end)
  "slowest\n#{String.join(lines, "")}"
end

fn slow_row(cell: ((String, String), String), ms_width: UInt64, request_width: UInt64) : String
  case cell
    ((ms, request), at):
      "  #{ms.pad_left(ms_width, " ")}  #{request.pad_right(request_width, " ")}  #{at}\n"
  end
end

fn busiest(rows: List(Busy)) : String
  counts = rows.map(fn(b) grouped(b.count) end)
  width = counts.map(fn(c) c.size end).max or 0
  lines = counts.zip(rows).map(fn(pair) busy_row(pair, width) end)
  "busiest\n#{String.join(lines, "")}"
end

fn busy_row(pair: (String, Busy), width: UInt64) : String
  case pair
    (count, b): "  #{count.pad_left(width, " ")}  #{b.method} #{b.path}\n"
  end
end

# Digits in groups of three from the right, joined by _: 1204 is 1_204.
fn grouped(n: UInt64) : String
  digits = "#{n}".chars
  String.join(digits.enumerate.map(fn(pair) digit_at(pair, digits.size) end), "")
end

# A digit, with _ before it when a group of three starts there.
fn digit_at(pair: (UInt64, String), size: UInt64) : String
  case pair
    (i, digit): if i > 0 and (size - i) % 3 == 0
      "_#{digit}"
    else
      digit
    end
  end
end

# A float to one decimal, its whole part grouped: 1234.5 is 1_234.5.
fn decimal(x: Float64) : String
  spelled = x.to_string(1)
  whole = spelled.slice(0, spelled.size - 2).to_u64 or 0
  "#{grouped(whole)}#{spelled.slice(spelled.size - 2, spelled.size)}"
end

fn percent(part: UInt64, whole: UInt64) : String
  requires part <= whole

  return "0.0%" if whole == 0
  "#{(part.to_f64 / whole.to_f64 * 100.0).to_string(1)}%"
end

fn fixture_summary() : Summary
  log = """
  2026-09-12T10:00:01Z GET /api/users 200 12
  2026-09-12T10:00:02Z POST /api/orders 500 340
  2026-09-12T10:00:31Z GET /api/users 200 1204
  2026-09-12T10:01:02Z GET /pay/4111111111111111 200 30
  a line that is not a log line
  """
  summarize(add_lines(empty_tally(), log.lines, None), 5)
end

test "numbers are grouped by _ in threes"
  assert grouped(0) == "0"
  assert grouped(999) == "999"
  assert grouped(1_000) == "1_000"
  assert grouped(1_204) == "1_204"
  assert grouped(12_345_678) == "12_345_678"
  assert decimal(40.06) == "40.1"
  assert decimal(1_234.5) == "1_234.5"
  assert percent(37, 1_204) == "3.1%"
  assert percent(0, 0) == "0.0%"
end

test "the counts section"
  counts = """
  requests     4
  errors       1  (25.0%)
  malformed    1
  per minute 3.9
  """
  assert text(fixture_summary()).lines.take(5) == counts.lines.push("")
end

test "the slowest section"
  slowest = """
  slowest
    1_204 ms  GET /api/users             2026-09-12T10:00:31Z
      340 ms  POST /api/orders           2026-09-12T10:00:02Z
       30 ms  GET /pay/****************  2026-09-12T10:01:02Z
       12 ms  GET /api/users             2026-09-12T10:00:01Z
  """
  assert text(fixture_summary()).lines.slice(5, 11) == slowest.lines.push("")
end

test "the busiest section"
  busiest = """
  busiest
    2  GET /api/users
    1  POST /api/orders
    1  GET /pay/****************
  """
  assert text(fixture_summary()).lines.drop(11) == busiest.lines
end

test "the JSON form is one object on one line"
  empty = json(summarize(empty_tally(), 1))
  assert empty == "{\"requests\": 0, \"errors\": 0, \"error_rate\": 0.0, \"malformed\": 0, \"per_minute\": 0.0, \"slowest\": [], \"busiest\": []}\n"
  assert json(fixture_summary()).contains?("\"slowest\": [{\"ms\": 1204, \"method\": \"GET\", \"path\": \"/api/users\", \"at\": \"2026-09-12T10:00:31Z\"}")
  assert json(fixture_summary()).contains?("\"busiest\": [{\"count\": 2, \"method\": \"GET\", \"path\": \"/api/users\"}")
end

test "no card number reaches either form"
  assert !text(fixture_summary()).contains?("4111")
  assert !json(fixture_summary()).contains?("4111")
end

test rejects "a percent of more than the whole"
  percent(5, 4)
end
