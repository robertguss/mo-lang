module Bench.Deferred
expose Batcher, Asker, Batching, main

intent "Step 31's deferred reply under load: N askers put asks to one batcher, which keeps each asker's reply and answers the whole batch once N are held (the reply shape), against the same work written as a send and a Done message back (the send shape); the batcher times itself from the first put to the last answer."

process Batcher(bound: UInt64, total: UInt64, clock: Clock)
  state
    held: List(Reply(UInt64))
    senders: List(Handle(Asker))
    written: UInt64
    began: Option(Time)
    took: Int64
    waiter: List(Reply(Int64))
  end

  message Put : UInt64
  message Sent(from: Handle(Asker))
  message Wait : Int64

  fn update(state, message)
    case message
      Put:
        if state.began == None
          state.began = Some(clock.now)
        end
        state.held = state.held.push(reply_to)
        if state.held.size >= bound
          state.written += state.held.size
          for held in state.held
            held.answer(state.written)
          end
          state.held = []
        end
        if state.written >= total and state.waiter.size > 0
          state.took = (clock.now - (state.began or clock.now)).ms
          for w in state.waiter
            w.answer(state.took)
          end
          state.waiter = []
        end
      Sent(from):
        if state.began == None
          state.began = Some(clock.now)
        end
        state.senders = state.senders.push(from)
        if state.senders.size >= bound
          state.written += state.senders.size
          for sender in state.senders
            sender.send(Done)
          end
          state.senders = []
        end
        if state.written >= total and state.waiter.size > 0
          state.took = (clock.now - (state.began or clock.now)).ms
          for w in state.waiter
            w.answer(state.took)
          end
          state.waiter = []
        end
      Wait:
        state.waiter = state.waiter.push(reply_to)
        if state.written >= total and state.waiter.size > 0
          state.took = (clock.now - (state.began or clock.now)).ms
          for w in state.waiter
            w.answer(state.took)
          end
          state.waiter = []
        end
    end
  end
end

process Asker(batcher: Handle(Batcher), count: UInt64)
  state
    left: UInt64
    me: Option(Handle(Asker))
  end

  message Ask
  message Send(me: Handle(Asker))
  message Done

  fn update(state, message)
    case message
      Ask:
        for _ in 0..count
          if batcher.ask(Put, within: 60.seconds) is Error(_)
            state.left += 1
          end
        end
      Send(me):
        state.left = count
        state.me = Some(me)
        batcher.send(Sent(from: me))
      Done:
        state.left -= 1
        if state.left > 0
          if state.me is Some(me)
            batcher.send(Sent(from: me))
          end
        end
    end
  end
end

supervisor Batching(bound: UInt64, total: UInt64, clock: Clock, batcher: Handle(Batcher), count: UInt64)
  child Batcher(bound, total, clock), restart: :always
  child Asker(batcher, count), restart: :always
end

fn main(platform: Platform)
  askers = (platform.args.first or "8").to_u64 or 8
  total = (platform.args.get(1) or "10000").to_u64 or 10_000
  shape = platform.args.get(2) or "reply"
  each = total / askers
  batcher = Batcher.start(askers, each * askers, platform.clock)
  for _ in 0..askers
    asker = Asker.start(batcher, each)
    if shape == "send"
      asker.send(Send(me: asker))
    else
      asker.send(Ask)
    end
  end
  case batcher.ask(Wait, within: 600.seconds)
    Ok(ms): platform.stdout.write_line("#{shape}: #{each * askers} asks from #{askers} askers in #{ms} ms")
    Error(e): platform.stdout.write_line("#{shape}: no answer: #{e}")
  end
end
