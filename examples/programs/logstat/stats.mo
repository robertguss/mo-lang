module Logstat.Stats
expose Top, Count, Tally, Summary, start, add, add_malformed, summarize, rate, per_minute

use Logstat.Parse{Record, Status}

intent "Fold records into a tally one at a time, then summarize it: counts, rates, the slowest requests, and the busiest paths."

type Top = UInt64 where value >= 1 and value <= 100

struct Count
  count: UInt64
  method: String
  path: String
end

struct Tally
  top: Top
  since: Option(Time)
  errors: UInt64
  successes: UInt64
  malformed: UInt64
  first: Option(Time)
  last: Option(Time)
  slowest: List(Record)
  counts: Map((String, String), UInt64)
end

struct Summary
  requests: UInt64
  errors: UInt64
  successes: UInt64
  malformed: UInt64
  error_rate: Float64
  per_minute: Float64
  slowest: List(Record)
  busiest: List(Count)
end

fn start(top: Top, since: Option(Time)) : Tally
  ensures result.errors + result.successes + result.malformed == 0

  Tally(top: top, since: since, errors: 0, successes: 0, malformed: 0, first: None, last: None,
    slowest: [], counts: Map.new())
end

fn add(tally: Tally, record: Record) : Tally
  ensures result.errors + result.successes <= tally.errors + tally.successes + 1
  ensures result.slowest.size <= tally.top

  # With no since, a record is never before it.
  return tally if record.at < (tally.since or record.at)
  var next = tally
  if record.status >= 500
    next.errors += 1
  else
    next.successes += 1
  end
  next.first = [tally.first or record.at, record.at].min
  next.last = [tally.last or record.at, record.at].max
  next.slowest = kept_slowest(tally.slowest, record, tally.top)
  next.counts = tally.counts.update((record.method, record.path), 0, fn(n) n + 1 end)
  next
end

fn add_malformed(tally: Tally) : Tally
  ensures result.malformed == tally.malformed + 1

  var next = tally
  next.malformed += 1
  next
end

fn summarize(tally: Tally) : Summary
  ensures result.requests == result.errors + result.successes
  ensures result.errors <= result.requests
  ensures result.slowest.size <= tally.top and result.busiest.size <= tally.top

  requests = tally.errors + tally.successes
  first = tally.first or Time.from_parts(1970, 1, 1, 0, 0, 0)
  last = tally.last or first
  Summary(requests: requests, errors: tally.errors, successes: tally.successes,
    malformed: tally.malformed, error_rate: rate(tally.errors, requests),
    per_minute: per_minute(requests, first, last), slowest: tally.slowest,
    busiest: ranked(tally.counts, tally.top))
end

# part / whole; nothing out of nothing is 0.
fn rate(part: UInt64, whole: UInt64) : Float64
  requires part <= whole

  return 0.0 if whole == 0
  part.to_f64 / whole.to_f64
end

# Requests per minute over the span from the first timestamp to the last. One request, or
# every request in the same instant, is 0.
fn per_minute(requests: UInt64, first: Time, last: Time) : Float64
  requires first <= last

  minutes = last.since(first).minutes
  return 0.0 if requests == 0 or minutes == 0.0
  requests.to_f64 / minutes
end

# Slowest first, and at one duration the earlier first.
fn slow_key(r: Record) : (UInt32, Time)
  (4_294_967_295 - r.ms, r.at)
end

# The slowest records, at most top of them. A record ties behind the ones already kept, so
# the order is stable.
fn kept_slowest(slowest: List(Record), record: Record, top: Top) : List(Record)
  ensures result.size <= top

  if slowest.size >= top and slowest.last is Some(least)
    return slowest if !(slow_key(record) < slow_key(least))
  end
  slowest.push(record).sort_by(fn(r) slow_key(r) end).take(top)
end

