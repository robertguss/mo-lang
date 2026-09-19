module FilesBench
expose main

intent "Runs one Fs row many times over a tree measure.py made, so the row's cost per call can be timed before and after step 40."

fn ok(r: Result(T, FsError)) : UInt64
  if r is Ok(_): 1 else: 0
end

fn once(work: Fs, mode: String) : UInt64
  case mode
    "read": ok(work.read("small.txt", within: 1.minute))
    "deep": ok(work.read("d/d/d/d/d/d/d/d/d/d/d/d/d/d/d/d/small.txt", within: 1.minute))
    "size": ok(work.size("small.txt", within: 1.minute))
    "write": ok(work.write("out.txt", "one line\n", within: 1.minute))
    "append": ok(work.append("log.txt", "one line\n", within: 1.minute))
    "fold": ok(work.fold_lines("big.txt", 0, within: 10.minute, fn(n, line) n + line.byte_size end))
    "list": ok(work.scoped("many").list(within: 1.minute))
    "list_kinds": ok(work.scoped("many").list_kinds(within: 1.minute))
    _: 0
  end
end

fn main(platform: Platform)
  work = platform.fs.scoped("work")
  mode = platform.args.get(0) or ""
  n = (platform.args.get(1) or "0").to_u64 or 0
  var done = 0
  for _ in 0..n
    done += once(work, mode)
  end
  platform.stdout.write_line("#{done} of #{n}")
end
