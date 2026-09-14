module Agent.Tools
expose Call, Used, Came, Found, used, inside?, allowed?, url_host, url_port, url_path

use Agent.Model{Fake}

intent "Each tool over only what its row gives it: list_files, read_file, and search take the run's folder read-only, write_file takes the folder writable only when the run was granted it, http_get takes Http and the run's hosts, and now takes the Clock; a call naming a tool the run was not granted, a path outside its folder, or a host off its list is refused before any capability is touched, and the model sees the refusal."

never "a tool runs when it was not granted, or reaches outside its run's folder or hosts"
  for u in Used.all
    !u.refused and !u.allowed
  end
end

# A tool call as the model named it, with what the run granted.
struct Call
  tool: String
  args: Map(String, String)
  granted: List(String)
  hosts: List(String)
end

# What a call came to: the output the model sees, whether it was refused, and whether the call
# was one the run allows (granted, and inside its folder or hosts), judged apart from the tools.
struct Used
  output: String
  refused: Bool
  allowed: Bool
end

enum Came
  Said(text: String)
  Denied(why: String)
end

# Lines a search has found so far, and the files it has read.
struct Found
  lines: List(String)
  files: UInt64
end

# Runs a call. `reads` is the run's folder read-only; `writes` is the same folder, writable only
# when the run was granted write_file and read-only otherwise, so a write it was not granted could
# not happen even without the check here.
fn used(reads: Fs, writes: Fs, http: Http, clock: Clock, call: Call, by: Deadline) : Used
  ensures !call.granted.contains?(call.tool) implies result.refused

  came = if call.granted.contains?(call.tool)
    ran(reads, writes, http, clock, call, by)
  else
    Denied(why: "#{call.tool} is not granted to this run")
  end
  case came
    Said(text): Used(output: text, refused: false, allowed: allowed?(call))
    Denied(why): Used(output: why, refused: true, allowed: allowed?(call))
  end
end

fn ran(reads: Fs, writes: Fs, http: Http, clock: Clock, call: Call, by: Deadline) : Came
  case call.tool
    "list_files": listed(reads, arg(call, "path", "."), by)
    "read_file": read(reads, arg(call, "path", ""), by)
    "search": searched(reads, arg(call, "path", "."), arg(call, "query", ""), by)
    "write_file": written(writes, arg(call, "path", ""), arg(call, "text", ""), by)
    "http_get": got(http, call, by)
    "now": Said(text: clock.now.to_iso8601)
    _: Denied(why: "there is no tool #{call.tool}")
  end
end

# Whether the run allows a call: the tool granted, a path inside its folder, a host on its list.
fn allowed?(call: Call) : Bool
  return false if !call.granted.contains?(call.tool)
  case call.tool
    "list_files" | "search": inside?(arg(call, "path", "."))
    "read_file" | "write_file": inside?(arg(call, "path", ""))
    "http_get": listed_host?(call)
    "now": true
    _: false
  end
end

fn listed_host?(call: Call) : Bool
  url = arg(call, "url", "")
  host = url_host(url)
  url.starts_with?("http://") and (call.hosts.contains?(host) or call.hosts.contains?("#{host}:#{url_port(url)}"))
end

fn arg(call: Call, name: String, otherwise: String) : String
  call.args.get(name) or otherwise
end

# A path inside the run's folder: relative, at most 1 KiB, and no segment climbs out.
fn inside?(path: String) : Bool
  return false if path == "" or path.starts_with?("/") or path.byte_size > 1_024
  path.split("/").all?(fn(segment) segment != ".." end)
end

fn said(error: FsError, path: String) : Came
  case error
    Missing(_): Said(text: "#{path} is not there")
    Timeout: Said(text: "#{path} took longer than the call may")
    NotText: Said(text: "#{path} is not UTF-8 text")
  end
end

fn outside(path: String) : Came
  Denied(why: "#{path} is outside the run's folder")
end

fn listed(reads: Fs, path: String, by: Deadline) : Came
  return outside(path) if !inside?(path)
  case reads.scoped(path).list(within: by)
    Ok(names): Said(text: String.join(names, "\n"))
    Error(error): said(error, path)
  end
end

# A file's text, when it is at most 64 KiB.
fn read(reads: Fs, path: String, by: Deadline) : Came
  return outside(path) if !inside?(path)
  case reads.size(path, within: by)
    Ok(bytes):
      return Said(text: "#{path} is #{bytes} bytes, more than 64 KiB") if bytes > 65_536
      case reads.read(path, within: by)
        Ok(text): Said(text: text)
        Error(error): said(error, path)
      end
    Error(error): said(error, path)
  end
end

