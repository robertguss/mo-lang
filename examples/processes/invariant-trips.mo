module Processes.InvariantTrips
expose Batches, Batching

intent "An invariant that breaks crashes the process on the message that broke it, and a test rejects proves it trips."

process Batches()
  state
    done: UInt32
  end

  invariant "done never goes backwards"
    state.done < old(state.done)
  end

  message Finish
  message Undo
  message Done : UInt32

  fn update(state, message)
    case message
      Finish:
        state.done += 1
      Undo:
        state.done -= 1
      Done: state.done
    end
  end
end

supervisor Batching
  child Batches, restart: :always
end

test "finishing moves done forward"
  batches = Batches.start()
  batches.send(Finish)
  assert batches.ask(Done, within: 100.ms) is Ok(1)
end

test rejects "undoing a finished batch"
  batches = Batches.start()
  batches.send(Finish)
  batches.send(Undo)
end

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs)
          proven: not run
