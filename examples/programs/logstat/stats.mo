module Logstat.Stats
expose Top, Count, Tally, Summary, start, add, add_malformed, summarize, rate, per_minute_tenths

use Logstat.Parse{Millis, Record, Status}

intent "Fold records into a tally one at a time, then summarize it: counts, rates, the slowest requests, and the busiest paths."

type Top = UInt64 where value >= 1 and value <= 100

struct Count
  method: String
  path: String
  count: UInt64
end

struct Tally
  top: Top
  since: UInt64
  errors: UInt64
  successes: UInt64
  malformed: UInt64
  first: UInt64
  last: UInt64
  slowest: List(Record)
  busiest: List(Count)
end

struct Summary
  requests: UInt64
  errors: UInt64
  successes: UInt64
  malformed: UInt64
  error_permille: UInt64
  per_minute_tenths: UInt64
  slowest: List(Record)
  busiest: List(Count)
end

fn start(top: Top, since: UInt64) : Tally
  ensures result.errors + result.successes + result.malformed == 0

  Tally(top: top, since: since, errors: 0, successes: 0, malformed: 0,
    first: 18_446_744_073_709_551_615, last: 0, slowest: [], busiest: [])
end

fn add(tally: Tally, record: Record) : Tally
  ensures result.errors + result.successes <= tally.errors + tally.successes + 1
  ensures result.slowest.size <= tally.top

  return tally if record.seconds < tally.since
  var next = tally
  if record.status >= 500
    next.errors += 1
  else
    next.successes += 1
  end
  next.first = least(tally.first, record.seconds)
  next.last = most(tally.last, record.seconds)
  next.slowest = kept_slowest(tally.slowest, record, tally.top)
  next.busiest = counted(tally.busiest, record)
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
  Summary(requests: requests, errors: tally.errors, successes: tally.successes,
    malformed: tally.malformed, error_permille: rate(tally.errors, requests, 1_000),
    per_minute_tenths: per_minute_tenths(requests, tally.first, tally.last), slowest: tally.slowest,
    busiest: ranked(tally.busiest, tally.top))
end

# part / whole in units of 1 / scale, rounded half up; nothing out of nothing is 0.
fn rate(part: UInt64, whole: UInt64, scale: UInt64) : UInt64
  requires part <= whole

  return 0 if whole == 0
  (part * scale + whole / 2) / whole
end

# Requests per minute in tenths: requests over the span from first to last in minutes.
# One request, or every request in the same second, is 0.
fn per_minute_tenths(requests: UInt64, first: UInt64, last: UInt64) : UInt64
  requires requests == 0 or first <= last

  return 0 if requests == 0 or first == last
  span = last - first
  (requests * 600 + span / 2) / span
end

fn slower?(a: Record, b: Record) : Bool
  a.ms > b.ms or (a.ms == b.ms and a.seconds < b.seconds)
end

# The slowest records, slowest first, at most top of them. A record ties behind the ones
# already kept, so the order is stable.
fn kept_slowest(slowest: List(Record), record: Record, top: Top) : List(Record)
  ensures result.size <= top

  placed = slowest.reduce(([], false), fn(acc, kept)
    if !acc.1 and slower?(record, kept)
      (acc.0.push(record).push(kept), true)
    else
      (acc.0.push(kept), acc.1)
    end
  end)
  all = if placed.1
    placed.0
  else
    placed.0.push(record)
  end
  first_n(all, top)
end

fn counted(busiest: List(Count), record: Record) : List(Count)
  ensures total(result) == total(busiest) + 1

  seen = busiest.filter(fn(c) c.method == record.method and c.path == record.path end)
  return busiest.push(Count(method: record.method, path: record.path, count: 1)) if seen.size == 0
  busiest.map(fn(c)
    if c.method == record.method and c.path == record.path
      Count(method: c.method, path: c.path, count: c.count + 1)
    else
      c
    end
  end)
end

fn total(counts: List(Count)) : UInt64
  counts.reduce(0, fn(sum, c) sum + c.count end)
end

fn busier?(a: Count, b: Count) : Bool
  return a.count > b.count if a.count != b.count
  return a.path < b.path if a.path != b.path
  a.method < b.method
