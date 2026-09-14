module Stdlib.FsFixtureScope
expose logs_in

intent "An Fs.fixture() refuses a path that climbs out of a scope, as the real Fs does, so a test can show a program staying inside the folder it was given."

# The .log files in a folder, read only through a scope on it.
fn logs_in(fs: Fs, dir: String) : List(String)
  case fs.scoped(dir).list(within: 1.minute)
    Ok(names): names.filter(fn(name) name.ends_with?(".log") end)
    Error(_): []
  end
end

test "a scope that climbs out of its folder holds nothing, as on the real Fs"
  fs = Fs.fixture()
  assert fs.mkdir("logs", within: 1.minute) is Ok(_)
  assert fs.write("outside.log", "x\n", within: 1.minute) is Ok(_)
  assert "#{fs.scoped("logs").scoped("..").list(within: 1.minute)}" == "Error(Missing(\".\"))"
  assert "#{fs.scoped("..").list(within: 1.minute)}" == "Error(Missing(\".\"))"
  assert "#{fs.scoped("logs").read("../outside.log", within: 1.minute)}" == "Error(Missing(\"../outside.log\"))"
end

test "a program given a folder reads only what is inside it"
  fs = Fs.fixture()
  assert fs.mkdir("logs", within: 1.minute) is Ok(_)
  assert fs.write("logs/in.log", "x\n", within: 1.minute) is Ok(_)
  assert fs.write("out.log", "y\n", within: 1.minute) is Ok(_)
  assert logs_in(fs, "logs") == ["in.log"]
  assert logs_in(fs.scoped("logs"), "..") == []
  assert logs_in(fs, "logs/..") == ["out.log"]
end

verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run
