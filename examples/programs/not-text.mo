# run: not-text.txt
# run: text.txt
module Programs.NotText
expose said

intent "A file that is not UTF-8 is NotText to every Fs row that gives a String or hands one on, and read_bytes still gives its bytes."

fn said(r: Result(T, FsError)) : String
  case r
    Ok(_): "ok"
    Error(Missing(path)): "missing #{path}"
    Error(Timeout): "timeout"
    Error(NotText): "not text"
  end
end

fn main(platform: Platform)
  data = platform.fs.scoped("bytes").read_only
  name = platform.args.first or "not-text.txt"
  out = platform.stdout
  out.write_line("read: #{said(data.read(name, within: 1.minute))}")
  out.write_line("read_lines: #{said(data.read_lines(name, within: 1.minute))}")
  handed = data.each_line(name, within: 1.minute, fn(line) out.write_line("| #{line}") end)
  out.write_line("each_line: #{said(handed)}")
  folded = data.fold_lines(name, 0, within: 1.minute, fn(total, line) total + line.byte_size end)
  case folded
    Ok(total): out.write_line("fold_lines: #{total} bytes of text")
    Error(_): out.write_line("fold_lines: #{said(folded)}")
  end
  read = data.read_bytes(name, within: 1.minute)
  case read
    Ok(bytes):
      out.write_line("read_bytes: #{bytes.size} bytes, #{bytes.count(fn(b) b > 127 end)} past ASCII")
    Error(_): out.write_line("read_bytes: #{said(read)}")
  end
end

test "a file the fixture does not hold is missing"
  assert said(Fs.fixture().read("a.txt", within: 1.minute)) == "missing a.txt"
end

verified: types, contracts, tests (1), property (0 seeds), sim (not run)
          proven: not run
