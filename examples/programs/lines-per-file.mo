# run: data
module Programs.LinesPerFile
expose described_line

intent "List a folder through a scoped, read-only Fs and print each file's name, lines, and bytes, one line each."

fn described_line(name: String, lines: UInt64, bytes: UInt64) : String
  "#{name.pad_right(12, " ")} #{lines} lines, #{bytes} bytes"
end

fn described(folder: Fs, name: String) : String
  lines = folder.read_lines(name, within: 100.ms)
  bytes = folder.size(name, within: 100.ms)
  case (lines, bytes)
    (Ok(read), Ok(n)): described_line(name, read.size, n)
    _: "#{name} cannot be read"
  end
end

fn main(platform: Platform)
  folder = platform.fs.scoped(platform.args.first or "data").read_only
  case folder.list(within: 100.ms)
    Ok(names):
      for name in names
        platform.stdout.write_line(described(folder, name))
      end
    Error(_):
      platform.stderr.write_line("cannot list the folder")
      platform.exit(1)
  end
end

test "a line is padded to a column"
  assert described_line("a.txt", 2, 10) == "a.txt        2 lines, 10 bytes"
end