end

# Busiest first: count descending, then path ascending, then method ascending.
fn ranked(counts: List(Count), top: Top) : List(Count)
  ensures result.size <= top

  sorted = counts.reduce([], fn(acc, c) inserted(acc, c) end)
  first_n(sorted, top)
end

fn inserted(sorted: List(Count), count: Count) : List(Count)
  ensures result.size == sorted.size + 1

  placed = sorted.reduce(([], false), fn(acc, kept)
    if !acc.1 and busier?(count, kept)
      (acc.0.push(count).push(kept), true)
    else
      (acc.0.push(kept), acc.1)
    end
  end)
  return placed.0 if placed.1
  placed.0.push(count)
end

fn first_n(xs: List(T), n: UInt64) : List(T)
  ensures result.size <= n

  taken = xs.reduce((0, []), fn(acc, x)
    if acc.0 < n
      (acc.0 + 1, acc.1.push(x))
    else
      acc
    end
  end)
  taken.1
end

fn least(a: UInt64, b: UInt64) : UInt64
  return a if a < b
  b
end

fn most(a: UInt64, b: UInt64) : UInt64
  return a if a > b
  b
end

fn sample(seconds: UInt64, method: String, path: String, status: Status, ms: Millis) : Record
  Record(at: "t#{seconds}", seconds: seconds, method: method, path: path, status: status, ms: ms)
end

test "requests split into errors and successes, and malformed lines are counted apart"
  var tally = start(5, 0)
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
  assert summary.error_permille == 500
end

test "per minute is requests over the span in minutes, and one request is 0.0"
  assert per_minute_tenths(1_204, 0, 1_800) == 401
  assert per_minute_tenths(1, 60, 60) == 0
  assert per_minute_tenths(0, 18_446_744_073_709_551_615, 0) == 0
  assert per_minute_tenths(3, 0, 120) == 15
  assert rate(37, 1_204, 1_000) == 31
  assert rate(0, 0, 1_000) == 0
end

test "slowest keeps the top N by duration, then by timestamp"
  var tally = start(3, 0)
  tally = add(tally, sample(5, "GET", "/late", 200, 340))
  tally = add(tally, sample(1, "GET", "/fast", 200, 2))
  tally = add(tally, sample(2, "POST", "/early", 500, 340))
  tally = add(tally, sample(9, "GET", "/slowest", 200, 1_204))
  tally = add(tally, sample(3, "GET", "/middle", 200, 88))
  paths = summarize(tally).slowest.map(fn(r) r.path end)
  assert paths == ["/slowest", "/early", "/late"]
end

test "busiest ranks by count, then path, then method, and keeps the top N"
  var tally = start(2, 0)
  tally = add(tally, sample(1, "GET", "/b", 200, 1))
  tally = add(tally, sample(2, "POST", "/a", 200, 1))
  tally = add(tally, sample(3, "GET", "/a", 200, 1))
  tally = add(tally, sample(4, "GET", "/c", 200, 1))
  tally = add(tally, sample(5, "GET", "/c", 200, 1))
  busiest = summarize(tally).busiest
  assert busiest == [Count(method: "GET", path: "/c", count: 2), Count(method: "GET", path: "/a",
    count: 1)]
end

test "a record before since is not counted"
  var tally = start(5, 100)
  tally = add(tally, sample(99, "GET", "/a", 500, 10))
  tally = add(tally, sample(100, "GET", "/a", 200, 10))
  summary = summarize(tally)
  assert summary.requests == 1
  assert summary.errors == 0
end

test rejects "a part larger than its whole"
  rate(3, 2, 1_000)
end

test rejects "a span whose last second comes before its first"
  per_minute_tenths(2, 60, 0)
end

test rejects "a top of zero"
  start(0, 0)
end

test rejects "a top above one hundred"
  start(101, 0)
end

property "errors never exceed requests, for any list of records"
  for records in any(List(Record))
    summary = summarize(records.reduce(start(100, 0), fn(tally, r) add(tally, r) end))
    assert summary.errors <= summary.requests
    assert summary.requests == records.size
  end
end
