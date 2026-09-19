module WorkspaceServer.Envelope
expose Ids, Envelope, Row, Hit, Produced, Outcome, ids_of, refused, project, text, capped, result_text, bounded_output, output_cap, done, refusal, timed_out, row_text, hit_text

use WorkspaceServer.Schema{Call, version}
use WorkspaceServer.Wire{response_cap}

intent "The one response shape every reply has, the outcome a tool call comes to before it is shown, and the projection between them: a success carries the result its operation names or it is invalid_result, command output past its bound is cut and marked truncated, and a response past 524,288 bytes becomes response_too_large."

struct Ids
  run_id: String
  workspace_id: String
  call_id: String
end

# Every response: identities are None until the whole call has been read and bound.
struct Envelope
  ids: Option(Ids)
  accepted: Bool
  state: String
  execution: String
  error: Option(String)
  result: Option(String)
end

# A listed file. Mo's Fs does not show permission bits, so every row's mode is 420 (0644).
struct Row
  path: String
  length: UInt64
  sha256: String
end

# A search hit: the file and the byte offset of the match in it.
struct Hit
  path: String
  offset: UInt64
end

# What a call produced, one variant per operation, so a success cannot lack its field.
enum Produced
  Listed(rows: List(Row), truncated: Bool)
  Read(text: String)
  Found(hits: List(Hit), truncated: Bool)
  Written
  Edited
  Ran(exit_code: Int64, stdout: String, stderr: String, elapsed_ms: UInt64)
  Undecodable(exit_code: Int64, elapsed_ms: UInt64)
  Nothing
end

# What executing one call came to: state, execution, the stable error, and what it produced.
struct Outcome
  state: String
  execution: String
  error: Option(String)
  produced: Produced
end

fn done(produced: Produced) : Outcome
  Outcome(state: "success", execution: "completed", error: None, produced: produced)
end

# A refusal the tool reached after looking: it completed, and changed nothing.
fn refusal(error: String) : Outcome
  Outcome(state: "refusal", execution: "completed", error: Some(error), produced: Nothing)
end

# A call whose own deadline passed inside it: what it did is not known.
fn timed_out() : Outcome
  Outcome(state: "timeout", execution: "unknown", error: Some("deadline"), produced: Nothing)
end

fn ids_of(call: Call) : Ids
  Ids(run_id: call.run_id, workspace_id: call.workspace_id, call_id: call.call_id)
end

# A refusal before admission: nothing started.
fn refused(ids: Option(Ids), error: String) : Envelope
  Envelope(ids: ids, accepted: false, state: "refusal", execution: "not_started",
    error: Some(error), result: None)
end

fn output_cap() : UInt64
  65_536
end

# The two streams cut to 65,536 bytes together, stdout first, each at a character boundary,
# and whether anything was cut (review finding H4: past the bound is truncated, not an
# encoding failure).
fn bounded_output(stdout: String, stderr: String) : (String, String, Bool)
  return (stdout, stderr, false) if stdout.byte_size + stderr.byte_size <= output_cap()
  out = prefix(stdout, output_cap())
  err = prefix(stderr, output_cap() - out.byte_size)
  (out, err, true)
end

# The longest prefix of whole graphemes within `bytes`.
fn prefix(text: String, bytes: UInt64) : String
  var low = 0
  var high = text.size
  for _ in 0..64
    if low < high
      middle = (low + high + 1) / 2
      if text.slice(0, middle).byte_size <= bytes
        low = middle
      else
        high = middle - 1
      end
    end
  end
  text.slice(0, low)
end

fn fits?(operation: String, produced: Produced) : Bool
  case produced
    Listed(rows: _, truncated: _): operation == "list_files"
    Read(_): operation == "read_file"
    Found(hits: _, truncated: _): operation == "search"
    Written: operation == "write_file"
    Edited: operation == "exact_edit"
    Ran(exit_code: _, stdout: _, stderr: _, elapsed_ms: _) | Undecodable(exit_code: _,
      elapsed_ms: _):
      operation == "command"
    Nothing: false
  end
end

# The admitted response for an outcome. A success whose result is not its operation's is
# invalid_result (review finding H5); a result with nothing in it is null.
fn project(call: Call, outcome: Outcome) : Envelope
  ids = Some(ids_of(call))
  if outcome.state == "success" and !fits?(call.operation, outcome.produced)
    return Envelope(ids: ids, accepted: true, state: "failure", execution: "unknown",
      error: Some("invalid_result"), result: None)
  end
  capped(Envelope(ids: ids, accepted: true, state: outcome.state, execution: outcome.execution,
    error: outcome.error, result: result_text(outcome.produced)))
end

fn capped(e: Envelope) : Envelope
  return e if text(e).byte_size <= response_cap()
  Envelope(ids: e.ids, accepted: e.accepted, state: "refusal", execution: e.execution,
    error: Some("response_too_large"), result: None)
end

