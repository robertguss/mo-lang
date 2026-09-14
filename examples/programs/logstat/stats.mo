module Logstat.Stats
expose Busy, Tally, Summary, empty, counted, malformed_line, summary, error_rate, per_minute

use Logstat.Parse{Entry, entries}

intent "Fold entries one at a time into a tally that stays small however many lines go in, and read a summary off it: requests split into errors (500 to 599) and successes, malformed lines, the span from the earliest to the latest timestamp, the slowest entries, and the busiest method and path pairs."

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

# How many requests went to one method and path.
struct Busy
  count: UInt64
  method: String
  path: String
end

# The running count. slowest holds the slowest entries so far, fewer than ten times top of them;
# busy counts each method and path pair, keyed by "method path".
struct Tally
  top: UInt64
  requests: UInt64
  errors: UInt64
  successes: UInt64
  malformed: UInt64
  first: Option(Time)
  last: Option(Time)
  slowest: List(Entry)
  busy: Map(String, Busy)
end

# What the report prints: at most top slowest and top busiest, already in their order.
struct Summary
  requests: UInt64
  errors: UInt64
  successes: UInt64
  malformed: UInt64
  span: Duration
  slowest: List(Entry)
  busiest: List(Busy)
end

fn empty(top: UInt64) : Tally
  requires top >= 1 and top <= 100

  Tally(top: top, requests: 0, errors: 0, successes: 0, malformed: 0, first: None, last: None,
    slowest: [], busy: Map.new())
end

fn error?(status: UInt16) : Bool
  status >= 500 and status <= 599
end

fn counted(t: Tally, e: Entry) : Tally
  ensures result.requests == t.requests + 1
  ensures result.errors + result.successes == result.requests

  var next = t
  next.requests += 1
  if error?(e.status)
    next.errors += 1
  else
    next.successes += 1
  end
  next.first = Some(earlier(t.first, e.at))
  next.last = Some(later(t.last, e.at))
  next.slowest = kept(next.slowest.push(e), t.top)
  next.busy = next.busy.update("#{e.method} #{e.path}",
    Busy(count: 0, method: e.method, path: e.path), fn(b) bumped(b) end)
  next
end

fn malformed_line(t: Tally) : Tally
  ensures result.malformed == t.malformed + 1

  var next = t
  next.malformed += 1
  next
end

fn bumped(b: Busy) : Busy
  var next = b
  next.count += 1
  next
end

fn earlier(first: Option(Time), at: Time) : Time
  case first
    Some(so_far): min_of(so_far, at)
    None: at
  end
end

fn later(last: Option(Time), at: Time) : Time
  case last
    Some(so_far): max_of(so_far, at)
    None: at
  end
end

# The slowest entries, trimmed to top once ten times top have gathered.
fn kept(slowest: List(Entry), top: UInt64) : List(Entry)
  return slowest if slowest.size < top * 10
  ranked(slowest, top)
end

# By duration descending, then timestamp ascending; the sorts are stable, so ties keep file order.
fn ranked(slowest: List(Entry), n: UInt64) : List(Entry)
  slowest.sort_by(fn(e) e.at end).sort_by_desc(fn(e) e.duration_ms end).take(n)
end

# By count descending, then path ascending, then method ascending.
fn busiest(busy: Map(String, Busy), n: UInt64) : List(Busy)
  busy.values.sort_by(fn(b) (b.path, b.method) end).sort_by_desc(fn(b) b.count end).take(n)
end

fn span(first: Option(Time), last: Option(Time)) : Duration
  case (first, last)
    (Some(from), Some(to)): to - from
    _: 0.ms
  end
end

fn summary(t: Tally) : Summary
  ensures result.slowest.size <= t.top and result.busiest.size <= t.top
  ensures result.requests == t.requests

  Summary(requests: t.requests, errors: t.errors, successes: t.successes, malformed: t.malformed,
    span: span(t.first, t.last), slowest: ranked(t.slowest, t.top), busiest: busiest(t.busy, t.top))
end

