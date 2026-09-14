module Logstat.Stats
expose Top, Tally, Hit, Summary, fresh, counted_line, counted, summarized, summary_of, error?, rate, per_minute

use Logstat.Parse{Record, parse_line}

intent "Fold log lines, one at a time and across files, into a tally that keeps only the slowest records it will show and a count per method and path, and turn the tally into a summary: requests, errors and their rate, malformed lines, requests per minute, the slowest records, and the busiest paths."

never "a summary's requests are not its errors plus its successes"
  for s in Summary.all
    s.requests != s.errors + s.successes
  end
end

never "a summary counts more errors than requests"
  for s in Summary.all
    s.errors > s.requests
  end
end

# How many slowest records and busiest paths a summary shows.
type Top = UInt64 where value >= 1 and value <= 100

# What has been read so far. slowest holds at most top records, in the order they are shown.
struct Tally
  errors: UInt64
  successes: UInt64
  malformed: UInt64
  first: Option(Time)
  last: Option(Time)
  slowest: List(Record)
  hits: Map(String, Hit)
end

# How many requests one method and path had.
struct Hit
  count: UInt64
  method: String
  path: String
end

struct Summary
  requests: UInt64
  errors: UInt64
  successes: UInt64
  malformed: UInt64
  error_rate: Float64
  per_minute: Float64
  slowest: List(Record)
  busiest: List(Hit)
end

fn fresh() : Tally
  Tally(errors: 0, successes: 0, malformed: 0, first: None, last: None, slowest: [],
    hits: Map.new())
end

# A malformed line is counted, a line before since is left out, and every other line is a request.
fn counted_line(tally: Tally, line: String, since: Option(Time), top: Top) : Tally
  case parse_line(line)
    Ok(record):
      return tally if before?(record, since)
      counted(tally, record, top)
    Error(_): with_malformed(tally)
  end
end

fn before?(record: Record, since: Option(Time)) : Bool
  case since
    Some(t): record.at < t
    None: false
  end
end

fn with_malformed(tally: Tally) : Tally
  var next = tally
  next.malformed = tally.malformed + 1
  next
end

# Errors are statuses 500 to 599.
fn error?(record: Record) : Bool
  record.status >= 500
end

fn counted(tally: Tally, record: Record, top: Top) : Tally
  ensures result.errors + result.successes == tally.errors + tally.successes + 1

  var next = tally
  if error?(record)
    next.errors = tally.errors + 1
  else
    next.successes = tally.successes + 1
  end
  next.first = Some(earliest(tally.first, record.at))
  next.last = Some(latest(tally.last, record.at))
  next.slowest = kept(tally.slowest, record, top)
  next.hits = tally.hits.update("#{record.method} #{record.path}",
    Hit(count: 0, method: record.method, path: record.path), fn(hit) bumped(hit) end)
  next
end

fn earliest(so_far: Option(Time), at: Time) : Time
  case so_far
    Some(t): min_of(t, at)
    None: at
  end
end

fn latest(so_far: Option(Time), at: Time) : Time
  case so_far
    Some(t): max_of(t, at)
    None: at
  end
end

fn bumped(hit: Hit) : Hit
  var next = hit
  next.count = hit.count + 1
  next
end

# The slowest records kept so far with one more read: a record no slower than the last of a full
# list is left out, so of two that tie the one read first stays.
fn kept(slowest: List(Record), record: Record, top: Top) : List(Record)
  if slowest.size >= top and slowest.last is Some(last)
    return slowest if !slower?(record, last)
  end
  ranked(slowest.push(record)).take(top)
end

fn slower?(a: Record, b: Record) : Bool
  a.duration_ms > b.duration_ms or (a.duration_ms == b.duration_ms and a.at < b.at)
end

# Duration descending, then timestamp ascending; records that tie on both keep their order.
fn ranked(records: List(Record)) : List(Record)
  records.sort_by(fn(r) r.at end).sort_by_desc(fn(r) r.duration_ms end)
end

fn summarized(records: List(Record), top: Top) : Summary
  summary_of(records.reduce(fresh(), fn(tally, r) counted(tally, r, top) end), top)
end

fn summary_of(tally: Tally, top: Top) : Summary
  ensures result.requests == result.errors + result.successes and result.errors <= result.requests

  requests = tally.errors + tally.successes
  Summary(requests: requests, errors: tally.errors, successes: tally.successes,
    malformed: tally.malformed, error_rate: rate(tally.errors, requests),
    per_minute: per_minute(requests, tally.first, tally.last), slowest: tally.slowest,
    busiest: busiest(tally.hits.values, top))
