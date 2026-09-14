module Logstat.Stats
expose Summary, Busy, empty, folded, added, tallied, busiest, per_minute, error_rate

use Logstat.Parse{Record, parse_line}

intent "Fold a log into a summary one line at a time: requests, errors, and malformed lines counted, the span of time, the slowest requests kept to the top N, and a count per method and path, so no more than N records are ever held."

never "a summary's requests are not its errors plus its successes"
  for s in Summary.all
    s.requests != s.errors + s.successes or s.errors > s.requests
  end
end

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

struct Busy
  count: UInt64
  method: String
  path: String
end

# A summary of nothing that keeps the `top` slowest and busiest and ignores records before
# `since`.
fn empty(top: UInt64, since: Option(Time)) : Summary
  requires top >= 1 and top <= 100

  Summary(top: top, since: since, requests: 0, errors: 0, successes: 0, malformed: 0, first: None,
    last: None, slowest: [], hits: Map.new())
end

# One line of a log folded in: a record, or one more malformed line.
fn folded(summary: Summary, line: String) : Summary
  case parse_line(line)
    Ok(record): added(summary, record)
    Error(_):
      var next = summary
      next.malformed += 1
      next
  end
end

# One record counted, unless it is from before the summary's `since`. An error is a status
# 500 to 599; every other status is a success.
fn added(summary: Summary, record: Record) : Summary
  ensures result.requests <= summary.requests + 1
  ensures result.slowest.size <= summary.top or result.slowest == summary.slowest

  return summary if early?(summary.since, record.at)
  error = record.status >= 500
  var next = summary
  next.requests += 1
  next.errors += if error: 1 else: 0
  next.successes += if error: 0 else: 1
  next.first = Some(min_of(summary.first or record.at, record.at))
  next.last = Some(max_of(summary.last or record.at, record.at))
  next.slowest = kept(summary.slowest, record, summary.top)
  next.hits = next.hits.update((record.method, record.path), 0, fn(n) n + 1 end)
  next
end

fn early?(since: Option(Time), at: Time) : Bool
  case since
    Some(t): at < t
    None: false
  end
end

# The slowest list with the record in its place, cut to `top`: by duration descending, then
# time ascending, and a record that ties one already kept goes after it.
fn kept(slowest: List(Record), record: Record, top: UInt64) : List(Record)
  requires top >= 1

  place = slowest.count(fn(r) !slower?(record, r) end)
  return slowest if place >= top
  slowest.take(place).push(record).concat(slowest.drop(place)).take(top)
end

fn slower?(a: Record, b: Record) : Bool
  a.ms > b.ms or (a.ms == b.ms and a.at < b.at)
end

fn tallied(records: List(Record), top: UInt64) : Summary
  requires top >= 1 and top <= 100

  records.reduce(empty(top, None), fn(s, r) added(s, r) end)
end

# The `top` method and path pairs by count descending, then path ascending, then method
# ascending.
fn busiest(summary: Summary) : List(Busy)
  ensures result.size <= summary.top

  summary.hits.entries.map(fn(e)
    Busy(count: e.1, method: e.0.0, path: e.0.1)
  end).sort_by(fn(b) (b.path, b.method) end).sort_by_desc(fn(b) b.count end).take(summary.top)
end

# Requests divided by the minutes between the first and last timestamps; 0.0 when they are
# the same instant, as for a single request.
fn per_minute(summary: Summary) : Float64
  ensures result >= 0.0

  case (summary.first, summary.last)
    (Some(first), Some(last)):
      minutes = (last - first).minutes
      if minutes > 0.0: summary.requests.to_f64 / minutes else: 0.0
    _: 0.0
  end
end

fn error_rate(summary: Summary) : Float64
  ensures result >= 0.0 and result <= 1.0

  if summary.requests == 0: 0.0 else: summary.errors.to_f64 / summary.requests.to_f64
end

fn at(text: String) : Time
  Time.parse(text) or Time.from_parts(2000, 1, 1, 0, 0, 0)
end

fn record(stamp: String, method: String, path: String, status: UInt16, ms: UInt32) : Record
  Record(at: at(stamp), method: method, path: path, status: status, ms: ms)
end

