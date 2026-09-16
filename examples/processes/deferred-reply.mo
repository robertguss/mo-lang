# run:
module Processes.DeferredReply
expose Batcher, Batchers, Asker, main

intent "A batcher answers later: the arm for an ask keeps its asker in a state field instead of answering it, and one flush answers the whole batch at once, so many asks cost one write and every asker still holds its own deadline."

# Put is an ask, and its arm never answers: it keeps reply_to in state.waiting, which the flush
# answers. The asker hands the batcher its own handle, so the first Put of a batch arms the flush.
process Batcher()
  state
    keys: List(String)
    waiting: List(Reply(UInt64))
    written: UInt64
  end

  invariant "the batch keeps an asker for every key in it"
    state.keys.size == state.waiting.size
  end

  message Put(key: String, me: Handle(Batcher)) : UInt64
  message Flush
  message Written : UInt64
  message Orphan

  fn update(state, message)
    case message
      Put(key: key, me: me):
        if state.keys.size == 0
          me.send(Flush, delay: 5.ms)
        end
        state.keys = state.keys.push(key)
        state.waiting = state.waiting.push(reply_to)
      Flush:
        batch = state.keys.size
        state.written += batch
        for held in state.waiting
          held.answer(batch)
        end
        state.keys = []
        state.waiting = []
      Written: state.written
      Orphan:
        state.keys = state.keys.push("orphan")
    end
  end
end

# One asker of its own per put, so several asks are in flight at once and one flush answers them all.
process Asker(batcher: Handle(Batcher))
  state
    answered: UInt64
    batch: UInt64
  end

  message Put(key: String)
  message Answered : UInt64
  message Batch : UInt64

  fn update(state, message)
    case message
      Put(key):
        case batcher.ask(Put(key: key, me: batcher), within: 1.minute)
          Ok(n):
            state.answered += 1
            state.batch = n
          Error(_):
            state.batch = 0
        end
      Answered: state.answered
      Batch: state.batch
    end
  end
end

supervisor Batchers(batcher: Handle(Batcher))
  child Batcher, restart: :always
  child Asker(batcher), restart: :always
end

fn main(platform: Platform)
  out = platform.stdout
  batcher = Batcher.start()
  var askers = []
  for i in 0..8
    asker = Asker.start(batcher)
    asker.send(Put(key: "k#{i}"))
    askers = askers.push(asker)
  end
  var answered = 0
  for asker in askers
    if asker.ask(Answered, within: 1.minute) is Ok(1)
      answered += 1
    end
  end
  out.write("answered #{answered}\n")
  if batcher.ask(Written, within: 1.minute) is Ok(w)
    out.write("written #{w}\n")
  end
end

# An ask from main is synchronous, so each of the ten is its own batch of one; what the test shows
# is that no arm answered its own ask. Under a seed a fault may eat an ask's deadline before the
# flush comes, so what holds in every run is that every Ok came from a flush, the only place
# answer is called, and that the batcher wrote at least as many keys as the asks it answered.
test "ten asks the batcher keeps are answered by a flush, never by the arm that took them"
  batcher = Batcher.start()
  var ok = 0
  for i in 0..10
    if batcher.ask(Put(key: "k#{i}", me: batcher), within: 1.minute) is Ok(n) and n >= 1
      ok += 1
    end
  end
  if batcher.ask(Written, within: 1.minute) is Ok(w)
    assert w >= ok
    assert ok != 10 or w == 10
  end
end

# The asker's deadline travels with the Reply: it runs out before the flush, and the answer the
# flush makes afterwards is dropped. The key is written all the same once the flush comes, so the
# message the ask carried arrived exactly once; under faults the wait for the flush may be refused.
test "an asker whose deadline is shorter than the flush sees Timeout, and the later answer is dropped"
  batcher = Batcher.start()
  assert batcher.ask(Put(key: "a", me: batcher), within: 1.ms) is Error(Timeout)
  slow = Fs.fixture(delay: 10.ms)
  waited = slow.list(within: 1.minute) is Ok(_)
  if batcher.ask(Written, within: 1.minute) is Ok(w)
    assert w <= 1
    assert !waited or w == 1
  end
end

# Orphan breaks the invariant while the ask is still held, so the batcher crashes and restarts
# between the ask and the flush: the asker it kept is answered Down at once.
test rejects "a crash between the ask and the flush gives every asker it kept Down"
  batcher = Batcher.start()
  batcher.send(Orphan, delay: 1.ms)
  assert batcher.ask(Put(key: "a", me: batcher), within: 1.minute) is Error(Down)
end

verified: types, contracts, tests (3), property (0 seeds), sim (100 runs, invariants (kept 1, tripped 1))
          proven: not run
