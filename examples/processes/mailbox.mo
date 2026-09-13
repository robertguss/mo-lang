module Processes.Mailbox
expose Journal, Journals

intent "A journal holds at most 100 waiting messages; a sender that overflows the mailbox crashes, and the journal does not."

process Journal() mailbox: 100
  state
    lines: List(String) where size <= 1_000
  end

  message Write(text: String)
  message Count : UInt64

  fn update(state, message)
    case message
      Write(text):
        state.lines = state.lines.push(text)
      Count: state.lines.size
    end
  end
end

supervisor Journals
  child Journal, restart: :always
end

test "writes within the bound all arrive"
  journal = Journal.start()
  journal.send(Write(text: "opened"))
  journal.send(Write(text: "closed"))
  assert journal.ask(Count, within: 100.ms) is Ok(2)
end

test "a full mailbox delivers every write"
  journal = Journal.start()
  for _ in 0..100
    journal.send(Write(text: "line"))
  end
  assert journal.ask(Count, within: 100.ms) is Ok(100)
end
