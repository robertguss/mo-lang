module Effects.Clock
expose Session, Holder, Holders, expired?

intent "Read the time only through a Clock, so a function without one cannot see it; in a test the fixture clock moves as the simulator's time does."

struct Session
  started: Time
  length: Duration
end

fn expired?(clock: Clock, session: Session) : Bool
  clock.now - session.started >= session.length
end

process Holder(clock: Clock)
  state
    until: Option(Time) = None
  end

  message Lease(length: Duration)
  message Held : Bool

  fn update(state, message)
    case message
      Lease(length):
        state.until = Some(clock.now + length)
      Held: clock.now < (state.until or clock.now)
    end
  end
end

supervisor Holders(clock: Clock)
  child Holder(clock), restart: :always
end

test "a fixture call that waits moves the fixture clock by its wait (step 28)"
  clock = Clock.fixture()
  before = clock.now
  assert Fs.fixture(delay: 200.ms).list(within: 1.minute) is Ok(_)
  assert clock.now - before == 200.ms
end

test "a lease runs out in a process once a fixture call has waited past it"
  clock = Clock.fixture()
  holder = Holder.start(clock)
  holder.send(Lease(length: 10.minute))
  assert holder.ask(Held, within: 1.minute) is Ok(true)
  # Under faults the call may fail before its delay, and then the lease may still be held.
  waited = Fs.fixture(delay: 11.minute).list(within: 12.minute)
  held = holder.ask(Held, within: 1.minute)
  assert waited is Error(_) or held == Ok(false)
end

test "a session with no length is over at once"
  clock = Clock.fixture()
  assert expired?(clock, Session(started: clock.now, length: 0.ms))
end

test "a long session is not over yet"
  clock = Clock.fixture()
  assert !expired?(clock, Session(started: clock.now, length: 1.minute))
end

verified: types, contracts, tests (4), property (0 seeds), sim (100 runs)
          proven: not run
