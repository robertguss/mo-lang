module Logstat.Stats
expose Slow, Busy, Tally, Summary, empty_tally, add_lines, tallied, summarize, error_rate, per_minute

use Logstat.Parse{Record, Malformed, parse_line}

intent "Fold one file's lines at a time into a running tally, and turn the tally into the summary a report prints."

never "a tally's requests are not its errors plus its successes"
  for t in Tally.all
    t.errors > t.requests or t.requests != t.errors + t.successes
  end
end

struct Slow
  ms: UInt32
  method: String
  path: String
  at: Time
end

struct Busy
  count: UInt64
  method: String
  path: String
end

struct Tally
  requests: UInt64
  errors: UInt64
  successes: UInt64
  malformed: UInt64
  first: Option(Time)
  last: Option(Time)
  slowest: List(Slow)
  hits: Map((String, String), UInt64)
end

struct Summary
  requests: UInt64
  errors: UInt64
  error_rate: Float64
  malformed: UInt64
  per_minute: Float64
  slowest: List(Slow)
  busiest: List(Busy)
end

fn empty_tally() : Tally
  Tally(requests: 0, errors: 0, successes: 0, malformed: 0, first: None, last: None, slowest: [],
    hits: Map.new())
end

# One file's lines into the tally: a malformed line is counted, a line before since is dropped.
fn add_lines(tally: Tally, lines: List(String), since: Option(Time)) : Tally
  parsed = lines.map(fn(line) parse_line(line) end)
  records = parsed.flat_map(fn(p) record_list(p) end).filter(fn(r) kept?(r, since) end)
  var next = added(tally, records)
  next.malformed = tally.malformed + parsed.count(fn(p) p is Error(_) end)
  next
end

fn tallied(records: List(Record)) : Tally
  added(empty_tally(), records)
end

fn record_list(parsed: Result(Record, Malformed)) : List(Record)
  case parsed
    Ok(r): [r]
    Error(_): []
  end
end

fn kept?(r: Record, since: Option(Time)) : Bool
  case since
    Some(t): r.at >= t
    None: true
  end
end

# The slowest list never needs more than the largest --top, so it keeps 100.
fn added(tally: Tally, records: List(Record)) : Tally
  var next = records.reduce(tally, fn(so_far, r) counted(so_far, r) end)
  next.slowest = slowest_first(tally.slowest.concat(records.map(fn(r) slow(r) end))).take(100)
  next
end

fn counted(t: Tally, r: Record) : Tally
  e = error_count(r)
  Tally(requests: t.requests + 1, errors: t.errors + e, successes: t.successes + 1 - e,
    malformed: t.malformed, first: [t.first or r.at, r.at].min, last: [t.last or r.at, r.at].max,
    slowest: t.slowest, hits: hit(t.hits, (r.method, r.path)))
end

fn hit(hits: Map((String, String), UInt64), key: (String, String)) : Map((String, String), UInt64)
  hits.update(key, 0, fn(c) c + 1 end)
end

fn error_count(r: Record) : UInt64
  return 1 if r.status >= 500 and r.status <= 599
  0
end

fn slow(r: Record) : Slow
  Slow(ms: r.duration_ms, method: r.method, path: r.path, at: r.at)
end

# Duration descending, then timestamp ascending; the sort is stable, so equal rows keep file order.
fn slowest_first(rows: List(Slow)) : List(Slow)
  rows.sort_by(fn(s) (4_294_967_295 - s.ms, s.at) end)
end

# Count descending, then path ascending, then method ascending.
fn busiest(hits: Map((String, String), UInt64), top: UInt64) : List(Busy)
  rows = hits.entries.map(fn(entry) busy(entry) end)
  rows.sort_by(fn(b) (18_446_744_073_709_551_615 - b.count, b.path, b.method) end).take(top)
end

fn busy(entry: ((String, String), UInt64)) : Busy
  case entry
    ((method, path), count): Busy(count: count, method: method, path: path)
  end
end

fn summarize(tally: Tally, top: UInt64) : Summary
  requires top >= 1 and top <= 100
  ensures result.errors <= result.requests

  share = error_rate(tally.errors, tally.requests)
  pace = per_minute(tally.requests, tally.first, tally.last)
  Summary(requests: tally.requests, errors: tally.errors, error_rate: share,
    malformed: tally.malformed, per_minute: pace, slowest: tally.slowest.take(top),
    busiest: busiest(tally.hits, top))
