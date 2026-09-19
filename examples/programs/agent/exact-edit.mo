module Agent.ExactEdit
expose edited

intent "A trusted text fixture's exact replacement, called only by its serialized Writer on the caller's one deadline; overlapping matches are ambiguous and every refusal precedes the write."

fn result_text(state: String, error: String, execution: String) : String
  "{\"state\": #{Json.encode(state)}, \"error_code\": #{Json.encode(error)}, \"execution\": #{Json.encode(execution)}}"
end

fn edited(files: Fs, path: String, old_text: String, new_text: String, by: Deadline) : String
  if path == "" or path.starts_with?("/") or path.byte_size > 1_024 or path.split("/").contains?("..")
    return result_text("refusal", "invalid_path", "not_started")
  end
  return result_text("refusal", "empty_match", "not_started") if old_text == ""
  case files.size(path, within: by)
    Ok(bytes):
      return result_text("refusal", "size", "not_started") if bytes > 65_536
    Error(_):
      return result_text("refusal", "read", "not_started")
  end
  text = case files.read(path, within: by)
    Ok(found): found
    Error(_):
      return result_text("refusal", "read", "not_started")
  end
  return result_text("refusal", "size", "not_started") if text.byte_size > 65_536
  bytes = text.bytes
  needle = old_text.bytes
  var matches = 0.to_u64
  var at = 0.to_u64
  for i in 0..bytes.size
    return result_text("timeout", "deadline", "not_started") if by.remaining == 0.ms
    if bytes.get(i) == needle.first and bytes.drop(i).take(needle.size) == needle
      matches += 1
      at = i
      if matches > 1
        break
      end
    end
  end
  return result_text("refusal", "missing_match", "not_started") if matches == 0
  return result_text("refusal", "multiple_matches", "not_started") if matches > 1
  # A match of whole characters leaves whole characters, so this refusal is not expected; it is
  # still a refusal before the write, never an empty file written as success.
  changed = case String.from_bytes(bytes.take(at).concat(new_text.bytes).concat(bytes.drop(at + needle.size)))
    Some(whole): whole
    None:
      return result_text("refusal", "invalid_utf8", "not_started")
  end
  return result_text("refusal", "size", "not_started") if changed.byte_size > 65_536
  case files.write(path, changed, within: by)
    Ok(_): result_text("success", "none", "completed")
    Error(Timeout): result_text("timeout", "write_timeout", "unknown")
    Error(_): result_text("failure", "write", "unknown")
  end
end

verified: types, contracts, tests (0), property (0 seeds), sim (not run)
          proven: not run
