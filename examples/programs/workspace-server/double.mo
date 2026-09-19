module WorkspaceServer.Double
expose main

use WorkspaceServer.Door{Door}
use WorkspaceServer.Server{serve_run}

intent "The local test double of the workspace server, as test_owner.py is the Python owner's: the same server with test_owner.py's scripted commands, an event tap in the run folder's workspace/events, and file replies held back by the config's late_ms. Only the local behaviour groups start it; the production entry is main.mo."

fn main(platform: Platform)
  folder = platform.args.first or ""
  if folder == ""
    platform.stdout.write_line("usage: workspace-server-double RUN_FOLDER")
    platform.exit(2)
  else
    door = Door.start()
    case serve_run(platform.fs.scoped(folder), platform.net, platform.clock, platform.random, true,
      door)
      Ok(lease_ms):
        let_go = door.ask(Wait, within: (lease_ms + 120_000).ms) == Ok(true)
        platform.exit(if let_go: 0 else: 1)
      Error(why):
        platform.stderr.write_line("workspace-server-double: #{why}")
        platform.exit(1)
    end
  end
end

verified: types, contracts, tests (0), property (0 seeds), sim (not run)
          proven: not run