end

fn error_rate(errors: UInt64, requests: UInt64) : Float64
  requires errors <= requests

  return 0.0 if requests == 0
  (errors.to_f64 / requests.to_f64).round(3)
end

fn per_minute(requests: UInt64, first: Option(Time), last: Option(Time)) : Float64
  case (first, last)
    (Some(a), Some(b)): rate(requests, b.since(a).minutes)
    _: 0.0
  end
end

# Requests over a span in minutes; a span of nothing, such as a single request, is 0.0.
fn rate(requests: UInt64, minutes: Float64) : Float64
  requires minutes >= 0.0

  return 0.0 if minutes == 0.0
  (requests.to_f64 / minutes).round(1)
end

test "requests, errors, and malformed lines are counted"
  log = """
  2026-09-12T10:00:00Z GET /a 200 10
  2026-09-12T10:00:30Z POST /b 500 40
  not a log line
  2026-09-12T10:01:00Z GET /a 404 20
  2026-09-12T10:02:00Z GET /a 599 5
  """
  summary = summarize(add_lines(empty_tally(), log.lines, None), 5)
  assert summary.requests == 4
  assert summary.errors == 2
  assert summary.malformed == 1
  assert summary.error_rate == 0.5
  assert summary.per_minute == 2.0
end

test "per minute is requests over the span in minutes, and one request is 0.0"
  first = Some(Time.from_parts(2026, 9, 12, 10, 0, 0))
  assert per_minute(3, first, Some(Time.from_parts(2026, 9, 12, 10, 0, 45))) == 4.0
  assert per_minute(1, first, first) == 0.0
  assert per_minute(0, None, None) == 0.0
  assert error_rate(1, 3) == 0.333
  assert error_rate(0, 0) == 0.0
end

test "slowest is by duration descending, then timestamp ascending"
  log = """
  2026-09-12T10:00:03Z GET /c 200 7
  2026-09-12T10:00:02Z GET /b 200 9
  2026-09-12T10:00:01Z GET /a 200 7
  2026-09-12T10:00:04Z GET /d 200 1
  """
  summary = summarize(add_lines(empty_tally(), log.lines, None), 3)
  assert summary.slowest.map(fn(s) s.path end) == ["/b", "/a", "/c"]
  assert summary.slowest.first is Some(top)
  assert top == Slow(ms: 9, method: "GET", path: "/b", at: Time.from_parts(2026, 9, 12, 10, 0, 2))
end

test "busiest is by count descending, then path ascending"
  log = """
  2026-09-12T10:00:01Z GET /z 200 1
  2026-09-12T10:00:02Z GET /b 200 1
  2026-09-12T10:00:03Z GET /z 200 1
  2026-09-12T10:00:04Z GET /a 200 1
  2026-09-12T10:00:05Z POST /b 200 1
  2026-09-12T10:00:06Z GET /b 200 1
  """
  summary = summarize(add_lines(empty_tally(), log.lines, None), 3)
  shown = summary.busiest.map(fn(b) "#{b.count} #{b.method} #{b.path}" end)
  assert shown == ["2 GET /b", "2 GET /z", "1 GET /a"]
end

test "a tally carries across files, and since drops only well-formed lines before it"
  since = Time.parse("2026-09-12T10:00:02Z")
  once = add_lines(empty_tally(), ["2026-09-12T10:00:01Z GET /a 500 1", "garbage"], since)
  twice = add_lines(once, ["2026-09-12T10:00:02Z GET /a 200 3",
    "2026-09-12T10:00:09Z GET /a 503 2"], since)
  summary = summarize(twice, 5)
  assert summary.requests == 2
  assert summary.errors == 1
  assert summary.malformed == 1
  assert twice.successes == 1
  assert summary.busiest == [Busy(count: 2, method: "GET", path: "/a")]
end

test rejects "a top of zero"
  summarize(empty_tally(), 0)
end

test rejects "a top above one hundred"
  summarize(empty_tally(), 101)
end

test rejects "more errors than requests"
  error_rate(3, 2)
end

test rejects "a span that runs backwards"
  rate(3, 0.0 - 1.0)
end

property "errors never exceed requests, for any list of records"
  for records in any(List(Record))
    tally = tallied(records)
    assert tally.errors <= tally.requests
    assert tally.requests == tally.errors + tally.successes
  end
end
