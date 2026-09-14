module Logstat.Stats
expose Summary, Hit, empty, counted, malformed_line, added, busiest, per_minute, error_rate, error?

use Logstat.Parse{Record, Status, parse_line}

intent "Fold log lines into one summary as they are read: requests, errors, and malformed lines, the first and last time, the slowest requests, and the hits per method and path, holding no more than the top slowest and one count per path."

never "a summary counts more errors than requests, or its requests are not its errors and successes"
  for s in Summary.all
    s.errors > s.requests or s.requests != s.errors + s.successes
  end
end

struct Hit
  count: UInt64
  method: String
  path: String
end

# top is how many slowest requests and busiest paths the summary gives; since, when there is one,
# is the time before which a line is ignored.
struct Summary
  top: UInt64
  since: Option(Time)
  requests: UInt64
  errors: UInt64
  successes: UInt64
  malformed: UInt64
  first: Option(Time)
  last: Option(Time)
  slowest: List(Record)
  hits: Map((String, String), UInt64)
end

fn empty(top: UInt64, since: Option(Time)) : Summary
  requires top >= 1 and top <= 100
  ensures result.requests == 0 and result.malformed == 0

  Summary(top: top, since: since, requests: 0, errors: 0, successes: 0, malformed: 0, first: None,
    last: None, slowest: [], hits: Map.new())
end

# One line read: a record counted when it is not before since, a line that is not one counted as
# malformed.
fn counted(summary: Summary, line: String) : Summary
  ensures result.requests + result.malformed <= summary.requests + summary.malformed + 1

  case parse_line(line)
    Ok(record): if kept?(summary, record): added(summary, record) else: summary
    Error(_): malformed_line(summary)
  end
end

fn kept?(summary: Summary, record: Record) : Bool
  case summary.since
    Some(since): record.at >= since
    None: true
  end
end

fn malformed_line(summary: Summary) : Summary
  ensures result.malformed == summary.malformed + 1

  var next = summary
  next.malformed += 1
  next
end

fn added(summary: Summary, record: Record) : Summary
  ensures result.requests == summary.requests + 1
  ensures result.slowest.size <= result.top

  # One construction, not a var changed field by field: the never above reads every Summary a
  # run holds, and a copy with its requests counted but not yet its error would trip it.
  errors = if error?(record.status): 1 else: 0
  Summary(top: summary.top, since: summary.since, requests: summary.requests + 1,
    errors: summary.errors + errors, successes: summary.successes + 1 - errors,
    malformed: summary.malformed, first: Some(min_of(summary.first or record.at, record.at)),
    last: Some(max_of(summary.last or record.at, record.at)),
    slowest: ranked(summary.slowest, record, summary.top),
    hits: summary.hits.update((record.method, record.path), 0, fn(n) n + 1 end))
end

fn error?(status: Status) : Bool
  status >= 500 and status <= 599
end

# The slowest records, at most top of them: by duration descending, then time ascending, then the
# order they were read.
fn ranked(slowest: List(Record), record: Record, top: UInt64) : List(Record)
  ensures result.size <= top

  return slowest if slowest.size >= top and !slower?(record, slowest.last or record)
  slowest.push(record).sort_by(fn(r) r.at end).sort_by_desc(fn(r) r.duration_ms end).take(top)
end

fn slower?(a: Record, b: Record) : Bool
  a.duration_ms > b.duration_ms or (a.duration_ms == b.duration_ms and a.at < b.at)
end

# The busiest method and path pairs, at most top of them: by count descending, then path
# ascending, then method ascending.
fn busiest(summary: Summary) : List(Hit)
  ensures result.size <= summary.top

  hits = summary.hits.entries.map(fn(entry) hit(entry) end)
  hits.sort_by(fn(h) (h.path, h.method) end).sort_by_desc(fn(h) h.count end).take(summary.top)
end

fn hit(entry: ((String, String), UInt64)) : Hit
  key = entry.0
  Hit(count: entry.1, method: key.0, path: key.1)
end

# Requests per minute over the span from the first time to the last; a span of no time, one
# request's included, is 0.0.
fn per_minute(summary: Summary) : Float64
  ensures result >= 0.0

  case summary.first
    Some(first): rate(summary.requests, (summary.last or first) - first)
    None: 0.0
  end
end

