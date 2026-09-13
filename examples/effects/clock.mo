module Effects.Clock
expose Session, expired?

intent "Read the time only through a Clock, so a function without one cannot see it."

struct Session
  started: Time
  length: Duration
end

fn expired?(clock: Clock, session: Session) : Bool
  clock.now - session.started >= session.length
end

test "a session with no length is over at once"
  clock = Clock.fixture()
  assert expired?(clock, Session(started: clock.now, length: 0.ms))
end

test "a long session is not over yet"
  clock = Clock.fixture()
  assert !expired?(clock, Session(started: clock.now, length: 1.minute))
end

verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run
