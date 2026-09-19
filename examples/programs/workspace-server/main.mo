# run:
# exit: 2
module WorkspaceServer.Main
expose main

use WorkspaceServer.Door{Door}
use WorkspaceServer.Server{serve_run}

intent "Run the Mo workspace server for one run folder the operator has laid out: serve mo-workspace-http-v1's five file tools on one loopback port and the operator's path on another, and end, exit 0, once the operator closes the run or a minute past the lease; a folder that cannot be served exits 1, and no folder is a usage error, exit 2. This server does not serve command: that is part B's, through Exec."

fn main(platform: Platform)
  folder = platform.args.first or ""
  if folder == ""
    platform.stdout.write_line("usage: workspace-server RUN_FOLDER")
    platform.exit(2)
  else
    door = Door.start()
    case serve_run(platform.fs.scoped(folder), platform.net, platform.clock, platform.random, false, door)
      Ok(lease_ms):
        let_go = door.ask(Wait, within: (lease_ms + 120_000).ms) == Ok(true)
        platform.exit(if let_go: 0 else: 1)
      Error(why):
        platform.stderr.write_line("workspace-server: #{why}")
        platform.exit(1)
    end
  end
end
