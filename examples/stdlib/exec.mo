module Stdlib.Exec
expose Removal, remove, inspect, removed_all

intent "Remove a container by name and read one back, through Commands main narrowed to `docker rm -f NAME` and `docker inspect --format {{json .}} NAME`, so nothing below main can run anything else, and every run says how it ended within its deadline."

enum Removal
  Removed
  NotThere
  Stuck(code: UInt8)
  Slow
  Broken(why: String)
end

# `docker rm -f NAME` exits 0 when it removed the container, and 1 when there was none.
fn remove(rm: Command, name: String) : Removal
  case rm.run([name], within: 10.seconds)
    Ok(done): ended(done.exit)
    Error(Timeout): Slow
    Error(Failed(why)): Broken(why: why)
    Error(Missing): Broken(why: "no docker at that path")
    Error(Refused): Broken(why: "a name holding a NUL")
  end
end

fn ended(exit: Exit) : Removal
  case exit
    Exited(code):
      if code == 0: Removed else: if code == 1: NotThere else: Stuck(code: code)
    Signalled(_): Stuck(code: 255)
  end
end

# The container's JSON as docker printed it, or None when the run did not end in Exited(0).
fn inspect(look: Command, name: String) : Option(String)
  case look.run([name], within: 10.seconds)
    Ok(done):
      if done.exit == Exited(code: 0) and !done.truncated: String.from_bytes(done.stdout) else: None
    Error(_): None
  end
end

fn removed_all(rm: Command, names: List(String)) : Bool
  var all = true
  for name in names
    all = all and remove(rm, name) == Removed
  end
  all
end

# A docker that knows two containers, `web` and `db`, and is slow for `stuck`.
fn docker(argv: List(String), stdin: String) : Done
  name = argv.last or ""
  known = name == "web" or name == "db"
  code = if name == "stuck": 125.to_u8 else: if known: 0.to_u8 else: 1.to_u8
  out = if argv.get(1) == Some("inspect") and known: "{\"Name\":\"/#{name}\"}\n" else: ""
  Done(exit: Exited(code: code), stdout: out.bytes, stderr: stdin.bytes, truncated: false,
    took: 12.ms)
end

# The argument list the child would get, the program's path first, joined by |.
fn echoed(argv: List(String)) : Done
  text = String.join(argv, "|")
  Done(exit: Exited(code: argv.size.to_u8), stdout: text.bytes, stderr: [], truncated: false,
    took: 0.ms)
end

test "a removal says how the child ended"
  docker_exec = Exec.fixture(fn(argv, stdin) docker(argv, stdin) end)
  rm = docker_exec.program("/usr/bin/docker").command([Fixed(text: "rm"), Fixed(text: "-f"), Hole])
  assert remove(rm, "web") == Removed
  assert remove(rm, "cache") == NotThere
  assert remove(rm, "stuck") == Stuck(code: 125)
  assert remove(rm, "a\u{0}b") == Broken(why: "a name holding a NUL")
  assert removed_all(rm, ["web", "db"])
  assert !removed_all(rm, ["web", "cache"])
end

test "inspect reads what the child wrote, and nothing when it failed"
  docker_exec = Exec.fixture(fn(argv, stdin) docker(argv, stdin) end)
  words = [Fixed(text: "inspect"), Fixed(text: "--format"), Fixed(text: "{{json .}}"), Hole]
  look = docker_exec.program("/usr/bin/docker").command(words)
  assert inspect(look, "db") == Some("{\"Name\":\"/db\"}\n")
  assert inspect(look, "cache") is None
end

test "a hole is one whole argument, whatever it holds"
  echo = Exec.fixture(fn(argv, _) echoed(argv) end).program("/bin/echo").command([Hole])
  case echo.run(["a b; $(rm -rf /)"], within: 1.minute)
    Ok(done):
      assert done.exit == Exited(code: 2)
      assert String.from_bytes(done.stdout) == Some("/bin/echo|a b; $(rm -rf /)")
    Error(_):
      assert false
  end
  assert echo.run([], within: 1.minute) == Error(Refused)
end

verified: types, contracts, tests (3), property (0 seeds), sim (not run)
          proven: not run
