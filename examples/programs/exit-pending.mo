# run:
# exit: 3
module Programs.ExitPending
expose Alarm, Alarms, main

intent "platform.exit ends the program at once, under mo run and as a binary, though a process holds a delayed send an hour away: the send is dropped with an event, and the exit code is kept."

process Alarm()
  state
    rung: UInt64
  end

  message Arm(me: Handle(Alarm)) : Bool
  message Ring

  fn update(state, message)
    case message
      Arm(me):
        me.send(Ring, delay: 3_600_000.ms)
        true
      Ring:
        state.rung += 1
    end
  end
end

supervisor Alarms
  child Alarm, restart: :never
end

fn main(platform: Platform)
  alarm = Alarm.start()
  armed = alarm.ask(Arm(me: alarm), within: 1_000.ms)
  platform.stdout.write_line("armed: #{armed}")
  platform.exit(3)
end

verified: types, contracts, tests (0), property (0 seeds), sim (not run)
          proven: not run
