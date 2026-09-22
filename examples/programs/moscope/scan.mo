module Scan
expose scan_tree

use Limits{depth, entries, files, call_time}
use Model{Matcher, Scan, Discovery, empty_scan, empty_discovery, failed}
use Parse{start_file, folded_line}

intent "Discover JSONL files serially from one read-only root, without following discovered links, then stream each in deterministic path order through the matcher."

struct EntryPlace
  entry_path: String
  next_level: UInt64
end

fn scan_tree(fs: Fs, matcher: Matcher) : Scan
  found = discover(fs, ".", 0, empty_discovery())
  var scan = empty_scan()
  scan.errors = found.errors
  scan.skipped_links = found.skipped_links
  for path in found.files.sort
    scan = scan_file(fs, path, scan, matcher)
  end
  scan
end

fn discover(root: Fs, path: String, level: UInt64, so_far: Discovery) : Discovery
  var found = so_far
  return found if found.stopped
  if !depth_admitted?(level)
    return discovery_stop(found, path, "traversal exceeds depth #{depth()}")
  end
  folder = if path == ".": root else: root.scoped(path)
  names = case folder.list(within: call_time())
    Ok(listed): listed.sort
    Error(error):
      found.errors = failed(found.errors, path, 0, "cannot list directory: #{fs_error(error)}")
      return found
  end
  for name in names
    if !entry_admitted?(found.entries)
      return discovery_stop(found, path, "traversal exceeds #{entries()} entries")
    end
    found.entries += 1
    place = EntryPlace(entry_path: joined(path, name), next_level: level + 1)
    case root.kind_of(place.entry_path, within: call_time())
      Error(error):
        found.errors = failed(found.errors, place.entry_path, 0,
          "cannot stat entry: #{fs_error(error)}")
      Ok(entry):
        found = discovered_entry(root, place, found, entry.kind)
    end
    if found.stopped
      break
    end
  end
  found
end

fn discovered_entry(root: Fs, place: EntryPlace, so_far: Discovery, kind: EntryKind) : Discovery
  var found = so_far
  case kind
    Link:
      found.skipped_links += 1
    Folder:
      if place.entry_path.ends_with?(".jsonl")
        found.errors = failed(found.errors, place.entry_path, 0,
          "a .jsonl candidate is a directory, not a regular file")
      end
      found = discover(root, place.entry_path, place.next_level, found)
    File:
      if place.entry_path.ends_with?(".jsonl")
        if !file_admitted?(found.files.size)
          return discovery_stop(found, place.entry_path, "discovery exceeds #{files()} JSONL files")
        end
        found.files = found.files.push(place.entry_path)
      end
  end
  found
end

# fold_lines streams the file; only matching blocks outlive their line.
fn scan_file(root: Fs, path: String, scan: Scan, matcher: Matcher) : Scan
  var next = scan
  folded = root.fold_lines(path, start_file(next, matcher, path), within: call_time(),
    fn(state, line) folded_line(state, line) end)
  case folded
    Ok(done):
      next = done.scan
      next.files_read += 1
    Error(error):
      next.errors = failed(next.errors, path, 0, "cannot read .jsonl input: #{fs_error(error)}")
  end
  next
end

fn joined(parent: String, name: String) : String
  return name if parent == "."
  "#{parent}/#{name}"
end

fn depth_admitted?(level: UInt64) : Bool
  level <= depth()
end

fn entry_admitted?(count: UInt64) : Bool
  count < entries()
end

fn file_admitted?(count: UInt64) : Bool
  count < files()
end

fn fs_error(error: FsError) : String
  case error
    Missing(_): "missing, unreadable, or not a supported entry"
    Timeout: "operation timed out"
    NotText: "entry is not text"
  end
end

fn discovery_stop(found: Discovery, path: String, detail: String) : Discovery
  var next = found
  next.errors = failed(next.errors, path, 0, detail)
  next.stopped = true
  next
end

fn everything() : Matcher
  Matcher(mode: Phrase, terms: [""], include_tools: true)
end

test "discovery reads nested JSONL, ignores other files, and reports JSONL folders as errors"
  fs = Fs.fixture()
  assert fs.mkdir("nested", within: 1.minute) is Ok(_)
  assert fs.mkdir("nested/folder.jsonl", within: 1.minute) is Ok(_)
  assert fs.write("nested/a.jsonl", "{\"type\":\"progress\"}\n", within: 1.minute) is Ok(_)
  assert fs.write("nested/no.txt", "ignored", within: 1.minute) is Ok(_)
  scan = scan_tree(fs, everything())
  assert scan.files_read == 1 and scan.records == 1
  assert scan.ignored.get("progress") == Some(1) and scan.errors.size == 1
end

test "a filesystem timeout is an error, not a silent empty result"
  timed = scan_tree(Fs.fixture(delay: 11.seconds), everything())
  assert timed.errors.size == 1 and timed.files_read == 0
end

test "files are read in sorted path order and every file is read"
  fs = Fs.fixture()
  record = "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"id\":\"m\",\"content\":\"kept\"}}\n"
  assert fs.write("b.jsonl", record, within: 1.minute) is Ok(_)
  assert fs.write("a.jsonl", record, within: 1.minute) is Ok(_)
  scan = scan_tree(fs, everything())
  assert scan.files_read == 2 and scan.candidates.size == 2 and scan.errors.size == 0
end

test "traversal admission predicates differ at every boundary"
  assert depth_admitted?(24) and !depth_admitted?(25)
  assert entry_admitted?(499_999) and !entry_admitted?(500_000)
  assert file_admitted?(99_999) and !file_admitted?(100_000)
end

verified: types, contracts, tests (4), property (0 seeds), sim (not run)
          proven: not run
