module Effects.Clock
expose ClockError, Session, expired

intent "Read the time only through a Clock, so a function without one cannot see it."

enum ClockError
  Timeout
end

struct Session
  started: Time
  length: Duration
end

fn expired(clock: Clock, session: Session) : Result(Bool, ClockError)
  now = try clock.now(within: 10.ms)
  Ok(now - session.started >= session.length)
end

test "a session with no length is over at once"
  clock = Clock.fixture()
  assert clock.now(within: 10.ms) is Ok(start)
  assert expired(clock, Session(started: start, length: 0.ms)) is Ok(true)
end

test "a long session is not over yet"
  clock = Clock.fixture()
  assert clock.now(within: 10.ms) is Ok(start)
  assert expired(clock, Session(started: start, length: 1.minute)) is Ok(false)
end