# The lines under a path that hold the query, as path:line: text, at most 200, from at most
# 1,000 files.
fn searched(reads: Fs, path: String, query: String, by: Deadline) : Came
  return outside(path) if !inside?(path)
  return Said(text: "search takes a query") if query == ""
  found = search_in(reads, path, query, Found(lines: [], files: 0), by)
  Said(text: String.join(found.lines.take(200), "\n"))
end

fn search_in(reads: Fs, path: String, query: String, so_far: Found, by: Deadline) : Found
  return so_far if so_far.lines.size >= 200 or so_far.files >= 1_000
  case reads.read_lines(path, within: by)
    Ok(lines): matched(so_far, path, lines, query)
    Error(_):
      case reads.scoped(path).list(within: by)
        Ok(names): each_in(reads, path, names, query, so_far, by)
        Error(_): so_far
      end
  end
end

fn each_in(reads: Fs, path: String, names: List(String), query: String, so_far: Found,
  by: Deadline) : Found
  var found = so_far
  for name in names
    if found.lines.size >= 200
      break
    end
    found = search_in(reads, joined(path, name), query, found, by)
  end
  found
end

fn joined(path: String, name: String) : String
  return name if path == "."
  "#{path}/#{name}"
end

fn matched(so_far: Found, path: String, lines: List(String), query: String) : Found
  hits = lines.enumerate.filter(fn(pair) pair.1.contains?(query) end)
  shown = hits.map(fn(pair) "#{path}:#{pair.0 + 1}: #{pair.1}" end)
  Found(lines: so_far.lines.concat(shown), files: so_far.files + 1)
end

fn written(writes: Fs, path: String, text: String, by: Deadline) : Came
  return outside(path) if !inside?(path)
  case writes.write(path, text, within: by)
    Ok(_): Said(text: "wrote #{text.byte_size} bytes to #{path}")
    Error(error): said(error, path)
  end
end

# A GET to a host on the run's list, over plain HTTP: its status and a body of at most 64 KiB.
fn got(http: Http, call: Call, by: Deadline) : Came
  url = arg(call, "url", "")
  return Denied(why: "http_get takes an http:// url") if !url.starts_with?("http://")
  host = url_host(url)
  port = url_port(url)
  return Denied(why: "#{host}:#{port} is not a host this run may reach") if !listed_host?(call)
  case http.send(Request(method: "GET", path: url_path(url)), host: host, port: port, within: by)
    Ok(response):
      return Said(text: "the body is more than 64 KiB") if response.body.byte_size > 65_536
      Said(text: "#{response.status}\n#{response.body}")
    Error(Timeout): Said(text: "#{host}:#{port} took longer than the call may")
    Error(Refused) | Error(Closed) | Error(Busy) | Error(Malformed) | Error(TooLarge) | Error(Unsupported):
      Said(text: "#{host}:#{port} did not answer with HTTP")
  end
end

# The part of an http:// url between the scheme and the path: host, or host:port.
fn authority(url: String) : String
  rest = url.slice(7, url.size)
  rest.slice(0, rest.index_of("/") or rest.size)
end

fn url_host(url: String) : String
  place = authority(url)
  place.slice(0, place.index_of(":") or place.size)
end

fn url_port(url: String) : UInt16
  place = authority(url)
  at = place.index_of(":") or place.size
  n = place.slice(at + 1, place.size).to_u64 or 80
  return 80 if n < 1 or n > 65_535
  n.to_u16
end

fn url_path(url: String) : String
  rest = url.slice(7, url.size)
  at = rest.index_of("/") or rest.size
  path = rest.slice(at, rest.size)
  return "/" if path == ""
  path
end

fn call(tool: String, args: Map(String, String), granted: List(String)) : Call
  Call(tool: tool, args: args, granted: granted, hosts: ["localhost"])
end

fn path_arg(path: String) : Map(String, String)
  Map.new().set("path", path)
end

