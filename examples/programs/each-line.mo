# run: lines.txt
# run: nothing.txt
# exit: 1
module Programs.EachLine
expose quoted

intent "Print a file in data/ one line at a time as it is read, through a scoped, read-only Fs."

fn quoted(line: String) : String
  "| #{line}"
end

fn main(platform: Platform)
  data = platform.fs.scoped("data").read_only
  name = platform.args.first or "lines.txt"
  out = platform.stdout
  case data.each_line(name, within: 1.minute, fn(line) out.write_line(quoted(line)) end)
    Ok(_): out.flush()
    Error(Missing(path)):
      platform.stderr.write("there is no #{path} in data/\n")
      platform.exit(1)
    Error(Timeout):
      platform.stderr.write("reading #{name} took longer than a minute\n")
      platform.exit(1)
  end
end

test "a line is quoted as it is"
  assert quoted("") == "| "
  assert quoted("a b") == "| a b"
end

verified: types, contracts, tests (1), property (0 seeds), sim (not run)
          proven: not run
