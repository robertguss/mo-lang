module Agent.Tests.ApplicationWorkspaceV1.Driver

use Agent.Tools{Call}
use Agent.WorkspaceAdapter{Settings, settings, sent, tools}

intent "Real-socket probes of the application adapter for both runtimes: one call sent on a deadline the probe's ask gives it, with the deadline's remainder before and after."

process Probe(http: Http, settings: Settings)
  state
    calls: UInt64
  end

  message Near(bytes: UInt64) : String

  fn update(state, message)
    case message
      Near(bytes):
        state.calls += 1
        before = reply_by.remaining.ms
        call = Call(tool: "command", args: Map.new().set("command", "x".repeat(bytes)),
          granted: tools(), hosts: [])
        output = sent(http, settings, call, "1", reply_by)
        "{\"before_ms\": #{before}, \"after_ms\": #{reply_by.remaining.ms}, \"output\": #{Json.encode(output)}}"
    end
  end
end

supervisor Probes(http: Http, settings: Settings)
  child Probe(http, settings), restart: :never
end

fn probed(fs: Fs, http: Http, args: List(String)) : String
  text = case fs.read(args.get(1) or "", within: 2_000.ms)
    Ok(found): found
    Error(_):
      return "{\"error\": \"config_unreadable\"}"
  end
  bound = case settings(text)
    Ok(found): found
    Error(why):
      return "{\"error\": #{Json.encode(why)}}"
  end
  ms = (args.get(2) or "0").to_i64 or 0
  probe = Probe.start(http, bound)
  if args.first == Some("near")
    case probe.ask(Near(bytes: (args.get(3) or "0").to_u64 or 0), within: ms.ms)
      Ok(line): line
      Error(_): "{\"error\": \"probe_deadline\"}"
    end
  else
    "{\"error\": \"unknown_mode\"}"
  end
end

fn main(platform: Platform)
  platform.stdout.write_line(probed(platform.fs, platform.http, platform.args))
end

verified: types, contracts, tests (0), property (0 seeds), sim (not run)
          proven: not run
