# run: made
module Folders
expose said, main

intent "Make a folder with Fs.mkdir and write a file into it over the real file system: a folder already there is Ok, and a folder whose parent is not there, or a file in the way, is Missing."

fn said(r: Result(T, FsError)) : String
  case r
    Ok(_): "ok"
    Error(Missing(path)): "missing #{path}"
    Error(Timeout): "timeout"
    Error(NotText): "not text"
  end
end

fn main(platform: Platform)
  name = platform.args.first or "made"
  here = platform.fs
  out = platform.stdout
  out.write_line("mkdir #{name}: #{said(here.mkdir(name, within: 1.minute))}")
  out.write_line("again: #{said(here.mkdir(name, within: 1.minute))}")
  out.write_line("under a folder not there: #{said(here.mkdir("nowhere/#{name}", within: 1.minute))}")
  out.write_line("a file into it: #{said(here.write("#{name}/note.txt", "hello\n", within: 1.minute))}")
  out.write_line("over the file: #{said(here.mkdir("#{name}/note.txt", within: 1.minute))}")
  case here.scoped(name).list(within: 1.minute)
    Ok(names): out.write_line("in it: #{names}")
    Error(_): out.write_line("in it: nothing")
  end
end

test "a folder made is listed before a file is in it, again is Ok, and a file in the way is Missing"
  fs = Fs.fixture()
  assert fs.mkdir("logs", within: 1.minute) is Ok(_)
  assert fs.mkdir("logs", within: 1.minute) is Ok(_)
  assert fs.list(within: 1.minute) == Ok(["logs"])
  assert fs.scoped("logs").list(within: 1.minute) == Ok([])
  assert fs.write("logs/a.log", "1\n", within: 1.minute) is Ok(_)
  assert fs.scoped("logs").list(within: 1.minute) == Ok(["a.log"])
  assert fs.mkdir("logs/a.log", within: 1.minute) is Error(Missing("logs/a.log"))
  assert fs.read("logs", within: 1.minute) is Error(Missing("logs"))
end

verified: types, contracts, tests (1), property (0 seeds), sim (not run)
          proven: not run
