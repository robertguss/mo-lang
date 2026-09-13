module Logstat.Stats
expose Top, Window, Summary, Busy, empty, with_lines, summarized, busiest, error?, error_rate, per_minute

use Logstat.Parse{Record, Malformed, parse_line}

intent "Fold records into a summary one file at a time: requests, errors, successes, malformed lines, the first and last instant, the slowest requests, and how often each method and path was asked for."

never "a summary counts more errors than requests, or requests that are neither errors nor successes"
  for s in Summary.all
    s.errors > s.requests or s.requests != s.errors + s.successes
  end
end

type Top = UInt64 where value >= 1 and value <= 100

struct Window
  top: Top
  since: Option(Time)
end

# `slowest` holds at most the window's top records, already in order; `hits` counts each
# (method, path) in the order first seen.
struct Summary
  requests: UInt64
  errors: UInt64
  successes: UInt64
  malformed: UInt64
  first: Option(Time)
  last: Option(Time)
  slowest: List(Record)
  hits: Map((String, String), UInt64)
end

struct Busy
  count: UInt64
  method: String
  path: String
end

fn empty() : Summary
  Summary(requests: 0, errors: 0, successes: 0, malformed: 0, first: None, last: None, slowest: [],
    hits: Map.new())
end

# One file's lines, without their newlines: a malformed line is counted, a line before the
# window's `since` is ignored, and every other line is a request.
fn with_lines(summary: Summary, lines: List(String), window: Window) : Summary
  requires lines.all?(fn(line) !line.contains?("\n") end)
  ensures result.malformed >= summary.malformed and result.requests >= summary.requests

  parsed = lines.map(fn(line) parse_line(line) end)
  kept = parsed.flat_map(fn(p) recorded(p) end).filter(fn(r) since?(r, window.since) end)
  var counted = with_records(summary, kept, window.top)
  counted.malformed += parsed.count(fn(p) p is Error(_) end)
  counted
end

fn summarized(records: List(Record), top: Top) : Summary
  ensures result.errors <= result.requests
  ensures result.requests == records.size and result.slowest.size <= top

  with_records(empty(), records, top)
end

fn with_records(summary: Summary, records: List(Record), top: Top) : Summary
  errors = records.count(fn(r) error?(r) end)
  times = records.map(fn(r) r.at end)
  Summary(requests: summary.requests + records.size, errors: summary.errors + errors,
    successes: summary.successes + records.size - errors, malformed: summary.malformed,
    first: times.concat(listed(summary.first)).min, last: times.concat(listed(summary.last)).max,
    slowest: ranked(summary.slowest.concat(records), top),
    hits: records.reduce(summary.hits, fn(hits, r) hit(hits, r) end))
end

fn recorded(parsed: Result(Record, Malformed)) : List(Record)
  case parsed
    Ok(r): [r]
    Error(_): []
  end
end

fn since?(r: Record, since: Option(Time)) : Bool
  case since
    Some(t): r.at >= t
    None: true
  end
end

fn listed(t: Option(Time)) : List(Time)
  case t
    Some(at): [at]
    None: []
  end
end

fn hit(hits: Map((String, String), UInt64), r: Record) : Map((String, String), UInt64)
  hits.update((r.method, r.path), 0, fn(n) n + 1 end)
end

# Slowest first; equal durations earliest first; equal instants in the order read.
fn ranked(records: List(Record), top: Top) : List(Record)
  by_time = records.sort_by(fn(r) r.at end)
  by_time.sort_by_desc(fn(r) r.ms end).take(top)
end

# Most asked for first; equal counts by path, then by method, in byte order.
fn busiest(summary: Summary, top: Top) : List(Busy)
  ensures result.size <= top

  all = summary.hits.entries.map(fn(e) Busy(count: e.1, method: e.0.0, path: e.0.1) end)
  by_path = all.sort_by(fn(b) (b.path, b.method) end)
  by_path.sort_by_desc(fn(b) b.count end).take(top)
end

fn error?(r: Record) : Bool
  r.status >= 500
end

fn error_rate(summary: Summary) : Float64
  return 0.0 if summary.requests == 0
  summary.errors.to_f64 / summary.requests.to_f64
end

# Requests over the minutes between the first and the last instant; no span is 0.0.
fn per_minute(summary: Summary) : Float64
  case (summary.first, summary.last)
    (Some(first), Some(last)): over_minutes(summary.requests, last.since(first).minutes)
    _: 0.0
  end
