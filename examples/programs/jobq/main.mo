# run: check data/demo data/session.txt
# run: compact data/compact
# run: serve
# exit: 2
# run: serve data/nowhere
# exit: 1
# run: client 127.0.0.1 1 p GET /jobs
# exit: 1
# run: verify data/demo
# run: verify data/ill
# exit: 1
module Jobq.Main
expose Place, Trip, Measured, Task, Problem, Folder, task, steady, serving?, main

use Jobq.Bench{Load, loaded, paired, rate_line, resident_mib, seconds}
use Jobq.Board{Call, Decision, Outcome, decide, folded_in, health_of, ill_formed, records, shelf_records, shelf_snapshot, snapshot}
use Jobq.Job{id_of, tagged, to_ms}
use Jobq.Queue{Opening, Policy, opening, policy, pruned_every, retained, shelf_lines}
use Jobq.Server{serving}
use Jobq.Store{Table, StoreError, bytes, count, cut_short?, journaled, line_of, lines, open, open_log, pairs, rewritten, writing_to}

intent "Run jobq: serve a folder's jobs over HTTP, compact its log to one line per live job in the names this version writes and its archive to one line per archived job, verify a folder and its archive without serving it, prune its archive of the jobs older than an age, measure it with bench (creates and lease-and-ack pairs a second, resident memory, and a restart, on a free port), send one request as a client, or check a folder by serving it on a free port and playing a script through the client; every command that opens a folder refuses one that holds a record the API could never have produced, a usage error exits 2, and a folder, a port, or a server that cannot be had exits 1."

# Where to serve, and how the service keeps going: its restart budget and its chaos switch.
struct Place
  dir: String
  port: UInt16
  rules: Policy
end

# One request from the client: where to, the token (- for none), and the request.
struct Trip
  host: String
  port: UInt16
  token: String
  method: String
  path: String
  json: String
end

# What bench measures: the folder it serves, the jobs it creates, and the workers that lease them.
struct Measured
  dir: String
  jobs: UInt64
  workers: UInt64
end

enum Task
  Serving(place: Place)
  Compacting(dir: String)
  Verifying(dir: String)
  Asking(trip: Trip)
  Checking(dir: String, script: String)
  Trimming(dir: String, older_than_ms: UInt64)
  Benching(measured: Measured)
end

# A folder's two logs, replayed: the live log and the archive.
struct Folder
  live: Table
  shelf: Table
end

enum Problem
  Usage(detail: String)
  Unopened(dir: String, why: String)
  Ill(dir: String, key: String, rule: String)
  Unbound(port: UInt16)
  Unreached(host: String, port: UInt16)
end

fn usage() : String
  "usage: jobq serve <dir> [--port N] [--max-restarts K] [--restart-window S] [--crash-every N] [--retain-ms N] [--retention <ms>] | jobq compact <dir> | jobq verify <dir> | jobq prune <dir> --older-than-ms <n> | jobq bench <dir> [--jobs N] [--workers N] | jobq client <host> <port> <token> <method> <path> [<json>] | jobq check <dir> <script>"
end

fn task(args: List(String)) : Result(Task, Problem)
  rest = args.drop(1)
  case args.first or ""
    "serve": to_serve(rest)
    "compact": compacting(rest)
    "verify": verifying(rest)
    "client": asking(rest)
    "check": checking(rest)
    "prune": trimming(rest)
    "bench": benching(rest)
    "": Error(Usage(detail: "no command given"))
    _: Error(Usage(detail: "unknown command #{args.first or ""}"))
  end
end

# The place a serve starts from: port 7900, five restarts a minute, no chaos, and done and dead
# jobs kept a day before they are archived.
fn place_of(dir: String) : Place
  Place(dir: dir, port: 7_900, rules: policy(5, 60_000, 0))
end

fn to_serve(args: List(String)) : Result(Task, Problem)
  dir = try dir_of(args)
  flags = args.drop(1)
  if flags.size % 2 != 0
    return Error(Usage(detail: "serve takes a folder and then flags, each with its value"))
  end
  var place = place_of(dir)
  var seen = flags.take(0)
  for i in 0..flags.size / 2
    name = flags.get(i * 2) or ""
    return Error(Usage(detail: "serve takes #{name} once")) if seen.contains?(name)
    seen = seen.push(name)
    place = try flagged(place, name, flags.get(i * 2 + 1) or "")
  end
  Ok(Serving(place: place))
end

# The place with one flag's value set.
fn flagged(place: Place, name: String, value: String) : Result(Place, Problem)
  var set = place
  case name
    "--port":
      set.port = try port_of(value)
    "--max-restarts":
      set.rules.max_restarts = try number_of(name, value, 0, 1_000)
    "--restart-window":
      set.rules.window_ms = (try number_of(name, value, 1, 86_400)) * 1_000
    "--crash-every":
      set.rules.crash_every = try number_of(name, value, 0, 1_000_000_000)
    "--retain-ms":
      set.rules = retained(set.rules, try number_of(name, value, 1_000, 2_678_400_000))
    "--retention":
      set.rules = pruned_every(set.rules, try age_of(name, value, true))
    _:
      return Error(Usage(detail: "serve takes --port, --max-restarts, --restart-window, --crash-every, --retain-ms, and --retention, not #{name}"))
  end
  Ok(set)
end

# A flag's whole number, from `least` to `most`.
fn number_of(name: String, text: String, least: UInt64, most: UInt64) : Result(UInt64, Problem)
  ensures result is Ok(n) implies n >= least and n <= most

  n = text.to_u64 or most + 1
  return Ok(n) if n >= least and n <= most
  Error(Usage(detail: "#{name} takes a whole number from #{least} to #{most}, not #{text}"))
end

# An age to prune at: a whole number of milliseconds from 1,000 to a hundred years, or 0 for never
# where the flag allows it.
fn age_of(name: String, text: String, or_never: Bool) : Result(UInt64, Problem)
  n = text.to_u64 or 0
  return Ok(0) if or_never and text == "0"
  return Ok(n) if n >= 1_000 and n <= 3_153_600_000_000
  least = if or_never: "0 or from 1000" else: "from 1000"
  Error(Usage(detail: "#{name} takes a whole number of milliseconds #{least} to 3153600000000, not #{text}"))
end

# prune takes a folder and --older-than-ms with its age, and nothing else.
fn trimming(args: List(String)) : Result(Task, Problem)
  dir = try dir_of(args)
  if args.size != 3 or args.get(1) != Some("--older-than-ms")
    return Error(Usage(detail: "prune takes a folder and --older-than-ms <n>"))
  end
  ms = try age_of("--older-than-ms", args.get(2) or "", false)
  Ok(Trimming(dir: dir, older_than_ms: ms))
end

# bench takes a folder and, in any order, once each, --jobs (30,000 by default) and --workers (32).
fn benching(args: List(String)) : Result(Task, Problem)
  dir = try dir_of(args)
  flags = args.drop(1)
  if flags.size % 2 != 0
    return Error(Usage(detail: "bench takes a folder and then flags, each with its value"))
  end
  var jobs = 30_000
  var workers = 32
  var seen = flags.take(0)
  for i in 0..flags.size / 2
    name = flags.get(i * 2) or ""
    value = flags.get(i * 2 + 1) or ""
    return Error(Usage(detail: "bench takes #{name} once")) if seen.contains?(name)
    seen = seen.push(name)
    if name == "--jobs"
      jobs = try number_of(name, value, 8, 10_000_000)
    else
      if name != "--workers"
        return Error(Usage(detail: "bench takes --jobs and --workers, not #{name}"))
      end
      workers = try number_of(name, value, 1, 1_024)
    end
  end
  Ok(Benching(measured: Measured(dir: dir, jobs: jobs, workers: workers)))