test "the reading tools read only inside the run's folder"
  fs = Fs.fixture()
  by = Deadline.fixture(1.minute)
  assert fs.write("work/a.txt", "one\ntwo", within: 1.minute) is Ok(_)
  assert fs.write("work/notes/b.txt", "two three", within: 1.minute) is Ok(_)
  assert fs.write("secret.txt", "two", within: 1.minute) is Ok(_)
  folder = fs.scoped("work")
  all = ["list_files", "read_file", "search"]
  clock = Clock.fixture()
  http = Http.fixture()
  assert used(folder.read_only, folder, http, clock, call("read_file", path_arg("a.txt"), all),
    by) == Used(output: "one\ntwo", refused: false, allowed: true)
  listing = used(folder.read_only, folder, http, clock, call("list_files", path_arg("."), all), by)
  assert !listing.refused and listing.output.contains?("a.txt") and listing.output.contains?("notes")
  found = used(folder.read_only, folder, http, clock,
    call("search", Map.new().set("query", "two"), all), by)
  assert found.output.contains?("a.txt:2: two") and found.output.contains?("notes/b.txt:1: two three")
  assert !found.output.contains?("secret")
  up = used(folder.read_only, folder, http, clock,
    call("read_file", path_arg("../secret.txt"), all), by)
  assert up.refused and !up.allowed
  assert used(folder.read_only, folder, http, clock,
    call("read_file", path_arg("notes/../../secret.txt"), all), by).refused
  assert used(folder.read_only, folder, http, clock, call("list_files", path_arg("/"), all),
    by).refused
  missing = used(folder.read_only, folder, http, clock,
    call("read_file", path_arg("nope.txt"), all), by)
  assert missing == Used(output: "nope.txt is not there", refused: false, allowed: true)
end

test "a tool the run was not granted is refused before it runs, write_file among them"
  fs = Fs.fixture()
  by = Deadline.fixture(1.minute)
  assert fs.mkdir("work", within: 1.minute) is Ok(_)
  folder = fs.scoped("work")
  args = path_arg("out.txt").set("text", "hello")
  refusal = used(folder.read_only, folder, Http.fixture(), Clock.fixture(),
    call("write_file", args, ["read_file"]), by)
  assert refusal == Used(output: "write_file is not granted to this run", refused: true,
    allowed: false)
  assert fs.read("work/out.txt", within: 1.minute) is Error(_)
  wrote = used(folder.read_only, folder, Http.fixture(), Clock.fixture(),
    call("write_file", args, ["write_file"]), by)
  assert wrote == Used(output: "wrote 5 bytes to out.txt", refused: false, allowed: true)
  assert fs.read("work/out.txt", within: 1.minute) == Ok("hello")
  assert used(folder.read_only, folder, Http.fixture(), Clock.fixture(),
    call("write_file", path_arg("../x"), ["write_file"]), by).refused
  assert used(folder.read_only, folder, Http.fixture(), Clock.fixture(),
    call("now", Map.new(), ["now"]), by) == Used(output: "2026-01-01T00:00:00Z", refused: false,
    allowed: true)
  assert used(folder.read_only, folder, Http.fixture(), Clock.fixture(),
    call("rm", Map.new(), ["rm"]), by).refused
end

test "a file over 64 KiB is not read, and a search stops at 200 lines"
  fs = Fs.fixture()
  by = Deadline.fixture(1.minute)
  assert fs.write("work/big.txt", "x".repeat(65_537), within: 1.minute) is Ok(_)
  assert fs.write("work/many.txt", "hit\n".repeat(300), within: 1.minute) is Ok(_)
  folder = fs.scoped("work")
  big = used(folder.read_only, folder, Http.fixture(), Clock.fixture(),
    call("read_file", path_arg("big.txt"), ["read_file"]), by)
  assert !big.refused and big.output.contains?("more than 64 KiB")
  hits = used(folder.read_only, folder, Http.fixture(), Clock.fixture(),
    call("search", Map.new().set("query", "hit"), ["search"]), by)
  assert hits.output.lines.size == 200
end

test "http_get reaches only a host on the run's list"
  http = Http.fixture()
  assert http.listen(0, within: 1.minute) is Ok(listener)
  listener.serve(into: Fake.start(["hello"], Fs.fixture()), idle: 5_000.ms)
  fs = Fs.fixture()
  url = Map.new().set("url", "http://localhost:#{listener.port}/page?x=1")
  heard = used(fs.read_only, fs, http, Clock.fixture(), call("http_get", url, ["http_get"]),
    Deadline.fixture(1.minute))
  assert !heard.refused and heard.allowed
  assert heard.output == "200\nhello" or heard.output.ends_with?("did not answer with HTTP") or heard.output.ends_with?("took longer than the call may")
  away = Map.new().set("url", "http://example.com/")
  assert used(fs.read_only, fs, http, Clock.fixture(), call("http_get", away, ["http_get"]),
    Deadline.fixture(1.minute)).refused
  plain = Map.new().set("url", "https://localhost/")
  assert used(fs.read_only, fs, http, Clock.fixture(), call("http_get", plain, ["http_get"]),
    Deadline.fixture(1.minute)).refused
  assert url_host("http://h:81/a") == "h" and url_port("http://h:81/a") == 81
  assert url_port("http://h/a") == 80 and url_path("http://h") == "/"
  assert url_path("http://h:1/a/b?c=d") == "/a/b?c=d"
end

verified: types, contracts, tests (4), property (0 seeds), sim (100 runs)
          proven: not run
