# run: 1000
# run: 400000
module Programs.DeferredLarge
expose Holder, Holders, Output, main

intent "An arm that answers an ask it kept, with a text of megabytes built in that arm, answers it whole, under mo run and as a binary: the answer is packed when answer runs, as a send is, so the compaction of the update's region before it commits cannot move the text from under it (it printed another process's memory in a binary and panicked the interpreter)."

# What the agent's Application answered: the text of a report and its exit code.
struct Output
  text: String
  code: UInt8
end

process Holder()
  state
    waiting: List(Reply(Output))
  end

  message Get(me: Handle(Holder), n: UInt64) : Output
  message Poll(n: UInt64)

  fn update(state, message)
    case message
      # The asker is kept, and a delayed self-send answers it, as the agent's Application did.
      Get(me: me, n: n):
        state.waiting = state.waiting.push(reply_to)
        me.send(Poll(n: n), delay: 1.ms)
      # The output is built here with garbage past it, so the returning arm compacts its region.
      Poll(n):
        output = built(n)
        for held in state.waiting
          held.answer(output)
        end
        state.waiting = []
    end
  end
end

supervisor Holders
  child Holder, restart: :never
end

# Two quoted copies of n doubled y's, a line apart: a report's shape, with garbage on the way.
fn built(n: UInt64) : Output
  line = "y".repeat(n)
  return Output(text: String.join([line, line].map(quoted), "\n"), code: 3)
end

fn quoted(line: String) : String
  return "\"#{line.replace("y", "yy")}\""
end

fn main(platform: Platform)
  out = platform.stdout
  n = (platform.args.first or "0").to_u64() or 0
  holder = Holder.start()
  case holder.ask(Get(me: holder, n: n), within: 60_000.ms)
    Ok(output):
      quoted = "\"#{"yy".repeat(n)}\""
      whole = output.text == "#{quoted}\n#{quoted}"
      out.write_line("answered #{output.text.byte_size} bytes and code #{output.code}, whole: #{whole}")
    Error(_): out.write_line("no answer")
  end
end

verified: types, contracts, tests (0), property (0 seeds), sim (not run)
          proven: not run