end

fn compacting(args: List(String)) : Result(Task, Problem)
  dir = try dir_of(args)
  return Error(Usage(detail: "compact takes one folder")) if args.size != 1
  Ok(Compacting(dir: dir))
end

fn verifying(args: List(String)) : Result(Task, Problem)
  dir = try dir_of(args)
  return Error(Usage(detail: "verify takes one folder")) if args.size != 1
  Ok(Verifying(dir: dir))
end

fn asking(args: List(String)) : Result(Task, Problem)
  if args.size < 5
    return Error(Usage(detail: "client takes a host, a port, a token, a method, and a path"))
  end
  port = try port_of(args.get(1) or "")
  trip = try trip_of(args.drop(2), args.first or "", port)
  Ok(Asking(trip: trip))
end

# A token, a method, a path, and any JSON after them, joined by spaces as they were split.
fn trip_of(words: List(String), host: String, port: UInt16) : Result(Trip, Problem)
  if words.size < 3
    return Error(Usage(detail: "a request is a token, a method, a path, and any JSON"))
  end
  Ok(Trip(host: host, port: port, token: words.first or "", method: words.get(1) or "",
    path: words.get(2) or "", json: String.join(words.drop(3), " ")))
end

fn checking(args: List(String)) : Result(Task, Problem)
  dir = try dir_of(args)
  return Error(Usage(detail: "check takes a folder and a script")) if args.size != 2
  Ok(Checking(dir: dir, script: args.get(1) or ""))
end

fn dir_of(args: List(String)) : Result(String, Problem)
  dir = args.first or ""
  return Error(Usage(detail: "no folder given")) if dir == "" or dir.starts_with?("-")
  Ok(dir)
end

fn port_of(text: String) : Result(UInt16, Problem)
  ensures result is Ok(port) implies port >= 1

  n = text.to_u64 or 0
  return Error(Usage(detail: "a port is a number from 1 to 65535, not #{text}")) if n < 1 or n > 65_535
  Ok(n.to_u16)
end

fn ran(http: Http, fs: Fs, clock: Clock, out: Out, err: Out, args: List(String)) : Result(String,
  Problem)
  given = try task(args)
  case given
    Serving(place): serve(http, fs, clock, out, err, place)
    Compacting(dir):
      opened = try opened_store(fs, err, dir)
      compacted(fs, dir, opened, clock.now)
    Verifying(dir):
      opened = try opened_store(fs.read_only, err, dir)
      counted(opened, clock.now)
    Asking(trip): client(http, trip)
    Checking(dir: dir, script: script):
      lines = try script_of(fs, script)
      opened = try opened_store(fs.read_only, err, dir)
      check(http, fs, clock, opened, lines)
    Trimming(dir: dir, older_than_ms: ms):
      opened = try opened_store(fs, err, dir)
      trimmed(fs, dir, opened, ms, clock.now)
    Benching(measured): bench(http, fs, clock, err, None, measured)
  end
end

# Serves a folder until jobq is stopped. A log or an archive whose last line was cut short is
# written whole first, so the next change starts on a line of its own.
fn serve(http: Http, fs: Fs, clock: Clock, out: Out, err: Out, place: Place) : Result(String,
  Problem)
  opened = try opened_store(fs, err, place.dir)
  start = try opening_of(opened, clock.now)
  cut = cut_short?(opened.live) or cut_short?(opened.shelf)
  whole = if cut: try compacted_from(fs, place.dir, start) else: start
  case http.listen(place.port, within: 5_000.ms)
    Ok(listener):
      queue = serving(listener, fs, clock, whole, place.rules)
      queue.send(Sweep)
      out.write_line("jobq: serving #{place.dir} on 127.0.0.1:#{listener.port}")
      out.flush
      Ok("")
    Error(_): Error(Unbound(port: place.port))
  end
end

fn opening_of(opened: Folder, now: Time) : Result(Opening, Problem)
  case opening(opened.live, opened.shelf, now)
    Some(start): Ok(start)
    None:
      Error(Unopened(dir: opened.live.dir, why: "holds a jobq.log with a record that is not a job"))
  end
end

# The log written whole from the board the stores replayed: one line per live job, in the names
# this version writes, so a log the previous version wrote leaves no old name behind, and no
# stale record of an archived job; then the archive written whole, one line per archived job and
# no tombstone; a folder with no archive file gets an empty one. The log goes first: a kill between
# the two leaves every tombstone standing over the log it guards.
#
# Renames and prunes (the marks) are folded in: every record in the queue it is in now, every
# pruned job gone, and no mark record and no count left. While the archive still holds records in
# old names or pruned ones, the log keeps its marks, so a folder with marks is written in four
# steps: the log with its marks and its records carrying their count; the archive in the new names,
# without the pruned jobs, carrying the count; the log without the marks and with no count; and the
# archive with no count. A kill between any two writes leaves a folder that opens to the same jobs
# in the same queues, and one between the last two numbers the next mark past the count the archive
# still carries.
fn compacted_from(fs: Fs, dir: String, start: Opening) : Result(Opening, Problem)
  kept = try whole_log(fs, dir, start.table, snapshot(start.board).map(fn(w) line_of(w) end))
  archive = try whole_log(fs, dir, start.archive, shelf_lines(shelf_snapshot(start.board)))
  return Ok(Opening(board: start.board, table: kept, archive: archive)) if start.board.marks == 0
  folded = folded_in(start.board)
  table = try whole_log(fs, dir, kept, snapshot(folded).map(fn(w) line_of(w) end))
  plain = try whole_log(fs, dir, archive, shelf_lines(shelf_snapshot(folded)))
  Ok(Opening(board: folded, table: table, archive: plain))
end

# A log written whole, except an empty one that was empty before, which is left as it is, so
# a folder that never archived a job gets no archive file.
fn whole_log(fs: Fs, dir: String, table: Table, lines: List(String)) : Result(Table, Problem)
  return Ok(table) if lines.size == 0 and bytes(table) == 0
  case rewritten(fs, table, lines)
    Ok(written): Ok(written)
    Error(_): Error(Unopened(dir: dir, why: "holds a #{table.base} jobq could not rewrite"))
  end
end

fn compacted(fs: Fs, dir: String, opened: Folder, now: Time) : Result(String, Problem)
  start = try opening_of(opened, now)
  whole = try compacted_from(fs, dir, start)
  live = "jobq: compacted #{dir}/jobq.log from #{lines(opened.live)} lines to #{lines(whole.table)}"
  return Ok("#{live}\n") if lines(opened.shelf) == 0
  Ok("#{live}, and #{dir}/jobq.archive from #{lines(opened.shelf)} to #{lines(whole.archive)}\n")
end

# What a folder holds once it opens, for an operator who wants to know before serving it: its
# jobs by state, the id the next create would take, and the jobs in the archive.
fn counted(opened: Folder, now: Time) : Result(String, Problem)
  start = try opening_of(opened, now)
  counts = health_of(start.board, now)
  jobs = counts.queued + counts.scheduled + counts.leased + counts.done + counts.dead
  states = "queued #{counts.queued}, scheduled #{counts.scheduled}, leased #{counts.leased}"
  ended = "done #{counts.done}, dead #{counts.dead}"
  Ok("#{jobs} jobs: #{states}, #{ended}; next id #{id_of(start.board.next)}; archived #{counts.archived}\n")
end