end

fn over_minutes(requests: UInt64, minutes: Float64) : Float64
  return 0.0 if minutes <= 0.0
  requests.to_f64 / minutes
end

fn at(minute: UInt64, second: UInt64) : Time
  Time.from_parts(2026, 9, 12, 10, minute, second)
end

fn record(method: String, path: String, status: UInt16, ms: UInt32, at: Time) : Record
  Record(at: at, method: method, path: path, status: status, ms: ms)
end

fn sample() : List(Record)
  [record("GET", "/api/users", 200, 12, at(0, 1)),
    record("POST", "/api/orders", 500, 340, at(0, 2)),
    record("GET", "/api/users", 404, 340, at(0, 0)),
    record("GET", "/health", 200, 1, at(1, 0)),
    record("POST", "/api/orders", 201, 90, at(0, 30)),
    record("GET", "/api/users", 503, 7, at(0, 45))]
end

test "requests split into errors and successes, and only 500 to 599 is an error"
  s = summarized(sample(), 5)
  assert s.requests == 6
  assert s.errors == 2
  assert s.successes == 4
  assert s.malformed == 0
  assert error_rate(s) == 2.0 / 6.0
  assert error_rate(empty()) == 0.0
end

test "the slowest are by duration, then earliest first, cut to the top"
  s = summarized(sample(), 3)
  assert s.slowest.map(fn(r) (r.ms, r.at) end) == [(340, at(0, 0)),
    (340, at(0, 2)),
    (90, at(0, 30))]
  assert summarized(sample(), 1).slowest.size == 1
end

test "the busiest are by count, then path, then method, cut to the top"
  s = summarized(sample(), 5)
  top = busiest(s, 5).map(fn(b) "#{b.count} #{b.method} #{b.path}" end)
  assert top == ["3 GET /api/users", "2 POST /api/orders", "1 GET /health"]
  assert busiest(s, 1).size == 1
  tied = summarized([record("GET", "/b", 200, 1, at(0, 0)),
    record("PUT", "/a", 200, 1, at(0, 0)),
    record("GET", "/a", 200, 1, at(0, 0))],
    5)
  assert busiest(tied, 5).map(fn(b) "#{b.method} #{b.path}" end) == ["GET /a", "PUT /a", "GET /b"]
end

test "per minute is requests over the span, and no span is 0.0"
  s = summarized(sample(), 5)
  assert s.first == Some(at(0, 0))
  assert s.last == Some(at(1, 0))
  assert per_minute(s) == 6.0
  assert per_minute(summarized(sample().take(1), 5)) == 0.0
  assert per_minute(empty()) == 0.0
end

test "lines fold in one file at a time, counting malformed lines and skipping lines before since"
  window = Window(top: 5, since: Some(at(0, 2)))
  first = with_lines(empty(), ["2026-09-12T10:00:01Z GET /a 200 5", "not a line"], window)
  both = with_lines(first,
    ["2026-09-12T10:00:02Z GET /a 500 9", "2026-09-12T10:01:02Z GET /b 200 3", ""], window)
  assert first.requests == 0 and first.malformed == 1
  assert both.requests == 2 and both.errors == 1 and both.malformed == 2
  assert both.first == Some(at(0, 2)) and both.last == Some(at(1, 2))
  assert both.slowest.map(fn(r) r.ms end) == [9, 3]
end

test "a summary built in two parts is the summary built at once"
  whole = summarized(sample(), 2)
  parts = with_records(summarized(sample().take(3), 2), sample().drop(3), 2)
  assert parts == whole
end

test rejects "a line that still holds its newline"
  with_lines(empty(), ["2026-09-12T10:00:01Z GET /a 200 5\n"], Window(top: 5, since: None))
end

test rejects "a top of zero"
  Window(top: 0, since: None)
end

test rejects "a top above one hundred"
  summarized(sample(), 101)
end

property "errors never exceed requests, and requests are errors plus successes, for any records"
  for generated in any(List(Record)), n in any(UInt8)
    records = generated.map(fn(r) record(r.method, r.path, 100 + r.status % 500, r.ms, r.at) end)
    top = 1 + n.to_u64 % 100
    s = summarized(records, top)
    assert s.errors <= s.requests
    assert s.requests == s.errors + s.successes
    assert busiest(s, top).map(fn(b) b.count end).sum == s.requests or s.hits.size > top
  end
end

verified: types, contracts, tests (10), property (200 seeds), sim (not run)
          proven: not run