test "requests, errors, successes, and malformed lines are counted"
  lines = ["2026-09-12T10:00:01Z GET /api/users 200 12",
    "2026-09-12T10:00:02Z POST /api/orders 500 340",
    "not a log line",
    "2026-09-12T10:00:03Z GET /api/users 404 7",
    "2026-09-12T10:00:04Z GET /api/users 599 9",
    ""]
  s = lines.reduce(empty(5, None), fn(so_far, line) folded(so_far, line) end)
  assert s.requests == 4
  assert s.errors == 2
  assert s.successes == 2
  assert s.malformed == 2
  assert error_rate(s) == 0.5
  assert error_rate(empty(5, None)) == 0.0
end

test "per minute is requests over the minutes from first to last, and a single request is 0.0"
  two = [record("2026-09-12T10:00:00Z", "GET", "/", 200, 1),
    record("2026-09-12T10:01:30Z", "GET", "/", 200, 1),
    record("2026-09-12T10:00:30Z", "GET", "/", 200, 1)]
  assert per_minute(tallied(two, 5)) == 2.0
  assert tallied(two, 5).first == Some(at("2026-09-12T10:00:00Z"))
  assert tallied(two, 5).last == Some(at("2026-09-12T10:01:30Z"))
  assert per_minute(tallied([record("2026-09-12T10:00:00Z", "GET", "/", 200, 1)], 5)) == 0.0
  assert per_minute(empty(5, None)) == 0.0
end

test "the slowest are kept to top, by duration descending, then time ascending"
  records = [record("2026-09-12T10:00:05Z", "GET", "/e", 200, 10),
    record("2026-09-12T10:00:04Z", "GET", "/d", 200, 30),
    record("2026-09-12T10:00:03Z", "GET", "/c", 200, 20),
    record("2026-09-12T10:00:02Z", "GET", "/b", 200, 30),
    record("2026-09-12T10:00:01Z", "GET", "/a", 200, 5),
    record("2026-09-12T10:00:02Z", "GET", "/tie", 200, 30)]
  s = tallied(records, 3)
  assert s.slowest.map(fn(r) r.path end) == ["/b", "/tie", "/d"]
  assert tallied(records, 100).slowest.map(fn(r) r.path end) == ["/b",
    "/tie",
    "/d",
    "/c",
    "/e",
    "/a"]
end

test "the busiest are by count descending, then path ascending, and kept to top"
  records = [record("2026-09-12T10:00:01Z", "GET", "/b", 200, 1),
    record("2026-09-12T10:00:02Z", "GET", "/c", 200, 1),
    record("2026-09-12T10:00:03Z", "POST", "/a", 200, 1),
    record("2026-09-12T10:00:04Z", "GET", "/c", 200, 1),
    record("2026-09-12T10:00:05Z", "GET", "/a", 200, 1)]
  assert busiest(tallied(records, 5)) == [Busy(count: 2, method: "GET", path: "/c"),
    Busy(count: 1, method: "GET", path: "/a"),
    Busy(count: 1, method: "POST", path: "/a"),
    Busy(count: 1, method: "GET", path: "/b")]
  assert busiest(tallied(records, 2)).size == 2
end

test "records before since are ignored, and one at since is counted"
  since = Some(at("2026-09-12T10:00:02Z"))
  s = empty(5, since)
  one = added(added(s, record("2026-09-12T10:00:01Z", "GET", "/a", 500, 1)),
    record("2026-09-12T10:00:02Z", "GET", "/b", 200, 1))
  assert one.requests == 1
  assert one.errors == 0
  assert busiest(one) == [Busy(count: 1, method: "GET", path: "/b")]
end

test rejects "a summary that keeps the top 0"
  empty(0, None)
end

test rejects "a summary that keeps the top 101"
  tallied([], 101)
end

test rejects "a slowest list cut to nothing"
  kept([], record("2026-09-12T10:00:01Z", "GET", "/a", 200, 1), 0)
end

property "errors are never more than requests, for any list of records"
  for records in any(List(Record)), top in any(UInt8) if top >= 1 and top <= 100
    s = tallied(records, top.to_u64)
    assert s.errors <= s.requests
    assert s.requests == s.errors + s.successes
    assert s.slowest.size <= top.to_u64
  end
end

verified: types, contracts, tests (9), property (200 seeds), sim (not run)
          proven: not run