# The archive pruned offline, as a prune over HTTP does: one record in the log, on disk before the
# counts are printed, after the archive's changes the same look made; nothing written when nothing
# is old enough. A log or an archive whose last line was cut short is written whole first.
fn trimmed(fs: Fs, dir: String, opened: Folder, ms: UInt64, now: Time) : Result(String, Problem)
  start = try opening_of(opened, now)
  cut = cut_short?(opened.live) or cut_short?(opened.shelf)
  whole = if cut: try compacted_from(fs, dir, start) else: start
  decision = decide(whole.board, Call(worker: "", command: Pruning(older_than_ms: ms)), to_ms(now))
  if decision.outcome is Cleared(pruned: pruned, remaining: remaining)
    wrote = try written(fs, dir, whole, decision)
    return Ok("jobq: pruned #{pruned} archived jobs from #{dir}; #{remaining} remain; #{wrote} lines written\n")
  end
  Error(Unopened(dir: dir, why: "holds an archive jobq could not prune"))
end

# A decision's archive changes, then its records, appended; gives the lines written.
fn written(fs: Fs, dir: String, whole: Opening, decision: Decision) : Result(UInt64, Problem)
  shelf = shelf_lines(decision.shelved)
  live = decision.writes.map(fn(w) line_of(w) end)
  if journaled(fs, whole.archive, shelf) is Error(_)
    return Error(Unopened(dir: dir, why: "holds a jobq.archive jobq could not write"))
  end
  if journaled(fs, whole.table, live) is Error(_)
    return Error(Unopened(dir: dir, why: "holds a jobq.log jobq could not write"))
  end
  Ok(shelf.size + live.size)
end

# Serves a folder on a free port, then measures it from inside the same program as the round's
# measure.py does from outside: `jobs` creates from 8 producers, lease-and-ack pairs for 10 seconds
# from 1 worker and then from `workers`, the resident memory after the pairs, and the time a
# second service takes to open the folder again and answer /health. The first service is left
# serving until bench exits, so the restart measures the replay, not a stop.
fn bench(http: Http, fs: Fs, clock: Clock, err: Out, runtime: Option(Runtime),
  measured: Measured) : Result(String, Problem)
  dir = measured.dir
  jobs = measured.jobs
  workers = measured.workers
  if fs.mkdir(dir, within: 10_000.ms) is Error(_)
    return Error(Unopened(dir: dir, why: "is not a folder jobq can make or use"))
  end
  load = load_average(fs)
  port = try served_on(http, fs, clock, err, dir)
  made = loaded(http, clock, port, jobs)
  one = paired(http, clock, port, 1, 10_000)
  many = paired(http, clock, port, workers, 10_000)
  resident = resident_mib(fs, runtime) or "n/a"
  began = clock.now
  opened = try opened_store(fs, err, dir)
  again = try served_on(http, fs, clock, err, dir)
  up = health_within(http, again)
  took = (clock.now - began).ms.to_u64
  size = (bytes(opened.live) + bytes(opened.shelf)) / 1_000_000
  head = "jobq bench: #{dir}, #{jobs} jobs, #{workers} workers; load average before #{load}"
  counts = [rate_line("creates", made),
    rate_line("pairs, 1 worker", one),
    rate_line("pairs, #{workers} worker#{if workers == 1: "" else: "s"}", many)]
  tail = ["resident memory after the pairs: #{resident} MiB",
    "restart with a #{size} MB log: #{seconds(took)} s to /health#{if up: "" else: " (no 200)"}"]
  Ok("#{String.join([head].concat(counts).concat(tail), "\n")}\n")
end

# The folder served on a free port, as serve serves it; the port.
fn served_on(http: Http, fs: Fs, clock: Clock, err: Out, dir: String) : Result(UInt16, Problem)
  opened = try opened_store(fs, err, dir)
  start = try opening_of(opened, clock.now)
  cut = cut_short?(opened.live) or cut_short?(opened.shelf)
  whole = if cut: try compacted_from(fs, dir, start) else: start
  case http.listen(0, within: 5_000.ms)
    Ok(listener):
      queue = serving(listener, fs, clock, whole, policy(5, 60_000, 0))
      queue.send(Sweep)
      Ok(listener.port)
    Error(_): Error(Unbound(port: 0))
  end
end

# Whether /health answers 200, asked up to 100 times.
fn health_within(http: Http, port: UInt16) : Bool
  var up = false
  for _ in 0..100
    got = http.send(Request(method: "GET", path: "/health"), host: "127.0.0.1", port: port,
      within: 10_000.ms)
    up = got is Ok(response) and response.status == 200
    if up
      break
    end
  end
  up
end

# The machine's load averages over 1, 5, and 15 minutes, from /proc/loadavg, or n/a.
fn load_average(fs: Fs) : String
  case fs.read_only.fold_lines("/proc/loadavg", "", within: 5_000.ms, fn(_, line) line end)
    Ok(line): String.join(line.split(" ").take(3), " ")
    Error(_): "n/a"
  end
end

fn client(http: Http, trip: Trip) : Result(String, Problem)
  case http.send(request_of(trip), host: trip.host, port: trip.port, within: 10_000.ms)
    Ok(response): Ok(shown(response))
    Error(_): Error(Unreached(host: trip.host, port: trip.port))
  end
end

fn request_of(trip: Trip) : Request
  headers = if trip.token == "-"
    Map.new()
  else
    Map.new().set("authorization", "Bearer #{trip.token}")
  end
  Request(method: trip.method, path: path_of(trip.path), query: query_of(trip.path),
    headers: headers, body: trip.json)
end

# The path before a ?, and the query after it split into its pairs, as the client writes them.
fn path_of(target: String) : String
  target.slice(0, target.index_of("?") or target.size)
end

fn query_of(target: String) : Map(String, String)
  at = target.index_of("?") or target.size
  pairs = target.slice(at + 1, target.size).split("&").filter(fn(pair) pair != "" end)
  pairs.reduce(Map.new(), fn(query, pair)
    query.set(pair.slice(0, pair.index_of("=") or pair.size),
      pair.slice((pair.index_of("=") or pair.size) + 1, pair.size))
  end)
end

# A response as the client prints it: the status, then the body when there is one.
fn shown(response: Response) : String
  return "#{response.status}\n" if response.body == ""
  "#{response.status} #{response.body}\n"
end

# Serves a folder's jobs on a free port and plays a script through the client, each line a
# request of its own; the transcript is every line sent and what came back, with the times the
# clock gives steadied. The folder's log and archive are only read: the changes go to
# jobq.check.log and jobq.check.archive beside them, removed before and after.
fn check(http: Http, fs: Fs, clock: Clock, opened: Folder, lines: List(String)) : Result(String,
  Problem)
  dir = opened.live.dir
  folder = fs.scoped(dir)
  if !cleared(folder)
    return Error(Unopened(dir: dir, why: "holds a jobq.check file jobq cannot remove"))
  end
  moved = Folder(live: writing_to(opened.live, "jobq.check.log"),
    shelf: writing_to(opened.shelf, "jobq.check.archive"))
  start = try opening_of(moved, clock.now)
  case http.listen(0, within: 5_000.ms)
    Ok(listener):
      transcript = checked_on(http, listener, fs, clock, start, lines)
      return Ok(transcript) if cleared(folder)
      Error(Unopened(dir: dir, why: "holds a jobq.check file jobq cannot remove"))
    Error(_): Error(Unbound(port: 0))
  end
end

fn cleared(folder: Fs) : Bool
  gone(folder, "jobq.check.log") and gone(folder, "jobq.check.archive")
end

fn gone(folder: Fs, name: String) : Bool
  removed = folder.remove(name, within: 10_000.ms) is Ok(_)
  removed or folder.size(name, within: 10_000.ms) is Error(Missing(_))
