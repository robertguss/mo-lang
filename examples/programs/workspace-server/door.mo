# sim: --faults 20 --until 0.5
module WorkspaceServer.Door
expose Door

intent "What main waits on: the operator's close, an observed candidate disconnect after cleanup, or the end of the lease and its grace. One knock lets every waiter go; a candidate that only stalls or floods never holds this handle."

process Door()
  state
    waiting: List(Reply(Bool))
    knocked: Bool
  end

  message Wait : Bool
  message Knock

  fn update(state, message)
    case message
      Wait:
        state.waiting = state.waiting.push(reply_to)
        if state.knocked
          for w in state.waiting
            w.answer(true)
          end
          state.waiting = []
        end
      Knock:
        state.knocked = true
        for w in state.waiting
          w.answer(true)
        end
        state.waiting = []
    end
  end
end

supervisor Doors
  child Door, restart: :never
end

test "the door lets main go once, whenever it is asked"
  door = Door.start()
  door.send(Knock)
  assert door.ask(Wait, within: 1.minute) == Ok(true)
end

verified: types, contracts, tests (1), property (0 seeds), sim (200 runs)
          proven: not run
