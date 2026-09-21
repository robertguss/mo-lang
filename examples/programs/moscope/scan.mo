module Moscope.Scan
expose scan_tree

use Moscope.Limits{depth, entries, files, file_bytes, total_bytes, diagnostics,
  call_time, process_time}
use Moscope.Model{Issue, Scan, Discovery, empty_scan, empty_discovery}
use Moscope.Parse{start_file, folded_line}

intent "Discover JSONL files serially from one read-only root, without following discovered links, then size-admit and fold them in deterministic path order."

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
    if found.entries >= entries()
      return discovery_stop(found, path, "traversal exceeds 50000 entries")
    end
    found.entries += 1
    child = joined(path, name)
    case root.kind_of(child, within: call_time())
      Error(error):
        found = discovery_problem(found, child, "cannot stat entry: #{fs_error(error)}")
      Ok(entry):
        case entry.kind
          Link: found.skipped_links += 1
          Folder:
            if child.ends_with?(".jsonl")
              found = discovery_problem(found, child,
                "a .jsonl candidate is a directory, not a regular file")
            end
            found = discover(root, child, level + 1, found, clock, started)
          File:
            if child.ends_with?(".jsonl")
              if found.files.size >= files()
                return discovery_stop(found, child, "discovery exceeds 5000 JSONL files")
              end
              found.files = found.files.push(child)
            end
        end
    end
    if found.stopped
      break
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
  initial = start_file(next, path, bytes, clock, started)
  case root.fold_lines(path, initial, within: call_time(), fn(state, line)
    folded_line(state, line)
  end)
    Ok(done):
      next = done.scan
      next.files_read += 1
      next
    Error(error):
      scan_problem(next, path, 0, "cannot read admitted .jsonl input: #{fs_error(error)}")
  end
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
