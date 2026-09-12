module Processes.Ask
expose Tally, Tallies

intent "Ask a process a question and wait for its reply, but never past a deadline."

process Tally()
  state
    votes: UInt32
  end

  message Vote
  message Total : UInt32

  fn update(state, message)
    case message
      Vote:
        state.votes += 1
      Total: state.votes
    end
  end
end

supervisor Tallies
  child Tally, restart: :always
end

test "the reply counts every vote sent before the ask"
  tally = Tally.start()
  tally.send(Vote)
  tally.send(Vote)
  assert tally.ask(Total, within: 100.ms) is Ok(2)
end
