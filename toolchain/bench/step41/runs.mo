module ExecBench
expose main

intent "Runs one command many times, so what one Command.run costs can be timed against a C posix_spawn loop as the floor."

# 1 when the child exited 0 and its stdout held `want` bytes.
fn ok(r: Result(Done, ExecError), want: UInt64) : UInt64
  case r
    Ok(done): if done.exit == Exited(code: 0) and done.stdout.size == want: 1 else: 0
    Error(_): 0
  end
end

fn main(platform: Platform)
  mode = platform.args.get(0) or ""
  n = (platform.args.get(1) or "0").to_u64 or 0
  exec = platform.exec
  truth = exec.program("/usr/bin/true").command([])
  mib = exec.program("/usr/bin/head").command([Fixed(text: "-c"), Fixed(text: "1048576"), Fixed(text: "/dev/zero")]).output(2_097_152)
  var done = 0
  for _ in 0..n
    if mode == "true"
      done += ok(truth.run([], within: 1.minute), 0)
    else
      done += ok(mib.run([], within: 1.minute), 1_048_576)
    end
  end
  platform.stdout.write_line("#{done} of #{n}")
end