# Errors as a share of requests, 0.0 with no requests.
fn error_rate(s: Summary) : Float64
  ensures result >= 0.0 and result <= 1.0

  return 0.0 if s.requests == 0
  s.errors.to_f64 / s.requests.to_f64
end

# Requests over the span in minutes, 0.0 when the span is nothing, as for a single request.
fn per_minute(s: Summary) : Float64
  return 0.0 if s.span <= 0.ms
  s.requests.to_f64 / s.span.minutes
end

test "requests split into errors and successes, and malformed lines are counted apart"
  lines = ["2026-09-12T10:00:01Z GET /a 200 1",
    "2026-09-12T10:00:02Z GET /a 500 1",
    "2026-09-12T10:00:03Z GET /a 599 1",
    "2026-09-12T10:00:04Z GET /a 404 1"]
  t = entries(lines).reduce(empty(5), fn(so_far, e) counted(so_far, e) end)
  s = summary(malformed_line(malformed_line(t)))
  assert s.requests == 4
  assert s.errors == 2
  assert s.successes == 2
  assert s.malformed == 2
  assert error_rate(s) == 0.5
end

test "the span runs from the earliest to the latest timestamp in any order, and a single request is 0.0 per minute"
  lines = ["2026-09-12T10:01:00Z GET /a 200 1",
    "2026-09-12T10:00:00Z GET /a 200 1",
    "2026-09-12T10:02:00Z GET /a 200 1"]
  s = summary(entries(lines).reduce(empty(5), fn(so_far, e) counted(so_far, e) end))
  assert s.span == 120_000.ms
  assert per_minute(s) == 1.5
  one = summary(entries(lines.take(1)).reduce(empty(5), fn(so_far, e) counted(so_far, e) end))
  assert per_minute(one) == 0.0
  assert per_minute(summary(empty(5))) == 0.0
  assert error_rate(summary(empty(5))) == 0.0
end

test "the slowest are by duration descending, then timestamp ascending"
  lines = ["2026-09-12T10:00:03Z GET /c 200 340",
    "2026-09-12T10:00:01Z GET /a 200 12",
    "2026-09-12T10:00:02Z POST /b 500 340",
    "2026-09-12T10:00:04Z GET /d 200 900"]
  s = summary(entries(lines).reduce(empty(3), fn(so_far, e) counted(so_far, e) end))
  assert s.slowest.map(fn(e) e.path end) == ["/d", "/b", "/c"]
end

test "the busiest are by count descending, then path ascending"
  lines = ["2026-09-12T10:00:01Z GET /b 200 1",
    "2026-09-12T10:00:02Z GET /c 200 1",
    "2026-09-12T10:00:03Z GET /c 200 1",
    "2026-09-12T10:00:04Z POST /a 200 1",
    "2026-09-12T10:00:05Z GET /a 200 1"]
  s = summary(entries(lines).reduce(empty(3), fn(so_far, e) counted(so_far, e) end))
  assert s.busiest == [Busy(count: 2, method: "GET", path: "/c"),
    Busy(count: 1, method: "GET", path: "/a"),
    Busy(count: 1, method: "POST", path: "/a")]
end

test "a tally trimmed along the way keeps the same slowest as sorting every entry"
  lines = (0..60).map(fn(i) "2026-09-12T10:00:00Z GET /p#{i} 200 #{(i * 37) % 50}" end)
  every = entries(lines)
  s = summary(every.reduce(empty(2), fn(so_far, e) counted(so_far, e) end))
  assert s.slowest.map(fn(e) e.path end) == ["/p27", "/p4"]
  assert s.slowest == every.sort_by_desc(fn(e) e.duration_ms end).take(2)
end

test rejects "a tally for a top of 0"
  empty(0)
end

test rejects "a tally for a top of 101"
  empty(101)
end

property "a summary never counts more errors than requests, for any list of records"
  for records in any(List(Entry))
    s = summary(records.reduce(empty(5), fn(so_far, e) counted(so_far, e) end))
    assert s.errors <= s.requests
    assert s.requests == s.errors + s.successes
  end
end

verified: types, contracts, tests (8), property (200 seeds), sim (not run)
          proven: not run
