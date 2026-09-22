module Probe
expose round_trip, main

fn round_trip(seen: List(String), line: String) : List(String)
  case Json.decode(line)
    Ok(json): seen.push(Json.encode(json))
    Error(_): seen.push("error")
  end
end

fn main(platform: Platform)
  path = platform.args.first or ""
  read = platform.fs.read_only.fold_lines(path, [], within: 600.seconds,
    fn(seen, line) round_trip(seen, line) end)
  case read
    Ok(lines): platform.stdout.write("#{String.join(lines, "\n")}\n")
    Error(_): platform.exit(3)
  end
end
