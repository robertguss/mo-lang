# sim: --faults 20 --until 0.5
module WorkspaceServer.Journal
expose Journal, Entry, Journals, reserve, binding_text, entry_of, intent_first?

intent "Keep the run's journal: one process owns owner.json in the run folder and rewrites it whole with Fs.replace after every record. Its first row binds the run to the hashes of the source and of the verifier configuration; each call has its admission and intent, then its execution, the reply produced and its delivery as four separate records, so a lost reply keeps its true outcome; cleanup is a record of its own. An intent is refused, before any effect, when the journal could not also hold that call's largest reply."

# One admitted call. Execution is `pending` until the worker reports it; the reply and the
# delivery are the connection's, recorded separately.
struct Entry
  core_call_id: String
  payload_sha256: String
  operation: String
  execution: String
  result: Option(String)
  reply: Option(String)
  delivery: Option(String)
end

# The room held back for one call's records: its largest response and some metadata.
fn reserve() : UInt64
  524_288 + 8_192
end

fn hex_or_null(text: String) : String
  if text == "" or text == "unreadable": "null" else: Json.encode(text)
end

# The first journal row: the operator's source hash (null when none was given), the
# server's own digest of the tree (null when a link or a special entry refuses the walk),
# and the hash of the verifier configuration.
fn binding_text(run_id: String, workspace_id: String, source: String, observed: String,
  verifier: String) : String
  "{\"run_id\": #{Json.encode(run_id)}, \"workspace_id\": #{Json.encode(workspace_id)}, \"source_sha256\": #{hex_or_null(source)}, \"observed_sha256\": #{hex_or_null(observed)}, \"verifier_sha256\": \"#{verifier}\"}"
end

fn entry_of(core_id: String, payload_sha256: String, operation: String) : Entry
  Entry(core_call_id: core_id, payload_sha256: payload_sha256, operation: operation,
    execution: "pending", result: None, reply: None, delivery: None)
end

# An execution recorded only for a call whose intent is there, and only once.
fn intent_first?(calls: Map(String, Entry), call_id: String) : Bool
  case calls.get(call_id)
    Some(e): e.execution == "pending"
    None: false
  end
end

process Journal(run: Fs, cap: UInt64)
  state
    binding: String
    calls: Map(String, Entry)
    cleanup: String = "{\"cleanup\": \"unresolved\", \"execution\": \"unknown\"}"
    frozen: String = "null"
    size: UInt64
    stray: UInt64
    unwritten: UInt64
  end

  invariant "every execution recorded follows its call's intent, and no call executes twice"
    state.stray == 0
  end

  message Bind(binding: String) : Bool
  message Intent(call_id: String, entry: Entry) : Bool
  message Executed(call_id: String, execution: String, result: String) : Bool
  message Replied(call_id: String, reply: String) : Bool
  message Delivered(call_id: String, delivery: String, unknown: Bool) : Bool
  message Cleaned(cleanup: String) : Bool
  message Froze(frozen: String) : Bool

  fn update(state, message)
    case message
      Bind(binding):
        state.binding = binding
        state.size = document(state.binding, state.calls, state.cleanup, state.frozen).byte_size
        written(run, document(state.binding, state.calls, state.cleanup, state.frozen), reply_by)
      Intent(call_id: call_id, entry: entry):
        if state.calls.has?(call_id) or state.size + reserve() > cap
          false
        else
          state.calls = state.calls.set(call_id, entry)
          text = document(state.binding, state.calls, state.cleanup, state.frozen)
          state.size = text.byte_size
          written(run, text, reply_by)
        end
      Executed(call_id: call_id, execution: execution, result: result):
        if !intent_first?(state.calls, call_id)
          state.stray += 1
          false
        else
          state.calls = executed(state.calls, call_id, execution, result)
          written(run, document(state.binding, state.calls, state.cleanup, state.frozen), reply_by)
        end
      Replied(call_id: call_id, reply: reply):
        state.calls = replied(state.calls, call_id, reply)
        written(run, document(state.binding, state.calls, state.cleanup, state.frozen), reply_by)
      Delivered(call_id: call_id, delivery: delivery, unknown: unknown):
        state.calls = delivered(state.calls, call_id, delivery)
        if unknown
          noted = "{\"delivery\": \"unknown\", \"call_id\": #{Json.encode(call_id)}, \"record\": #{delivery}}"
          state.unwritten += if run.replace("delivery.json", noted, within: reply_by) is Ok(_): 0 else: 1
        end
        written(run, document(state.binding, state.calls, state.cleanup, state.frozen), reply_by)
      Cleaned(cleanup):
        state.cleanup = cleanup
        written(run, document(state.binding, state.calls, state.cleanup, state.frozen), reply_by)
      Froze(frozen):
        state.frozen = frozen
        written(run, document(state.binding, state.calls, state.cleanup, state.frozen), reply_by)
    end
  end
end

# Never restarted: a new journal would start empty and write over the old one's records, so a
# journal that stops leaves every later intent refused instead.
supervisor Journals(run: Fs, cap: UInt64)
  child Journal(run, cap), restart: :never
end

fn written(run: Fs, text: String, by: Deadline) : Bool
  run.replace("owner.json", text, within: by) is Ok(_)
end