end

fn checked_on(http: Http, listener: HttpListener, fs: Fs, clock: Clock, start: Opening,
  lines: List(String)) : String
  queue = serving(listener, fs, clock, start, policy(5, 60_000, 0))
  queue.send(Sweep)
  var transcript = ""
  for line in lines
    heard = played(http, line, listener.port)
    transcript = "#{transcript}> #{line}\n#{steady(heard)}"
  end
  transcript
end

fn played(http: Http, line: String, port: UInt16) : String
  case trip_of(line.split(" "), "127.0.0.1", port)
    Ok(trip):
      case client(http, trip)
        Ok(text): text
        Error(problem): "#{said(problem)}\n"
      end
    Error(problem): "#{said(problem)}\n"
  end
end

# A transcript with what depends on the clock replaced: each job's times, the time it runs at,
# the time it was archived, and the uptime.
fn steady(text: String) : String
  times = masked(masked(text, "created_at", true), "updated_at", true)
  waits = masked(masked(times, "run_at", true), "archived_at", true)
  shelf = masked(masked(waits, "oldest_archived_at", true), "bytes", false)
  masked(masked(shelf, "lease_until", true), "uptime_ms", false)
end

# The value under the key masked wherever it appears; a quoted one only when it is a string, so a
# null stays null.
fn masked(text: String, key: String, quoted: Bool) : String
  label = "\"#{key}\": "
  pieces = text.split(label)
  mark = if quoted: "\"<#{key}>\"" else: "<#{key}>"
  rest = pieces.drop(1).map(fn(piece)
    if quoted and !piece.starts_with?("\"")
      "#{label}#{piece}"
    else
      "#{label}#{mark}#{after_value(piece, quoted)}"
    end
  end)
  String.join([pieces.first or ""].concat(rest), "")
end

# What follows a JSON value at the start of a piece: past the closing quote of a string, or
# from the first , or } after a number.
fn after_value(piece: String, quoted: Bool) : String
  if quoted
    inside = piece.slice(1, piece.size)
    return inside.slice((inside.index_of("\"") or 0) + 1, inside.size)
  end
  ends = [piece.index_of(","), piece.index_of("}")].flat_map(fn(at) found(at) end)
  piece.slice(ends.min or piece.size, piece.size)
end

fn found(at: Option(UInt64)) : List(UInt64)
  case at
    Some(i): [i]
    None: []
  end
end

fn script_of(fs: Fs, script: String) : Result(List(String), Problem)
  case fs.read_only.read_lines(script, within: 10_000.ms)
    Ok(lines): Ok(lines)
    Error(Missing(_)): Error(Unopened(dir: script, why: "is not a script jobq can read"))
    Error(Timeout): Error(Unopened(dir: script, why: "took longer than 10 seconds to read"))
    Error(NotText): Error(Unopened(dir: script, why: "is not UTF-8 text"))
  end
end

# The folder's store and archive, replayed; a folder with no archive has an empty one. A last
# line cut short is left out and said on stderr, once, at once.
fn opened_store(fs: Fs, err: Out, dir: String) : Result(Folder, Problem)
  live = try replayed(fs, err, dir, "jobq.log")
  shelf = try replayed(fs, err, dir, "jobq.archive")
  whole(Folder(live: live, shelf: shelf))
end

fn replayed(fs: Fs, err: Out, dir: String, name: String) : Result(Table, Problem)
  case open_log(fs, dir, name)
    Ok(table):
      if cut_short?(table)
        err.write_line("jobq: the last line of #{dir}/#{name} was cut short, so it is left out")
        err.flush
      end
      Ok(table)
    Error(problem): Error(Unopened(dir: dir, why: why_unopened(problem, name)))
  end
end

# Every record, live and archived, checked against the job's rules before anything is served,
# compacted, or verified: the first that breaks one refuses the folder, naming the record and the
# rule.
fn whole(opened: Folder) : Result(Folder, Problem)
  case ill_formed(pairs(opened.live), pairs(opened.shelf))
    Some(bad): Error(Ill(dir: opened.live.dir, key: bad.0, rule: bad.1))
    None: Ok(opened)
  end
end

fn why_unopened(problem: StoreError, name: String) : String
  case problem
    NoFolder: "is not a folder jobq can read"
    Unreadable: "holds a #{name} jobq cannot read"
    Slow: "took longer than ten minutes to read"
    BadLine(number): "holds a #{name} whose line #{number} is not a SET or a DEL"
    Unwritten | Torn: "holds a #{name} jobq could not write"
  end
end

fn said(problem: Problem) : String
  case problem
    Usage(detail): "#{detail}; #{usage()}"
    Unopened(dir: dir, why: why): "#{dir} #{why}"
    Ill(dir: dir, key: key, rule: rule): "#{dir}: record #{key}: #{rule}"
    Unbound(port): "cannot listen on 127.0.0.1:#{port}"
    Unreached(host: host, port: port): "no jobq answered at #{host}:#{port}"
  end
end

fn code_of(problem: Problem) : UInt8
  case problem
    Usage(_): 2
    Unopened(dir: _, why: _): 1
    Ill(dir: _, key: _, rule: _): 1
    Unbound(_): 1
    Unreached(host: _, port: _): 1
  end
end

# Whether the arguments say to serve, which goes on until jobq is stopped.
fn serving?(args: List(String)) : Bool
  task(args) is Ok(Serving(_))
end

# Serving goes on until jobq is stopped; every other command ends jobq with exit once it is done,
# since check serves a listener of its own.
fn main(platform: Platform)
  args = platform.args
  outcome = case task(args)
    Ok(Benching(measured)):
      bench(platform.http, platform.fs, platform.clock, platform.stderr, platform.runtime, measured)
    Ok(_) | Error(_):
      ran(platform.http, platform.fs, platform.clock, platform.stdout, platform.stderr, args)
  end
  case outcome
    Ok(text):
      platform.stdout.write(text)
      if !serving?(args)
        platform.exit(0)
      end
    Error(problem):
      platform.stderr.write_line("jobq: #{said(problem)}")
      platform.exit(code_of(problem))
  end
end

# A record as the previous version wrote it, with attempts and max_attempts and no backoff.
fn old_record(id: String, state: String, attempts: UInt64) : String
  "{\"id\": \"#{id}\", \"queue\": \"emails\", \"state\": \"#{state}\", \"payload\": \"p\", \"attempts\": #{attempts}, \"max_attempts\": 3, \"created_at\": \"2026-09-14T09:00:00Z\", \"updated_at\": \"2026-09-14T09:05:00Z\"}"
end

# A record as this version writes it, done at 09:05 and archived at 10:00.
fn archived_record(id: String, key: String) : String
  "{\"id\": \"#{id}\", \"queue\": \"emails\", \"key\": \"#{key}\", \"state\": \"done\", \"payload\": \"p\", \"tries\": 1, \"max_tries\": 3, \"backoff_ms\": 0, \"created_at\": \"2026-09-14T09:00:00Z\", \"updated_at\": \"2026-09-14T09:05:00Z\", \"archived_at\": \"2026-09-14T10:00:00Z\"}"
end

# A record as this version writes it, in `queue`, queued, with the renames it carries.
fn queued_record(id: String, queue: String, renames: UInt64) : String
  seen = if renames == 0: "" else: ", \"renames\": #{renames}"
  "{\"id\": \"#{id}\", \"queue\": \"#{queue}\", \"state\": \"queued\", \"payload\": \"p\", \"tries\": 0, \"max_tries\": 3, \"backoff_ms\": 0, \"created_at\": \"2026-09-14T09:00:00Z\", \"updated_at\": \"2026-09-14T09:05:00Z\"#{seen}}"
