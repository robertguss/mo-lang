# run: lines.txt
module Programs.CountLines
expose count_lines

intent "Count the lines of a file in data/, read through a scoped, read-only Fs."

fn count_lines(text: String) : UInt64
  text.bytes.filter(fn(b) b == 10 end).size
end

fn main(platform: Platform)
  data = platform.fs.scoped("data").read_only
  name = platform.args.first or "lines.txt"
  case data.read(name, within: 100.ms)
    Ok(text): platform.stdout.write("#{count_lines(text)} lines in #{name}\n")
    Error(Missing(path)):
      platform.stderr.write("there is no #{path} in data/\n")
      platform.exit(1)
    Error(Timeout):
      platform.stderr.write("reading #{name} took longer than 100 ms\n")
      platform.exit(1)
  end
end

test "a line ends at a newline"
  assert count_lines("") == 0
  assert count_lines("one\ntwo\n") == 2
end

verified: types, contracts, tests (1), property (0 seeds), sim (not run)
          proven: not run