fn result_text(produced: Produced) : Option(String)
  case produced
    Listed(rows: rows, truncated: cut): Some(items(rows.map(fn(r) row_text(r) end), cut))
    Read(text): Some("{\"text\": #{Json.encode(text)}, \"truncated\": false}")
    Found(hits: hits, truncated: cut):
      Some(items(hits.map(fn(h)
        "{\"path\": #{Json.encode(h.path)}, \"offset\": #{h.offset}}"
      end), cut))
    Written: Some("{\"written\": true, \"truncated\": false}")
    Edited: Some("{\"edited\": true, \"truncated\": false}")
    Ran(exit_code: code, stdout: out, stderr: err, elapsed_ms: ms): Some(ran(code, out, err, ms))
    Undecodable(exit_code: code, elapsed_ms: ms): Some(undecodable(code, ms))
    Nothing: None
  end
end

fn row_text(r: Row) : String
  "{\"path\": #{Json.encode(r.path)}, \"length\": #{r.length}, \"sha256\": \"#{r.sha256}\", \"mode\": 420}"
end

fn hit_text(h: Hit) : String
  "{\"path\": #{Json.encode(h.path)}, \"offset\": #{h.offset}}"
end

fn items(texts: List(String), truncated: Bool) : String
  "{\"items\": [#{String.join(texts, ", ")}], \"truncated\": #{truncated}}"
end

fn ran(code: Int64, stdout: String, stderr: String, ms: UInt64) : String
  cut = bounded_output(stdout, stderr)
  streams = "\"stdout\": #{Json.encode(cut.0)}, \"stderr\": #{Json.encode(cut.1)}"
  "{\"exit_code\": #{code}, \"signal\": null, \"execution_valid\": true, #{streams}, \"encoding\": \"utf-8\", \"truncated\": #{cut.2}, \"elapsed_ms\": #{ms}}"
end

fn undecodable(code: Int64, ms: UInt64) : String
  "{\"exit_code\": #{code}, \"signal\": null, \"execution_valid\": true, \"stdout\": null, \"stderr\": null, \"encoding\": \"utf-8\", \"truncated\": false, \"elapsed_ms\": #{ms}}"
end

fn nullable(text: Option(String)) : String
  case text
    Some(t): Json.encode(t)
    None: "null"
  end
end

fn text(e: Envelope) : String
  ids = case e.ids
    Some(i):
      "\"run_id\": #{Json.encode(i.run_id)}, \"workspace_id\": #{Json.encode(i.workspace_id)}, \"call_id\": #{Json.encode(i.call_id)}"
    None: "\"run_id\": null, \"workspace_id\": null, \"call_id\": null"
  end
  tail = "\"error\": #{nullable(e.error)}, \"result\": #{e.result or "null"}"
  "{\"version\": \"#{version()}\", #{ids}, \"accepted\": #{e.accepted}, \"state\": \"#{e.state}\", \"execution\": \"#{e.execution}\", #{tail}}"
end

fn a_call(operation: String) : Call
  Call(run_id: "r", workspace_id: "0".repeat(32), call_id: "c", operation: operation,
    args: Map.new(), timeout_ms: 0)
end

test "a refusal before admission names no identities and started nothing"
  got = text(refused(None, "busy"))
  assert Json.decode(got) is Ok(Object(fields))
  assert fields.keys == ["version",
    "run_id",
    "workspace_id",
    "call_id",
    "accepted",
    "state",
    "execution",
    "error",
    "result"]
  assert got.contains?("\"run_id\": null") and got.contains?("\"execution\": \"not_started\"")
end

test "a success carries its operation's result, or it is invalid_result"
  read = project(a_call("read_file"), done(Read(text: "héllo")))
  assert read.result == Some("{\"text\": \"héllo\", \"truncated\": false}")
  wrong = project(a_call("read_file"), done(Written))
  assert (wrong.state, wrong.execution, wrong.error) == ("failure", "unknown",
    Some("invalid_result"))
  empty = project(a_call("list_files"), done(Nothing))
  assert empty.error == Some("invalid_result")
end

test "a refusal keeps its completed execution and has no result"
  got = project(a_call("exact_edit"), refusal("missing_match"))
  assert (got.state, got.execution, got.error, got.result) == ("refusal", "completed",
    Some("missing_match"), None)
end

test "a response past its cap is response_too_large, not truncated"
  big = project(a_call("read_file"), done(Read(text: "x".repeat(600_000))))
  assert (big.state, big.error, big.result) == ("refusal", Some("response_too_large"), None)
end

test "command output past 65,536 bytes is cut at a character and marked truncated"
  assert bounded_output("ab", "c") == ("ab", "c", false)
  cut = bounded_output("é".repeat(40_000), "tail")
  assert cut.0.byte_size == 65_536 and cut.1 == "" and cut.2
  odd = bounded_output("x#{"é".repeat(40_000)}", "")
  assert odd.0.byte_size == 65_535 and odd.2
  shown = project(a_call("command"),
    done(Ran(exit_code: 0, stdout: "y".repeat(70_000), stderr: "", elapsed_ms: 5)))
  assert shown.state == "success" and (shown.result or "").contains?("\"truncated\": true")
end

verified: types, contracts, tests (5), property (0 seeds), sim (not run)
          proven: not run