fn executed(calls: Map(String, Entry), call_id: String, execution: String, result: String) : Map(String, Entry)
  case calls.get(call_id)
    Some(e):
      calls.set(call_id, Entry(core_call_id: e.core_call_id, payload_sha256: e.payload_sha256,
        operation: e.operation, execution: execution, result: Some(result), reply: e.reply,
        delivery: e.delivery))
    None: calls
  end
end

fn replied(calls: Map(String, Entry), call_id: String, reply: String) : Map(String, Entry)
  case calls.get(call_id)
    Some(e):
      calls.set(call_id, Entry(core_call_id: e.core_call_id, payload_sha256: e.payload_sha256,
        operation: e.operation, execution: e.execution, result: e.result, reply: Some(reply),
        delivery: e.delivery))
    None: calls
  end
end

fn delivered(calls: Map(String, Entry), call_id: String, delivery: String) : Map(String, Entry)
  case calls.get(call_id)
    Some(e):
      calls.set(call_id, Entry(core_call_id: e.core_call_id, payload_sha256: e.payload_sha256,
        operation: e.operation, execution: e.execution, result: e.result, reply: e.reply,
        delivery: Some(delivery)))
    None: calls
  end
end

fn row(call_id: String, e: Entry) : String
  first = "#{Json.encode(call_id)}: {\"core_call_id\": \"#{e.core_call_id}\", \"payload_sha256\": \"#{e.payload_sha256}\", \"operation\": #{Json.encode(e.operation)}, \"admission\": \"admitted\", \"intent\": true"
  "#{first}, \"execution\": \"#{e.execution}\", \"result\": #{e.result or "null"}, \"reply\": #{e.reply or "null"}, \"delivery\": #{e.delivery or "null"}}"
end

fn document(binding: String, calls: Map(String, Entry), cleanup: String, frozen: String) : String
  rows = String.join(calls.entries.map(fn(pair) row(pair.0, pair.1) end), ", ")
  "{\"version\": \"mo-workspace-server-journal-v1\", \"binding\": #{binding}, \"calls\": {#{rows}}, \"cleanup\": #{cleanup}, \"frozen\": #{frozen}}"
end

fn bound() : String
  binding_text("run-1", "0".repeat(32), "a".repeat(64), "a".repeat(64), "b".repeat(64))
end

test "the binding is the first row, and each record rewrites the whole journal"
  fs = Fs.fixture()
  journal = Journal.start(fs, 4_194_304)
  assert journal.ask(Bind(binding: bound()), within: 1.minute) == Ok(true)
  assert journal.ask(Intent(call_id: "c1", entry: entry_of("1".repeat(32), "f".repeat(64), "read_file")), within: 1.minute) == Ok(true)
  assert journal.ask(Executed(call_id: "c1", execution: "completed", result: "{\"state\": \"success\"}"), within: 1.minute) == Ok(true)
  assert journal.ask(Replied(call_id: "c1", reply: "{\"status\": 504}"), within: 1.minute) == Ok(true)
  assert journal.ask(Cleaned(cleanup: "{\"cleanup\": \"confirmed\"}"), within: 1.minute) == Ok(true)
  assert fs.read("owner.json", within: 1.minute) is Ok(text)
  assert Json.decode(text) is Ok(Object(fields))
  assert fields.keys == ["version", "binding", "calls", "cleanup", "frozen"]
  assert text.contains?("\"execution\": \"completed\", \"result\": {\"state\": \"success\"}, \"reply\": {\"status\": 504}")
end

test "an intent the journal could not hold with its largest reply is refused, and a repeat too"
  fs = Fs.fixture()
  small = Journal.start(fs, reserve() + 100)
  assert small.ask(Bind(binding: bound()), within: 1.minute) == Ok(true)
  assert small.ask(Intent(call_id: "c1", entry: entry_of("1", "2", "list_files")), within: 1.minute) == Ok(false)
  roomy = Journal.start(Fs.fixture(), 4_194_304)
  assert roomy.ask(Bind(binding: bound()), within: 1.minute) == Ok(true)
  assert roomy.ask(Intent(call_id: "c1", entry: entry_of("1", "2", "list_files")), within: 1.minute) == Ok(true)
  assert roomy.ask(Intent(call_id: "c1", entry: entry_of("3", "4", "list_files")), within: 1.minute) == Ok(false)
end

test "an execution with no intent before it is refused"
  assert !intent_first?(Map.new(), "c9")
  once = Map.new().set("c1", entry_of("1", "2", "read_file"))
  assert intent_first?(once, "c1")
  assert !intent_first?(executed(once, "c1", "completed", "{}"), "c1")
end

test "a delivery that is not known leaves delivery.json beside the journal"
  fs = Fs.fixture()
  journal = Journal.start(fs, 4_194_304)
  assert journal.ask(Bind(binding: bound()), within: 1.minute) == Ok(true)
  assert journal.ask(Intent(call_id: "c1", entry: entry_of("1", "2", "read_file")), within: 1.minute) == Ok(true)
  delivery = "{\"known\": false, \"written\": false}"
  assert journal.ask(Delivered(call_id: "c1", delivery: delivery, unknown: true), within: 1.minute) == Ok(true)
  assert journal.ask(Froze(frozen: "{\"sha256\": \"x\"}"), within: 1.minute) == Ok(true)
  assert fs.read("delivery.json", within: 1.minute) is Ok(text)
  assert text.starts_with?("{\"delivery\": \"unknown\"")
end