end

# Count descending, then path ascending, then method ascending; hits that tie on all three keep
# the order they were first seen.
fn busiest(hits: List(Hit), top: Top) : List(Hit)
  hits.sort_by(fn(h) (h.path, h.method) end).sort_by_desc(fn(h) h.count end).take(top)
end

fn rate(errors: UInt64, requests: UInt64) : Float64
  requires errors <= requests

  return 0.0 if requests == 0
  errors.to_f64 / requests.to_f64
end

# Requests over the minutes from the first timestamp to the last; 0.0 when there is no span, as
# for a single request.
fn per_minute(requests: UInt64, first: Option(Time), last: Option(Time)) : Float64
  span = span_minutes(first, last)
  return 0.0 if span == 0.0
  requests.to_f64 / span
end

fn span_minutes(first: Option(Time), last: Option(Time)) : Float64
  case (first, last)
    (Some(from), Some(to)): to.since(from).minutes
    _: 0.0
  end
end

fn at(second: UInt64) : Time
  Time.from_parts(2026, 9, 12, 10, 0, 0) + (second * 1_000).ms
end

fn record(second: UInt64, path: String, status: UInt64, ms: UInt32) : Record
  Record(at: at(second), method: "GET", path: path, status: status.to_u16, duration_ms: ms)
end

fn sample() : List(Record)
  [record(0, "/a", 200, 12),
    record(30, "/b", 500, 340),
    record(60, "/a", 200, 340),
    record(90, "/c", 503, 7),
    record(120, "/b", 200, 9)]
end

test "requests, errors, and their rate are counted over the records"
  s = summarized(sample(), 5)
  assert s.requests == 5 and s.errors == 2 and s.successes == 3 and s.malformed == 0
  assert s.error_rate == 0.4
  assert summarized([], 5).error_rate == 0.0
end

test "per minute is requests over the span from the first timestamp to the last"
  assert summarized(sample(), 5).per_minute == 2.5
  assert summarized([record(0, "/a", 200, 1)], 5).per_minute == 0.0
  assert summarized([record(9, "/a", 200, 1), record(9, "/b", 200, 1)], 5).per_minute == 0.0
  assert summarized([], 5).per_minute == 0.0
  assert per_minute(3, Some(at(0)), Some(at(120))) == 1.5
end

test "the slowest are by duration descending, then timestamp ascending, at most top"
  paths = summarized(sample(), 5).slowest.map(fn(r) r.path end)
  assert paths == ["/b", "/a", "/a", "/b", "/c"]
  assert summarized(sample(), 2).slowest.map(fn(r) r.at end) == [at(30), at(60)]
  assert summarized(sample().reverse, 2).slowest.map(fn(r) r.at end) == [at(30), at(60)]
end

test "the busiest are by count descending, then path ascending, at most top"
  hits = summarized(sample(), 5).busiest
  assert hits.map(fn(h) (h.count, h.path) end) == [(2, "/a"), (2, "/b"), (1, "/c")]
  assert summarized(sample().reverse, 1).busiest.map(fn(h) h.path end) == ["/a"]
end

test "a malformed line is counted, and a line before since is left out"
  lines = ["2026-09-12T10:00:01Z GET /a 200 12",
    "not a line",
    "2026-09-12T09:59:59Z GET /b 500 3",
    ""]
  var tally = fresh()
  tally = lines.reduce(tally, fn(so_far, line) counted_line(so_far, line, Some(at(0)), 5) end)
  s = summary_of(tally, 5)
  assert s.requests == 1 and s.errors == 0 and s.malformed == 2
  everything = lines.reduce(fresh(), fn(so_far, line) counted_line(so_far, line, None, 5) end)
  assert summary_of(everything, 5).requests == 2
end

test rejects "an error rate with more errors than requests"
  rate(3, 2)
end

test rejects "a top of none"
  summarized(sample(), 0)
end

test rejects "a top past one hundred"
  summarized(sample(), 101)
end

property "a summary of any records counts every one, and never more errors than requests"
  for records in any(List(Record))
    s = summarized(records, 5)
    assert s.errors <= s.requests
    assert s.requests == records.size
  end
end

property "the slowest kept one record at a time are the slowest of them all"
  for records in any(List(Record)), top in any(Top)
    assert summarized(records, top).slowest == ranked(records).take(top)
  end
end

verified: types, contracts, tests (10), property (200 seeds), sim (not run)
          proven: not run
