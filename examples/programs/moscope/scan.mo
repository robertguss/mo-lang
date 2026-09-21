module Scan
expose scan_tree

use Limits{depth, entries, files, file_bytes, total_bytes, diagnostics, call_time, process_time}
use Model{Issue, Scan, Discovery, empty_scan, empty_discovery}
use Parse{start_file, folded_line}

intent "Discover JSONL files serially from one read-only root, without following discovered links, then size-admit and fold them in deterministic path order."

struct EntryPlace
  entry_path: String
  next_level: UInt64
end

fn scan_tree(fs: Fs, clock: Clock, started: Time) : Scan
  found = discover(fs, ".", 0, empty_discovery(), clock, started)
  var scan = empty_scan()
  scan.issues = found.issues
  scan.incomplete = found.incomplete
  scan.skipped_links = found.skipped_links
  for path in found.files.sort
    if clock.now >= started + process_time()
      scan = scan_problem(scan, path, 0, "the 60 second processing deadline was exceeded")
      break
    end
    scan = scan_file(fs, path, scan, clock, started)
  end
  scan
end

fn discover(root: Fs, path: String, level: UInt64, so_far: Discovery, clock: Clock,
  started: Time) : Discovery
  var found = so_far
  return found if found.stopped
  if clock.now >= started + process_time()
    return discovery_stop(found, path, "the 60 second processing deadline was exceeded")
  end
  if level > depth()
    return discovery_stop(found, path, "traversal exceeds depth 24")
  end
  folder = if path == ".": root else: root.scoped(path)
  names = case folder.list(within: call_time())
    Ok(listed): listed.sort
    Error(error):
      return discovery_problem(found, path, "cannot list directory: #{fs_error(error)}")
  end
  # list materializes the directory before this application can count it.
  for name in names
    if clock.now >= started + process_time()
      return discovery_stop(found, path, "the 60 second processing deadline was exceeded")
    end
    if found.entries >= entries()
      return discovery_stop(found, path, "traversal exceeds 50000 entries")
    end
    found.entries += 1
    entry_path = joined(path, name)
    place = EntryPlace(entry_path: entry_path, next_level: level + 1)
    case root.kind_of(entry_path, within: call_time())
      Error(error):
        found = discovery_problem(found, entry_path, "cannot stat entry: #{fs_error(error)}")
      Ok(entry):
        found = discovered_entry(root, place, found, clock, started, entry.kind)
    end
    if found.stopped
      break
    end
  end
  found
end

fn discovered_entry(root: Fs, place: EntryPlace, so_far: Discovery, clock: Clock,
  started: Time, kind: EntryKind) : Discovery
  var found = so_far
  case kind
    Link:
      found.skipped_links += 1
    Folder:
      if place.entry_path.ends_with?(".jsonl")
        found = discovery_problem(found, place.entry_path,
          "a .jsonl candidate is a directory, not a regular file")
      end
      found = discover(root, place.entry_path, place.next_level, found, clock, started)
    File:
      if place.entry_path.ends_with?(".jsonl")
        if found.files.size >= files()
          return discovery_stop(found, place.entry_path, "discovery exceeds 5000 JSONL files")
        end
        found.files = found.files.push(place.entry_path)
      end
  end
  found
end

fn scan_file(root: Fs, path: String, scan: Scan, clock: Clock, started: Time) : Scan
  var next = scan
  bytes = case root.size(path, within: call_time())
    Ok(n): n
    Error(error):
      return scan_problem(next, path, 0,
        "cannot admit regular .jsonl input by size: #{fs_error(error)}")
  end
  if bytes > file_bytes()
    return scan_problem(next, path, 0, "file exceeds 64 MiB")
  end
  admitted = next.admitted_bytes.checked_add(bytes)
  if admitted is None or (admitted or 0) > total_bytes()
    return scan_problem(next, path, 0, "aggregate admitted input exceeds 1 GiB")
  end
  next.admitted_bytes = admitted or next.admitted_bytes
  initial = start_file(next, path, bytes)
  if clock.now >= started + process_time()
    return scan_problem(next, path, 0, "the 60 second processing deadline was exceeded")
  end
  folded = root.fold_lines(path, initial, within: call_time(), fn(state, line)
    folded_line(state, line)
  end)
  case folded
    Ok(done):
      next = done.scan
      next.files_read += 1
    Error(error):
      next = scan_problem(next, path, 0,
        "cannot read admitted .jsonl input: #{fs_error(error)}")
  end
  if clock.now >= started + process_time()
    next = scan_problem(next, path, 0, "the 60 second processing deadline was exceeded")
  end
  next
end

fn joined(parent: String, name: String) : String
  return name if parent == "."
  "#{parent}/#{name}"
end

fn fs_error(error: FsError) : String
  case error
    Missing(path): "missing or unsupported entry #{path}"
    Timeout: "operation timed out"
    NotText: "entry is not text"
  end
end

fn discovery_problem(found: Discovery, path: String, detail: String) : Discovery
  var next = found
  next.incomplete = true
  if next.issues.size < diagnostics()
    next.issues = next.issues.push(Issue(path: path, line: 0, detail: detail))
  end
  next
end

fn discovery_stop(found: Discovery, path: String, detail: String) : Discovery
  var next = discovery_problem(found, path, detail)
  next.stopped = true
  next
end

fn scan_problem(scan: Scan, path: String, line: UInt64, detail: String) : Scan
  var next = scan
  next.incomplete = true
  if next.issues.size < diagnostics()
    next.issues = next.issues.push(Issue(path: path, line: line, detail: detail))
  end
  next
end

test "production discovery reads nested JSONL, ignores other files, and diagnoses JSONL folders"
  fs = Fs.fixture()
  assert fs.mkdir("nested", within: 1.minute) is Ok(_)
  assert fs.mkdir("nested/folder.jsonl", within: 1.minute) is Ok(_)
  assert fs.write("nested/a.jsonl", "{\"type\":\"progress\"}\n", within: 1.minute) is Ok(_)
  assert fs.write("nested/no.txt", "ignored", within: 1.minute) is Ok(_)
  clock = Clock.fixture()
  scan = scan_tree(fs, clock, clock.now)
  assert scan.files_read == 1 and scan.records == 1 and scan.admitted_bytes == 20
  assert scan.unknown_kinds.get("progress") == Some(1) and scan.incomplete
end

test "production filesystem timeout and aggregate admission paths are incomplete"
  clock = Clock.fixture()
  timed = scan_tree(Fs.fixture(delay: 11.seconds), clock, clock.now)
  assert timed.incomplete and timed.files_read == 0
  fs = Fs.fixture()
  assert fs.write("a.jsonl", "{}\n", within: 1.minute) is Ok(_)
  var full = empty_scan()
  full.admitted_bytes = total_bytes()
  refused = scan_file(fs, "a.jsonl", full, clock, clock.now)
  assert refused.incomplete and refused.files_read == 0
  assert refused.admitted_bytes == total_bytes()
end

test "processing expiry after a successful fold preserves admitted results"
  fs = Fs.fixture(delay: 2.seconds)
  record = "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"id\":\"m\",\"content\":\"kept\"}}\n"
  assert fs.write("a.jsonl", record, within: 1.minute) is Ok(_)
  clock = Clock.fixture()
  started = clock.now
  assert Fs.fixture(delay: 53.seconds).list(within: 1.minute) is Ok(_)
  scan = scan_tree(fs, clock, started)
  assert scan.incomplete
  assert scan.files_read == 1
  assert scan.messages.size == 1
end