# Busiest first: count descending, then path ascending, then method ascending.
fn ranked(counts: Map((String, String), UInt64), top: Top) : List(Count)
  ensures result.size <= top

  sorted = counts.entries.sort_by(fn(e) (18_446_744_073_709_551_615 - e.1, e.0.1, e.0.0) end)
  sorted.take(top).map(fn(e) Count(count: e.1, method: e.0.0, path: e.0.1) end)
end

fn sample(second: UInt64, method: String, path: String, status: Status, ms: UInt32) : Record
  at = Time.from_parts(2026, 1, 1, 0, 0, 0) + (second * 1_000).ms
  Record(at: at, method: method, path: path, status: status, ms: ms)
end

test "requests split into errors and successes, and malformed lines are counted apart"
  var tally = start(5, None)
  tally = add(tally, sample(0, "GET", "/a", 200, 10))
  tally = add(tally, sample(1, "GET", "/a", 500, 10))
  tally = add(tally, sample(2, "GET", "/a", 599, 10))
  tally = add(tally, sample(3, "GET", "/a", 499, 10))
  tally = add_malformed(tally)
  summary = summarize(tally)
  assert summary.requests == 4
  assert summary.errors == 2
  assert summary.successes == 2
  assert summary.malformed == 1
  assert summary.error_rate == 0.5
end

test "per minute is requests over the span in minutes, and one request is 0.0"
  t = Time.from_parts(2026, 9, 12, 10, 0, 0)
  assert per_minute(1_204, t, t + 1_800_000.ms).to_string(1) == "40.1"
  assert per_minute(1, t, t) == 0.0
  assert per_minute(3, t, t + 120_000.ms) == 1.5
  assert rate(37, 1_204).round(3) == 0.031
  assert rate(0, 0) == 0.0
end

test "slowest keeps the top N by duration, then by timestamp"
  var tally = start(3, None)
  tally = add(tally, sample(5, "GET", "/late", 200, 340))
  tally = add(tally, sample(1, "GET", "/fast", 200, 2))
  tally = add(tally, sample(2, "POST", "/early", 500, 340))
  tally = add(tally, sample(9, "GET", "/slowest", 200, 1_204))
  tally = add(tally, sample(3, "GET", "/middle", 200, 88))
  paths = summarize(tally).slowest.map(fn(r) r.path end)
  assert paths == ["/slowest", "/early", "/late"]
end

test "busiest ranks by count, then path, then method, and keeps the top N"
  var tally = start(2, None)
  tally = add(tally, sample(1, "GET", "/b", 200, 1))
  tally = add(tally, sample(2, "POST", "/a", 200, 1))
  tally = add(tally, sample(3, "GET", "/a", 200, 1))
  tally = add(tally, sample(4, "GET", "/c", 200, 1))
  tally = add(tally, sample(5, "GET", "/c", 200, 1))
  busiest = summarize(tally).busiest
  assert busiest == [Count(count: 2, method: "GET", path: "/c"), Count(count: 1, method: "GET",
    path: "/a")]
end

test "a record before since is not counted"
  var tally = start(5, Some(Time.from_parts(2026, 1, 1, 0, 1, 40)))
  tally = add(tally, sample(99, "GET", "/a", 500, 10))
  tally = add(tally, sample(100, "GET", "/a", 200, 10))
  summary = summarize(tally)
  assert summary.requests == 1
  assert summary.errors == 0
end

test rejects "a part larger than its whole"
  rate(3, 2)
end

test rejects "a span whose last instant comes before its first"
  per_minute(2, Time.fixture() + 60_000.ms, Time.fixture())
end

test rejects "a top of zero"
  start(0, None)
end

test rejects "a top above one hundred"
  start(101, None)
end

property "errors never exceed requests, for any list of records"
  for records in any(List(Record))
    summary = summarize(records.reduce(start(100, None), fn(tally, r) add(tally, r) end))
    assert summary.errors <= summary.requests
    assert summary.requests == records.size
  end
end

verified: types, contracts, tests (10), property (200 seeds), sim (not run)
          proven: not run
