module Stdlib.Time
expose minutes_between

intent "Read instants from RFC 3339 text, build them from calendar parts, and measure the time between two of them."

fn minutes_between(from: Time, to: Time) : Float64
  to.since(from).minutes
end

test "RFC 3339 text is an instant, and a date or time that does not exist is not"
  assert Time.parse("2026-09-12T10:00:02Z") is Some(t)
  assert t.to_iso8601 == "2026-09-12T10:00:02Z"
  assert t == Time.from_parts(2026, 9, 12, 10, 0, 2)
  assert Time.parse("2026-09-12T12:00:02+02:00") == Some(t)
  assert Time.parse("2026-09-12T10:00:02.5Z") is Some(half)
  assert half.to_iso8601 == "2026-09-12T10:00:02.500Z"
  assert half.since(t).ms == 500
  assert Time.parse("2026-02-30T00:00:00Z") is None
  assert Time.parse("2026-09-12T24:00:00Z") is None
  assert Time.parse("2026-09-12 10:00:02Z") is None
  assert Time.parse("2026-09-12T10:00:02") is None
end

test "a span is a Duration, read in milliseconds, seconds, or minutes"
  start = Time.from_parts(2024, 12, 31, 23, 59, 30)
  finish = Time.from_parts(2025, 1, 1, 0, 1, 0)
  assert finish.since(start).seconds == 90.0
  assert minutes_between(start, finish) == 1.5
  assert finish - start == 90_000.ms
  assert finish - start == 90.seconds
  assert (start + 30_000.ms).to_iso8601 == "2025-01-01T00:00:00Z"
  assert Time.fixture().to_iso8601 == "2026-01-01T00:00:00Z"
end

test "the calendar counts leap days, and the years before 1970"
  assert Time.from_parts(2024, 3, 1, 0, 0, 0).since(Time.from_parts(2024, 2, 28, 0, 0, 0)) == 2.days
  assert Time.parse("2023-02-29T00:00:00Z") is None
  assert Time.parse("2000-02-29T00:00:00Z") is Some(_)
  assert Time.from_parts(1969, 12, 31, 23, 59, 59).to_iso8601 == "1969-12-31T23:59:59Z"
end

verified: types, contracts, tests (3), property (0 seeds), sim (not run)
          proven: not run
