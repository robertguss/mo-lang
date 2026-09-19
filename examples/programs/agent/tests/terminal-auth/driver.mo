module Agent.TerminalAuth.Driver

use Agent.Model{Model, Request, Reply, ModelError, complete}

process Caller(http: Http, port: UInt16)
  state
    calls: UInt64
  end

  message Call(retries: UInt32, exhausted: Bool, budget: Int64) : String

  fn update(state, message)
    case message
      Call(retries: retries, exhausted: exhausted, budget: budget):
        state.calls += 1
        by = if exhausted: reply_by.at_most(0.ms) else: reply_by.at_most(budget.ms)
        model = Model(host: "127.0.0.1", port: port, tools: ["now"])
        request = Request(run: "terminal-auth", goal: "g", tools: ["now"], transcript: [])
        case complete(http, model, request, retries, by)
          Ok(Answer(text: text, tokens: tokens)): "Answer(#{text},#{tokens})"
          Ok(_): "UnexpectedTool"
          Error(Status(code)): "Status(#{code})"
          Error(Late): "Late"
          Error(_): "UnexpectedError"
        end
    end
  end
end

supervisor Callers(http: Http, port: UInt16)
  child Caller(http, port), restart: :always
end

fn main(platform: Platform)
  port = (platform.args.get(0) or "0").to_u64 or 0
  retries = (platform.args.get(1) or "2").to_u64 or 2
  budget = (platform.args.get(2) or "2000").to_i64 or 2000
  exhausted = (platform.args.get(3) or "false") == "true"
  caller = Caller.start(platform.http, port.to_u16)
  case caller.ask(Call(retries: retries.to_u32, exhausted: exhausted, budget: budget),
    within: (budget + 1000).ms)
    Ok(text): platform.stdout.write_line(text)
    Error(_): platform.stdout.write_line("CallerTimeout")
  end
end

verified: types, contracts, tests (0), property (0 seeds), sim (not run)
          proven: not run