fn rate(requests: UInt64, span: Duration) : Float64
  return 0.0 if span.ms <= 0
  requests.to_f64 / span.minutes
end

fn error_rate(summary: Summary) : Float64
  ensures result >= 0.0 and result <= 1.0

  if summary.requests == 0: 0.0 else: summary.errors.to_f64 / summary.requests.to_f64
end

fn at(second: UInt64) : Time
  Time.from_parts(2026, 9, 12, 10, 0, second)
end

fn record(second: UInt64, path: String, status: Status, ms: UInt32) : Record
  Record(at: at(second), method: "GET", path: path, status: status, duration_ms: ms)
end

test "requests, errors, and malformed lines are counted, and 5xx alone is an error"
  lines = ["2026-09-12T10:00:01Z GET /api/users 200 12",
    "2026-09-12T10:00:02Z POST /api/orders 500 340",
    "not a line",
    "2026-09-12T10:00:03Z GET /api/users 404 7",
    "2026-09-12T10:00:04Z GET /api/users 599 8"]
  summary = lines.reduce(empty(5, None), fn(s, line) counted(s, line) end)
  assert summary.requests == 4
  assert summary.errors == 2
  assert summary.successes == 2
  assert summary.malformed == 1
  assert error_rate(summary) == 0.5
  assert !error?(499) and error?(500)
end

test "lines before since are ignored, and malformed lines are counted whatever since says"
  lines = ["2026-09-12T10:00:01Z GET /a 200 12", "2026-09-12T10:00:30Z GET /b 200 12", "bad"]
  summary = lines.reduce(empty(5, Some(at(30))), fn(s, line) counted(s, line) end)
  assert summary.requests == 1
  assert summary.malformed == 1
  assert summary.first == Some(at(30))
end

test "per minute is requests over the span from the first time to the last, whatever the order"
  one = added(empty(5, None), record(10, "/a", 200, 1))
  assert per_minute(one) == 0.0
  assert per_minute(empty(5, None)) == 0.0
  three = added(added(one, record(40, "/a", 200, 1)), record(0, "/a", 200, 1))
  assert three.first == Some(at(0)) and three.last == Some(at(40))
  assert per_minute(three) == 4.5
  assert error_rate(empty(5, None)) == 0.0
end

test "the slowest are by duration descending, then time ascending, and only top are kept"
  records = [record(5, "/e", 200, 30),
    record(1, "/a", 200, 10),
    record(4, "/d", 200, 30),
    record(2, "/b", 200, 99),
    record(3, "/c", 200, 10)]
  summary = records.reduce(empty(3, None), fn(s, r) added(s, r) end)
  assert summary.slowest.map(fn(r) r.path end) == ["/b", "/d", "/e"]
  all = records.reduce(empty(100, None), fn(s, r) added(s, r) end)
  assert all.slowest.map(fn(r) r.path end) == ["/b", "/d", "/e", "/a", "/c"]
end

test "the busiest are by count descending, then path ascending, then method, and only top"
  lines = ["2026-09-12T10:00:01Z GET /z 200 1",
    "2026-09-12T10:00:02Z GET /b 200 1",
    "2026-09-12T10:00:03Z POST /a 200 1",
    "2026-09-12T10:00:04Z GET /a 200 1",
    "2026-09-12T10:00:05Z GET /z 200 1",
    "2026-09-12T10:00:06Z GET /c 200 1"]
  summary = lines.reduce(empty(4, None), fn(s, line) counted(s, line) end)
  assert busiest(summary) == [Hit(count: 2, method: "GET", path: "/z"),
    Hit(count: 1, method: "GET", path: "/a"),
    Hit(count: 1, method: "POST", path: "/a"),
    Hit(count: 1, method: "GET", path: "/b")]
end

test rejects "a top of zero"
  empty(0, None)
end

test rejects "a top above one hundred"
  empty(101, None)
end

property "errors never outnumber requests, and requests are errors and successes, for any records"
  for records in any(List(Record))
    summary = records.reduce(empty(5, None), fn(s, r) added(s, r) end)
    assert summary.errors <= summary.requests
    assert summary.requests == summary.errors + summary.successes
    assert summary.requests == records.size
  end
end

verified: types, contracts, tests (8), property (200 seeds), sim (not run)
          proven: not run
