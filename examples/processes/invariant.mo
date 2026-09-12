module Processes.Invariant
expose Odometer, Dashboard

intent "State what must hold after every message, so the process crashes the moment it does not."

process Odometer()
  state
    km: UInt64
  end

  invariant "the odometer never goes backwards"
    state.km < old(state.km)
  end

  message Drive(km: UInt64)
  message Reading : UInt64

  fn update(state, message)
    case message
      Drive(km: distance):
        state.km += distance
      Reading: state.km
    end
  end
end

supervisor Dashboard
  child Odometer, restart: :always
end

test "driving only ever adds to the reading"
  odometer = Odometer.start()
  odometer.send(Drive(km: 12))
  odometer.send(Drive(km: 30))
  assert odometer.ask(Reading, within: 100.ms) is Ok(42)
end