end

test "serve takes a folder and an optional port, 7900 by default"
  assert task(["serve", "data"]) == Ok(Serving(place: place_of("data")))
  assert serving?(["serve", "data"])
  assert !serving?(["compact", "data"])
  assert task(["serve",
    "data",
    "--port",
    "8000"]) == Ok(Serving(place: Place(dir: "data", port: 8_000, rules: policy(5, 60_000, 0))))
end

test "serve takes a restart budget and a chaos switch, 5 in 60 seconds and 0 by default, in any order"
  rules = policy(2, 10_000, 7)
  words = ["serve", "d", "--crash-every", "7", "--max-restarts", "2", "--restart-window", "10"]
  assert task(words) == Ok(Serving(place: Place(dir: "d", port: 7_900, rules: rules)))
  with_port = ["serve", "d", "--restart-window", "10", "--port", "8000"]
  assert task(with_port) == Ok(Serving(place: Place(dir: "d", port: 8_000,
    rules: policy(5, 10_000, 0))))
  no_restarts = Place(dir: "d", port: 7_900, rules: policy(0, 60_000, 0))
  assert task(["serve", "d", "--max-restarts", "0"]) == Ok(Serving(place: no_restarts))
  assert serving?(words)
  assert task(["serve", "d", "--crash-every"]) is Error(Usage(_))
  assert task(["serve", "d", "--crash-every", "-1"]) is Error(Usage(_))
  assert task(["serve", "d", "--crash-every", "x"]) is Error(Usage(_))
  assert task(["serve", "d", "--restart-window", "0"]) is Error(Usage(_))
  assert task(["serve", "d", "--restart-window", "86401"]) is Error(Usage(_))
  assert task(["serve", "d", "--max-restarts", "1001"]) is Error(Usage(_))
  assert task(["serve", "d", "--max-restarts", "1", "--max-restarts", "2"]) is Error(Usage(_))
  assert task(["serve", "d", "--port", "1", "--budget", "2"]) is Error(Usage(_))
  assert task(["check", "d", "s.txt", "--crash-every", "2"]) is Error(Usage(_))
  assert task(["compact", "d", "--crash-every", "2"]) is Error(Usage(_))
  assert task(["verify", "d", "--crash-every", "2"]) is Error(Usage(_))
end

test "a missing folder, a bad port, a short request, or an unknown command is a usage error"
  assert task([]) is Error(Usage(_))
  assert task(["serve"]) is Error(Usage(_))
  assert task(["serve", "--port", "8000"]) is Error(Usage(_))
  assert task(["serve", "data", "--port"]) is Error(Usage(_))
  assert task(["serve", "data", "--port", "0"]) is Error(Usage(_))
  assert task(["serve", "data", "--port", "65536"]) is Error(Usage(_))
  assert task(["compact"]) is Error(Usage(_))
  assert task(["compact", "a", "b"]) is Error(Usage(_))
  assert task(["client", "localhost", "7900", "p", "GET"]) is Error(Usage(_))
  assert task(["client", "localhost", "port", "p", "GET", "/jobs"]) is Error(Usage(_))
  assert task(["check", "data"]) is Error(Usage(_))
  assert task(["stop"]) is Error(Usage(_))
end

test "client joins the JSON after the path back into one body, and splits a query from the path"
  words = ["client", "localhost", "7900", "p", "POST", "/jobs", "{\"queue\":", "\"a\"}"]
  trip = Trip(host: "localhost", port: 7_900, token: "p", method: "POST", path: "/jobs",
    json: "{\"queue\": \"a\"}")
  assert task(words) == Ok(Asking(trip: trip))
  assert request_of(trip).headers.get("authorization") == Some("Bearer p")
  var anonymous = trip
  anonymous.token = "-"
  anonymous.path = "/jobs?queue=emails&state=scheduled"
  listing = request_of(anonymous)
  assert listing.headers.size == 0 and listing.path == "/jobs"
  assert listing.query == Map.new().set("queue", "emails").set("state", "scheduled")
  assert task(["check", "data", "s.txt"]) == Ok(Checking(dir: "data", script: "s.txt"))
end

test "a response prints as its status and body, and the clock's numbers are steadied"
  assert shown(Response(status: 204, body: "")) == "204\n"
  assert shown(Response(status: 404, body: "{}")) == "404 {}\n"
  job = "{\"id\": \"j_1\", \"created_at\": \"2026-09-14T10:00:00.123Z\", \"updated_at\": \"2026-09-14T10:00:01Z\", \"worker\": \"w\", \"lease_until\": \"2026-09-14T10:00:31Z\"}"
  assert steady(job) == "{\"id\": \"j_1\", \"created_at\": \"<created_at>\", \"updated_at\": \"<updated_at>\", \"worker\": \"w\", \"lease_until\": \"<lease_until>\"}"
  later = "{\"id\": \"j_2\", \"state\": \"scheduled\", \"updated_at\": \"2026-09-14T10:00:01Z\", \"run_at\": \"2026-09-14T11:00:01Z\"}"
  assert steady(later) == "{\"id\": \"j_2\", \"state\": \"scheduled\", \"updated_at\": \"<updated_at>\", \"run_at\": \"<run_at>\"}"
  assert steady("{\"queued\": 1, \"dead\": 0, \"uptime_ms\": 1234}") == "{\"queued\": 1, \"dead\": 0, \"uptime_ms\": <uptime_ms>}"
  assert steady("no numbers here") == "no numbers here"
end

test "a store whose last line was cut short opens without it, and says so on the error stream"
  fs = Fs.fixture()
  err = Out.fixture()
  cut = "SET j_1 #{old_record("j_1", "queued", 0)}\nSET j_2 {\"id\": \"j_2\""
  assert fs.write("d/jobq.log", cut, within: 1_000.ms) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(table)
  assert count(table.live) == 1
  assert err.written == ["jobq: the last line of d/jobq.log was cut short, so it is left out\n"]
  assert opening_of(table, Time.fixture()) is Ok(_)
end

