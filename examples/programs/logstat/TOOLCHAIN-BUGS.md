# Toolchain bugs found while writing logstat

Recorded while writing program 2 (`mo-wiki/spec/programs/02-log-analyzer.md`, brief `mo-wiki/plans/program-2.md`), round 4 of the control run. The write scope was `examples/`, so none is fixed here. Built from `565a7cc` (`zig build`, ReleaseSafe).

## 1. `Fs.fixture()` does not refuse `..` where Mo.Server's `Fs` does

A scope on the platform's `Fs` refuses to climb out of itself; a scope on the fixture climbs and answers as if it had not. A test over the fixture therefore cannot show that a program stays inside its folder, which is one of logstat's nevers.

```
test "fixture scope up"
  fs = Fs.fixture()
  assert fs.mkdir("logs", within: 1.minute) is Ok(_)
  assert fs.write("outside.log", "x\n", within: 1.minute) is Ok(_)
  assert "#{fs.scoped("logs").scoped("..").list(within: 1.minute)}" == "Error(Missing(\".\"))"
  assert "#{fs.scoped("..").list(within: 1.minute)}" == "Error(Missing(\".\"))"
end
```

Under `mo test` the first assert fails with `Ok([])` and the second with `Ok(["outside.log"])`. Under `mo run`, the same calls on `platform.fs` (with `logs/` and `outside.log` in the working folder) give `Error(Missing("."))` for both. Reads agree: `fs.scoped("logs").read("../outside.log")` is `Missing` on both.

Related, and perhaps intended: `platform.fs.scoped("..")` is refused but `platform.fs.scoped("/tmp")` lists `/tmp`, and `platform.fs.read("/etc/hosts")` reads it, so the platform's `Fs` is rooted at the working folder for a relative path and at `/` for an absolute one. A scope taken from it is closed both ways: `platform.fs.scoped("logs").scoped("/etc")` and `.read("/etc/hosts")` are `Missing`.

Workaround: logstat's test of the never ("a .log file above <dir>, or in a folder inside it, is never read") puts a `.log` beside the scoped folder and one in a folder inside it, and checks neither is read; it does not test `..`. `main` scopes `platform.fs` to `<dir>` read-only before anything reads, and reads only names `list` gave.
