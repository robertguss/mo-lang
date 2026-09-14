module Effects.Runtime
expose Tally, Tallies

intent "The runtime surface is a capability: a test's Runtime lists the processes it started, reads a state between updates and the events the runtime kept, and a Runtime that may act sends a message the process declares, pauses, and resumes, where a read-only one refuses."

process Tally()
  state
    votes: UInt64
  end

  message Vote(n: UInt64)
  message Total : UInt64

  fn update(state, message)
    case message
      Vote(n):
        state.votes += n
      Total: state.votes
    end
  end
end

supervisor Tallies
  child Tally, restart: :always
end

test "the surface lists a started process and reads its state and its updates"
  runtime = Runtime.fixture()
  tally = Tally.start()
  tally.send(Vote(n: 2))
  assert tally.ask(Total, within: 1.minute) is Ok(2)
  listed = runtime.processes(within: 1.minute)
  assert listed.size == 1
  case listed.first
    Some(info):
      assert info.name == "Tally"
      assert info.mailbox == 0 and info.bound == 1_000 and info.alive
      assert runtime.state(info.id, within: 1.minute) is Ok("Tally(votes: 2)")
      assert runtime.recent(info.id, 2, within: 1.minute).size == 2
      assert runtime.slowest(1, within: 1.minute).size == 1
      assert runtime.events(since: Time.fixture(), n: 10, within: 1.minute).size == 3
      assert Json.encode(info).starts_with?("{\"id\": ")
    None:
      assert false
  end
  assert runtime.state(7, within: 1.minute) is Error(NoProcess)
  assert runtime.crashes(5, within: 1.minute).size == 0
  assert runtime.sources(within: 1.minute).size == 0
  assert runtime.memory(within: 1.minute).largest.size == 1
end

test "a surface that may act pauses, sends, and resumes, and a read-only one refuses"
  runtime = Runtime.fixture()
  tally = Tally.start()
  tally.send(Vote(n: 2))
  assert tally.ask(Total, within: 1.minute) is Ok(2)
  case runtime.processes(within: 1.minute).first
    Some(info):
      assert runtime.pause(info.id, within: 1.minute) is Ok(_)
      tally.send(Vote(n: 3))
      assert tally.ask(Total, within: 10.ms) is Error(Timeout)
      assert runtime.send(info.id, "Vote(n: 5)", within: 1.minute) is Ok(_)
      assert runtime.send(info.id, "Vote(n: -1)", within: 1.minute) is Error(Unparsed(_))
      assert runtime.read_only.send(info.id, "Vote(n: 1)", within: 1.minute) is Error(ReadOnly)
      assert runtime.read_only.pause(info.id, within: 1.minute) is Error(ReadOnly)
      assert runtime.resume(info.id, within: 1.minute) is Ok(_)
      assert tally.ask(Total, within: 1.minute) is Ok(10)
    None:
      assert false
  end
end

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs)
          proven: not run