# The incident's first lesson: a record in a state the API can never produce refuses the folder
# at the door, whichever command opened it, and names the record and the rule it breaks.
test "a folder with a record no request could have left is refused, and a whole one is verified"
  fs = Fs.fixture()
  err = Out.fixture()
  good = "SET ids 1000\nSET j_1 #{old_record("j_1", "queued", 0)}\nSET j_2 #{old_record("j_2", "done", 1)}\n"
  assert fs.write("d/jobq.log", good, within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(table)
  assert counted(table,
    Time.fixture()) == Ok("2 jobs: queued 1, scheduled 0, leased 0, done 1, dead 0; next id j_1000; archived 0\n")
  ill = good.replace("\"state\": \"done\", \"payload\": \"p\", \"attempts\": 1",
    "\"state\": \"done\", \"payload\": \"p\", \"attempts\": 0")
  assert fs.write("d/jobq.log", ill, within: 1.minute) is Ok(_)
  assert opened_store(fs, err,
    "d") == Error(Ill(dir: "d", key: "j_2", rule: "a done job has at least one try"))
  named = good.replace("SET j_2 {\"id\": \"j_2\"", "SET j_7 {\"id\": \"j_2\"")
  assert fs.write("d/jobq.log", named, within: 1.minute) is Ok(_)
  assert opened_store(fs, err,
    "d") == Error(Ill(dir: "d", key: "j_7", rule: "its id is j_2, not its key"))
  assert fs.write("d/jobq.log", good.replace("SET ids 1000", "SET ids nine"),
    within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") == Error(Ill(dir: "d", key: "ids", rule: "is not a number"))
  assert said(Ill(dir: "d", key: "j_2", rule: "is not a job")) == "d: record j_2: is not a job"
  assert code_of(Ill(dir: "d", key: "j_2", rule: "is not a job")) == 1
end

test "a log the previous version wrote compacts to one line per job, and no old name is left"
  fs = Fs.fixture()
  err = Out.fixture()
  old = "SET ids 1000\nSET j_1 #{old_record("j_1", "queued", 0)}\nSET j_2 #{old_record("j_2", "done", 1)}\n"
  assert fs.write("d/jobq.log", old, within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(table)
  assert lines(table.live) == 3 and count(table.live) == 3
  assert compacted(fs, "d", table,
    Time.fixture()) == Ok("jobq: compacted d/jobq.log from 3 lines to 3\n")
  assert fs.read("d/jobq.log", within: 1.minute) is Ok(text)
  assert !text.contains?("attempts")
  assert fs.read("d/jobq.archive", within: 1.minute) is Error(_)
  assert text.contains?("\"tries\": 0, \"max_tries\": 3, \"backoff_ms\": 0")
  assert text.contains?("\"tries\": 1, \"max_tries\": 3, \"backoff_ms\": 0")
  assert opened_store(fs, err, "d") is Ok(again)
  assert count(again.live) == 3 and lines(again.live) == 3
  assert opening_of(again, Time.fixture()) is Ok(_)
end

test "verify takes one folder, and names the folder it cannot open"
  assert task(["verify", "data"]) == Ok(Verifying(dir: "data"))
  assert task(["verify"]) is Error(Usage(_))
  assert task(["verify", "a", "b"]) is Error(Usage(_))
  assert task(["verify", "--port"]) is Error(Usage(_))
  assert !serving?(["verify", "data"])
  fs = Fs.fixture()
  err = Out.fixture()
  assert opened_store(fs, err, "nowhere") is Error(Unopened(dir: "nowhere", why: _))
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(empty)
  assert counted(empty,
    Time.fixture()) == Ok("0 jobs: queued 0, scheduled 0, leased 0, done 0, dead 0; next id j_1; archived 0\n")
end

test "serve takes --retain-ms from a second to 31 days, a day by default"
  assert place_of("d").rules.retain_ms == 86_400_000
  assert task(["serve", "d", "--retain-ms", "1000"]) is Ok(Serving(short))
  assert short.rules.retain_ms == 1_000 and short.rules.max_restarts == 5
  assert task(["serve", "d", "--retain-ms", "2678400000"]) is Ok(Serving(long))
  assert long.rules.retain_ms == 2_678_400_000
  assert task(["serve", "d", "--retain-ms", "999"]) is Error(Usage(_))
  assert task(["serve", "d", "--retain-ms", "2678400001"]) is Error(Usage(_))
  assert task(["serve", "d", "--retain-ms", "day"]) is Error(Usage(_))
  assert task(["serve", "d", "--retain-ms", "1000", "--retain-ms", "2000"]) is Error(Usage(_))
  assert task(["compact", "d", "--retain-ms", "1000"]) is Error(Usage(_))
  assert usage().contains?("[--retain-ms N]")
end

test "verify counts the archive, and a folder without one has an empty archive"
  fs = Fs.fixture()
  err = Out.fixture()
  live = "SET ids 1000\nSET j_1 #{old_record("j_1", "queued", 0)}\nSET j_2 #{archived_record("j_2", "k").replace(", \"archived_at\": \"2026-09-14T10:00:00Z\"", "")}\n"
  assert fs.write("d/jobq.log", live, within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(bare)
  assert count(bare.shelf) == 0
  assert counted(bare,
    Time.fixture()) == Ok("2 jobs: queued 1, scheduled 0, leased 0, done 1, dead 0; next id j_1000; archived 0\n")
  shelf = "SET j_2 #{archived_record("j_2", "k")}\nSET j_3 #{archived_record("j_3", "k3")}\nSET j_3 deleted\nSET j_4 #{archived_record("j_4", "k4")}\nSET j_5 {\"id\""
  assert fs.write("d/jobq.archive", shelf, within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(both)
  assert err.written.contains?("jobq: the last line of d/jobq.archive was cut short, so it is left out\n")
  assert counted(both,
    Time.fixture()) == Ok("1 jobs: queued 1, scheduled 0, leased 0, done 0, dead 0; next id j_1000; archived 2\n")
end

test "verify refuses an archive with a bad record, naming it, as it refuses a bad live one"
  fs = Fs.fixture()
  err = Out.fixture()
  assert fs.write("d/jobq.log", "SET ids 1000\n", within: 1.minute) is Ok(_)
  queued = archived_record("j_2", "k").replace("\"state\": \"done\"",
    "\"state\": \"queued\"").replace("\"tries\": 1", "\"tries\": 0")
  assert fs.write("d/jobq.archive", "SET j_2 #{queued}\n", within: 1.minute) is Ok(_)
  assert opened_store(fs, err,
    "d") == Error(Ill(dir: "d", key: "archive j_2", rule: "is not a job"))
  bare = archived_record("j_2", "k").replace(", \"archived_at\": \"2026-09-14T10:00:00Z\"", "")
  assert fs.write("d/jobq.archive", "SET j_2 #{bare}\n", within: 1.minute) is Ok(_)
  assert opened_store(fs, err,
    "d") == Error(Ill(dir: "d", key: "archive j_2", rule: "an archived job has an archived_at"))
  bad_key = archived_record("j_2", "a b")
  assert fs.write("d/jobq.archive", "SET j_2 #{bad_key}\n", within: 1.minute) is Ok(_)
  assert opened_store(fs, err,
    "d") == Error(Ill(dir: "d", key: "archive j_2",
    rule: "its key is not 1 to 64 letters, digits, - or _"))
  assert fs.write("d/jobq.archive", "GET j_2\n", within: 1.minute) is Ok(_)
  assert opened_store(fs, err,
    "d") == Error(Unopened(dir: "d",
    why: "holds a jobq.archive whose line 1 is not a SET or a DEL"))
  twice = "SET j_2 #{archived_record("j_2", "k")}\nSET j_3 #{archived_record("j_3", "k")}\n"
  assert fs.write("d/jobq.archive", twice, within: 1.minute) is Ok(_)
  assert opened_store(fs, err,
    "d") == Error(Ill(dir: "d", key: "j_3", rule: "its key k is j_2's too"))
end

test "compact drops archived jobs from the log and deleted ones from the archive"
  fs = Fs.fixture()
  err = Out.fixture()
  stale = archived_record("j_2", "k").replace(", \"archived_at\": \"2026-09-14T10:00:00Z\"", "")
  live = "SET ids 1000\nSET j_1 #{old_record("j_1", "queued", 0)}\nSET j_2 #{stale}\nSET j_3 #{stale.replace("j_2", "j_3").replace("\"k\"", "\"k3\"")}\n"
  shelf = "SET j_2 #{archived_record("j_2", "k")}\nSET j_3 #{archived_record("j_3", "k3")}\nSET j_3 deleted\n"
  assert fs.write("d/jobq.log", live, within: 1.minute) is Ok(_)
  assert fs.write("d/jobq.archive", shelf, within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(folder)
  assert compacted(fs, "d", folder,
    Time.fixture()) == Ok("jobq: compacted d/jobq.log from 4 lines to 2, and d/jobq.archive from 3 to 1\n")
  assert fs.read("d/jobq.log", within: 1.minute) is Ok(log_text)
  assert !log_text.contains?("j_2") and !log_text.contains?("j_3")
  assert fs.read("d/jobq.archive",
    within: 1.minute) == Ok("SET j_2 #{archived_record("j_2", "k")}\n")
  assert opened_store(fs, err, "d") is Ok(again)
  assert counted(again,
    Time.fixture()) == Ok("1 jobs: queued 1, scheduled 0, leased 0, done 0, dead 0; next id j_1000; archived 1\n")
end

test "compact folds two renames into the log and the archive, and leaves no rename record and no count"
  fs = Fs.fixture()
  err = Out.fixture()
  live = "SET ids 1000\nSET j_1 #{queued_record("j_1", "emails", 0)}\nSET rename_1 {\"from\": \"emails\", \"to\": \"mail\"}\nSET j_3 #{queued_record("j_3", "emails", 1)}\nSET rename_2 {\"from\": \"mail\", \"to\": \"post\"}\n"
  shelf = "SET j_2 #{archived_record("j_2", "k")}\n"
  assert fs.write("d/jobq.log", live, within: 1.minute) is Ok(_)
  assert fs.write("d/jobq.archive", shelf, within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(folder)
  assert counted(folder,
    Time.fixture()) == Ok("2 jobs: queued 2, scheduled 0, leased 0, done 0, dead 0; next id j_1000; archived 1\n")
  assert compacted(fs, "d", folder,
    Time.fixture()) == Ok("jobq: compacted d/jobq.log from 5 lines to 3, and d/jobq.archive from 1 to 1\n")
  assert fs.read("d/jobq.log", within: 1.minute) is Ok(log_text)
  assert !log_text.contains?("rename_") and !log_text.contains?("renames")
  assert log_text.contains?("SET j_1 #{queued_record("j_1", "post", 0)}\n")
  assert log_text.contains?("SET j_3 #{queued_record("j_3", "emails", 0)}\n")
  assert fs.read("d/jobq.archive", within: 1.minute) is Ok(shelf_text)
  assert shelf_text.contains?("\"queue\": \"post\"") and !shelf_text.contains?("renames")
  assert opened_store(fs, err, "d") is Ok(again)
  assert opening_of(again, Time.fixture()) is Ok(start)
  assert health_of(start.board, Time.fixture()).archived == 1 and start.board.marks == 0
  assert compacted(fs, "d", again,
    Time.fixture()) == Ok("jobq: compacted d/jobq.log from 3 lines to 3, and d/jobq.archive from 1 to 1\n")
end

test "a compact cut short after its first, second, or third write leaves a folder that opens to the same queues"
  fs = Fs.fixture()
  err = Out.fixture()
  live = "SET ids 1000\nSET j_1 #{queued_record("j_1", "emails", 0)}\nSET rename_1 {\"from\": \"emails\", \"to\": \"mail\"}\n"
  shelf = "SET j_2 #{archived_record("j_2", "k")}\n"
  assert fs.write("d/jobq.log", live, within: 1.minute) is Ok(_)
  assert fs.write("d/jobq.archive", shelf, within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(folder)
  assert opening_of(folder, Time.fixture()) is Ok(start)
  first = String.join(snapshot(start.board).map(fn(w) line_of(w) end), "")
  assert first.contains?("SET rename_1 ") and first.contains?("\"queue\": \"mail\", \"state\"")
  assert fs.write("d/jobq.log", first, within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(after_first)
  assert opening_of(after_first, Time.fixture()) is Ok(one)
  assert records(one.board) == records(start.board)
  assert shelf_records(one.board) == shelf_records(start.board)
  second = String.join(shelf_lines(shelf_snapshot(start.board)), "")
  assert fs.write("d/jobq.archive", second, within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(after_second)
  assert opening_of(after_second, Time.fixture()) is Ok(two)
  assert records(two.board) == records(start.board)
  assert shelf_records(two.board) == shelf_records(start.board)
  assert shelf_records(two.board).all?(fn(r) r.contains?("\"queue\": \"mail\"") end)
  third = String.join(snapshot(folded_in(start.board)).map(fn(w) line_of(w) end), "")
  assert !third.contains?("rename_") and !third.contains?("renames")
  assert fs.write("d/jobq.log", third, within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(after_third)
  assert opening_of(after_third, Time.fixture()) is Ok(three)
  assert records(three.board) == records(start.board)
  assert shelf_records(three.board) == shelf_records(start.board)
  assert three.board.marks == 1
end

# The generation-five bug report as a test: the previous version compacted a folder with renames
# to a rename count and no rename record, renamed once more, and then refused to open the folder it
# had written ("the rename count is below rename_3"). A folder the program wrote and closed cleanly
# opens.
test "a folder the previous version compacted and renamed once more opens, verifies, and compacts"
  fs = Fs.fixture()
  err = Out.fixture()
  live = "SET ids 1000\nSET renames 2\nSET j_1 #{queued_record("j_1", "post", 2)}\nSET rename_3 {\"from\": \"post\", \"to\": \"mail\"}\n"
  assert fs.write("d/jobq.log", live, within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(folder)
  assert counted(folder,
    Time.fixture()) == Ok("1 jobs: queued 1, scheduled 0, leased 0, done 0, dead 0; next id j_1000; archived 0\n")
  assert opening_of(folder, Time.fixture()) is Ok(start)
  assert start.board.marks == 3 and records(start.board).all?(fn(r)
    r.contains?("\"queue\": \"mail\"")
  end)
  assert compacted(fs, "d", folder,
    Time.fixture()) == Ok("jobq: compacted d/jobq.log from 4 lines to 2\n")
  assert fs.read("d/jobq.log", within: 1.minute) is Ok(text)
  assert text == "SET ids 1000\nSET j_1 #{queued_record("j_1", "mail", 0)}\n"
end

test "prune takes a folder and an age of at least a second, bench a folder and its sizes, and serve a retention"
  assert task(["prune", "d", "--older-than-ms", "5000"]) == Ok(Trimming(dir: "d",
    older_than_ms: 5_000))
  assert task(["prune", "d", "--older-than-ms", "999"]) is Error(Usage(_))
  assert task(["prune", "d", "--older-than-ms", "0"]) is Error(Usage(_))
  assert task(["prune", "d"]) is Error(Usage(_))
  assert task(["prune", "d", "--older-than", "5000"]) is Error(Usage(_))
  assert task(["prune", "d", "--older-than-ms", "5000", "x"]) is Error(Usage(_))
  assert task(["bench",
    "d"]) == Ok(Benching(measured: Measured(dir: "d", jobs: 30_000, workers: 32)))
  assert task(["bench",
    "d",
    "--workers",
    "8",
    "--jobs",
    "1000"]) == Ok(Benching(measured: Measured(dir: "d", jobs: 1_000, workers: 8)))
  assert task(["bench", "d", "--jobs", "7"]) is Error(Usage(_))
  assert task(["bench", "d", "--workers", "0"]) is Error(Usage(_))
  assert task(["bench", "d", "--jobs", "10", "--jobs", "20"]) is Error(Usage(_))
  assert task(["bench", "d", "--port", "1"]) is Error(Usage(_))
  assert !serving?(["bench", "d"]) and !serving?(["prune", "d", "--older-than-ms", "5000"])
  assert place_of("d").rules.retention_ms == 0
  assert task(["serve", "d", "--retention", "60000"]) is Ok(Serving(kept))
  assert kept.rules.retention_ms == 60_000
  assert task(["serve", "d", "--retention", "0"]) is Ok(Serving(never_pruned))
  assert never_pruned.rules.retention_ms == 0
  assert task(["serve", "d", "--retention", "500"]) is Error(Usage(_))
  assert task(["serve", "d", "--retention", "soon"]) is Error(Usage(_))
  assert usage().contains?("jobq prune <dir> --older-than-ms <n>") and usage().contains?("[--retention <ms>]")
end

test "prune writes one record, removes only the jobs old enough, frees their keys, and a stale live record stays gone"
  fs = Fs.fixture()
  err = Out.fixture()
  stale = archived_record("j_2", "k").replace(", \"archived_at\": \"2026-09-14T10:00:00Z\"", "")
  live = "SET ids 1000\nSET j_1 #{old_record("j_1", "queued", 0)}\nSET j_2 #{stale}\n"
  later = archived_record("j_3", "k3").replace("\"archived_at\": \"2026-09-14T10:00:00Z\"",
    "\"archived_at\": \"2026-09-14T11:00:00Z\"")
  shelf = "SET j_2 #{archived_record("j_2", "k")}\nSET j_3 #{later}\n"
  assert fs.write("d/jobq.log", live, within: 1.minute) is Ok(_)
  assert fs.write("d/jobq.archive", shelf, within: 1.minute) is Ok(_)
  now = Time.parse("2026-09-14T11:00:00Z") or Time.fixture()
  assert opened_store(fs, err, "d") is Ok(folder)
  assert trimmed(fs, "d", folder, 3_600_000,
    now) == Ok("jobq: pruned 1 archived jobs from d; 1 remain; 1 lines written\n")
  assert fs.read("d/jobq.log", within: 1.minute) is Ok(text)
  assert text == "#{live}SET prune_1 {\"cutoff\": \"2026-09-14T10:00:00Z\", \"pruned\": 1}\n"
  assert fs.read("d/jobq.archive", within: 1.minute) == Ok(shelf)
  assert opened_store(fs, err, "d") is Ok(again)
  assert counted(again,
    now) == Ok("1 jobs: queued 1, scheduled 0, leased 0, done 0, dead 0; next id j_1000; archived 1\n")
  assert opening_of(again, now) is Ok(start)
  assert shelf_records(start.board).all?(fn(r) r.contains?("\"id\": \"j_3\"") end)
  assert trimmed(fs, "d", again, 3_600_000,
    now) == Ok("jobq: pruned 0 archived jobs from d; 1 remain; 0 lines written\n")
  assert fs.read("d/jobq.log", within: 1.minute) == Ok(text)
  assert compacted(fs, "d", again,
    now) == Ok("jobq: compacted d/jobq.log from 4 lines to 2, and d/jobq.archive from 2 to 1\n")
  assert fs.read("d/jobq.archive", within: 1.minute) == Ok("SET j_3 #{later}\n")
  assert fs.read("d/jobq.log", within: 1.minute) is Ok(compact_text)
  assert !compact_text.contains?("prune_") and !compact_text.contains?("j_2")
  assert opened_store(fs, err, "d") is Ok(third)
  assert counted(third,
    now) == Ok("1 jobs: queued 1, scheduled 0, leased 0, done 0, dead 0; next id j_1000; archived 1\n")
end

test "a prune record cut short by a kill is left out, and the folder opens with every archived job"
  fs = Fs.fixture()
  err = Out.fixture()
  live = "SET ids 1000\nSET j_1 #{old_record("j_1", "queued", 0)}\n"
  assert fs.write("d/jobq.log", "#{live}SET prune_1 {\"cutoff\": \"2026-09",
    within: 1.minute) is Ok(_)
  assert fs.write("d/jobq.archive", "SET j_2 #{archived_record("j_2", "k")}\n",
    within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(folder)
  assert err.written.contains?("jobq: the last line of d/jobq.log was cut short, so it is left out\n")
  assert counted(folder,
    Time.fixture()) == Ok("1 jobs: queued 1, scheduled 0, leased 0, done 0, dead 0; next id j_1000; archived 1\n")
end

test "verify refuses a folder with a bad prune record, naming it"
  fs = Fs.fixture()
  err = Out.fixture()
  live = "SET ids 1000\nSET j_1 #{old_record("j_1", "queued", 0)}\nSET prune_1 {\"cutoff\": \"soon\", \"pruned\": 1}\n"
  assert fs.write("d/jobq.log", live, within: 1.minute) is Ok(_)
  assert opened_store(fs, err,
    "d") == Error(Ill(dir: "d", key: "prune_1", rule: "its cutoff is not a time"))
end

test "the steadied transcript masks the archive's oldest time and size, and leaves a null alone"
  assert steady("{\"archived\": 2, \"oldest_archived_at\": \"2026-09-14T10:00:00Z\", \"bytes\": 512}") == "{\"archived\": 2, \"oldest_archived_at\": \"<oldest_archived_at>\", \"bytes\": <bytes>}"
  assert steady("{\"archived\": 0, \"oldest_archived_at\": null, \"bytes\": 0}") == "{\"archived\": 0, \"oldest_archived_at\": null, \"bytes\": <bytes>}"
end

test "verify refuses a folder with a bad rename record, and counts with the renames applied"
  fs = Fs.fixture()
  err = Out.fixture()
  good = "SET ids 1000\nSET j_1 #{queued_record("j_1", "emails", 0)}\nSET rename_1 {\"from\": \"emails\", \"to\": \"mail\"}\n"
  assert fs.write("d/jobq.log", good, within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(folder)
  assert counted(folder,
    Time.fixture()) == Ok("1 jobs: queued 1, scheduled 0, leased 0, done 0, dead 0; next id j_1000; archived 0\n")
  bad = good.replace("\"to\": \"mail\"", "\"to\": \"no mail\"")
  assert fs.write("d/jobq.log", bad, within: 1.minute) is Ok(_)
  assert opened_store(fs, err,
    "d") == Error(Ill(dir: "d", key: "rename_1",
    rule: "its to is not 1 to 64 letters, digits, - or _"))
  shelf = "SET j_2 #{archived_record("j_2", "k")}\n"
  clash = "#{good}SET j_3 #{queued_record("j_3", "mail", 1).replace("\"queue\": \"mail\"", "\"queue\": \"mail\", \"key\": \"k\"")}\n"
  assert fs.write("d/jobq.log", clash, within: 1.minute) is Ok(_)
  assert fs.write("d/jobq.archive", shelf, within: 1.minute) is Ok(_)
  assert opened_store(fs, err,
    "d") == Error(Ill(dir: "d", key: "j_3", rule: "its key k is j_2's too"))
end

test "the steadied transcript masks archived_at"
  shown_job = "{\"id\": \"j_1\", \"updated_at\": \"2026-09-14T10:00:01Z\", \"archived_at\": \"2026-09-16T10:00:01.5Z\"}"
  assert steady(shown_job) == "{\"id\": \"j_1\", \"updated_at\": \"<updated_at>\", \"archived_at\": \"<archived_at>\"}"
end

test "a usage error exits 2, and a folder, a port, or a server that cannot be had exits 1"
  assert code_of(Usage(detail: "x")) == 2
  assert code_of(Unopened(dir: "d", why: "w")) == 1
  assert code_of(Unbound(port: 7_900)) == 1
  assert code_of(Unreached(host: "h", port: 1)) == 1
end

test "a serve on a port another listener holds is Unbound, and exits 1"
  http = Http.fixture()
  fs = Fs.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert http.listen(7_900, within: 1.minute) is Ok(_)
  held = serve(http, fs, Clock.fixture(), Out.fixture(), Out.fixture(), place_of("d"))
  assert held == Error(Unbound(port: 7_900)) and code_of(Unbound(port: 7_900)) == 1
end

verified: types, contracts, tests (25), property (0 seeds), sim (not run)
          proven: not run
