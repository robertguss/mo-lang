module Lag
expose Stamp, Stamps, main

intent "Probe: how late a 100 ms delayed send arrives, under mo run and as a binary."

process Stamp(clock: Clock, out: Out)
  state
    count: Int64
    total_ms: Int64
    worst_ms: Int64
  end

  message At(me: Handle(Stamp), sent: Time)

  fn update(state, message)
    case message
      At(me: me, sent: sent):
        lag = (clock.now - sent).ms - 100
        state.count += 1
        state.total_ms += lag
        if lag > state.worst_ms
          state.worst_ms = lag
        end
        if state.count < 20
          me.send(At(me: me, sent: clock.now), delay: 100.ms)
        else
          out.write("20 sends of 100 ms: mean lag #{state.total_ms / 20} ms, worst #{state.worst_ms} ms\n")
        end
    end
  end
end

supervisor Stamps(clock: Clock, out: Out)
  child Stamp(clock, out), restart: :always
end

fn main(platform: Platform)
  stamp = Stamp.start(platform.clock, platform.stdout)
  stamp.send(At(me: stamp, sent: platform.clock.now), delay: 100.ms)
end
