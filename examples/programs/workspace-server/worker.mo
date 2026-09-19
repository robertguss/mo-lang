# sim: --faults 20 --until 0.5
module WorkspaceServer.Worker
expose Worker, Tap, Script, Workers, production, scripted_command, digest_of

use WorkspaceServer.Admission{Admission}
use WorkspaceServer.Envelope{Envelope, Outcome, Produced, project, text, done, refusal}
use WorkspaceServer.Journal{Journal}
use WorkspaceServer.Schema{Call}
use WorkspaceServer.Tools{run, inventory}

intent "Execute admitted calls against the workspace folder, the only process that holds it: each file tool runs within the deadline of the connection waiting for it, so the work and the wait end together; the worker, not the connection, journals what the execution came to and tells admission it is over, so a reply that is late or lost keeps its true outcome. A test double's script adds commands, late replies and an event tap, as test_owner.py does for the Python owner."

# What the local test double adds. The production server passes none of it: no commands, no
# delay, no events.
struct Script
  commands: Bool
  late_ms: UInt64
end

fn production() : Script
  Script(commands: false, late_ms: 0)
end

# test_owner.py's scripted commands: exit 7, 123 ms, the named delay, and its two odd outputs.
fn scripted_command(command: String) : (Outcome, UInt64)
  delay = case command
    "slow": 600
    "lease-slow": 1_300
    "stall": 20_000
    _: 0
  end
  if command == "binary"
    return (Outcome(state: "failure", execution: "completed", error: Some("output_encoding"),
      produced: Undecodable(exit_code: 7, elapsed_ms: 123)),
      delay)
  end
  ran = Ran(exit_code: 7, stdout: "hello 🌊", stderr: "", elapsed_ms: 123)
  if command == "timeout"
    return (Outcome(state: "timeout", execution: "completed", error: None, produced: ran), delay)
  end
  (done(ran), delay)
end

# The SHA-256 of the tree's inventory, one `path sha256` line per file, or why there is none.
fn digest_of(workspace: Fs, by: Deadline) : String
  case inventory(workspace, ".", by)
    Ok(rows):
      Hash.hex(Hash.sha256(String.join(rows.map(fn(r)
        "#{r.path} #{r.sha256}\n"
      end), "").bytes))
    Error(_): "unreadable"
  end
end

# Where the double writes each operation it starts, for the tests to wait on.
process Tap(fs: Fs)
  state
    lost: UInt64
  end

  message Event(name: String)

  fn update(state, message)
    case message
      Event(name):
        if fs.append("events", "#{name}\n", within: 1_000.ms) is Error(_)
          state.lost += 1
        end
    end
  end
end

process Worker(workspace: Fs, journal: Handle(Journal), admission: Handle(Admission),
  script: Script, tap: Option(Handle(Tap)))
  state
    me: Option(Handle(Worker))
    held: List(Reply(Envelope))
    held_call: String
    held_envelope: Option(Envelope)
    executed: UInt64
  end

  message Know(me: Handle(Worker))
  message Do(call: Call, core_id: String) : Envelope
  message Release
  message Digest : String

  fn update(state, message)
    case message
      Know(me):
        state.me = Some(me)
      Do(call: call, core_id: _):
        tapped(tap, call.operation)
        worked = worked(workspace, script, call, reply_by)
        envelope = project(call, worked.0)
        state.held = state.held.push(reply_to)
        state.held_call = call.call_id
        state.held_envelope = Some(envelope)
        state.executed += 1
        if worked.1 == 0 or state.me == None
          finish(journal, admission, call.call_id, envelope, reply_by.remaining)
          state.held_envelope = None
          for r in state.held
            r.answer(envelope)
          end
          state.held = []
        else
          later(state.me, worked.1)
        end
      Release:
        if state.held_envelope is Some(envelope)
          finish(journal, admission, state.held_call, envelope, 2_000.ms)
          for r in state.held
            r.answer(envelope)
          end
          state.held = []
          state.held_envelope = None
        end
      Digest: digest_of(workspace, reply_by)
    end
  end
end

supervisor Workers(workspace: Fs, journal: Handle(Journal), admission: Handle(Admission),
  script: Script, tap: Option(Handle(Tap)), fs: Fs)
  child Worker(workspace, journal, admission, script, tap), restart: :on_crash
  child Tap(fs), restart: :always
end

# What a call came to, and how long the double holds its reply back.
fn worked(workspace: Fs, script: Script, call: Call, by: Deadline) : (Outcome, UInt64)
  if call.operation == "command"
    return (refusal("request_refused"), 0) if !script.commands
    return scripted_command(call.args.get("command") or "")
  end
  (run(workspace, call, by), script.late_ms)
end

fn tapped(tap: Option(Handle(Tap)), name: String)
  if tap is Some(t)
    t.send(Event(name: name))
  end
end

fn later(me: Option(Handle(Worker)), delay: UInt64)
  if me is Some(m)
    m.send(Release, delay: delay.ms)
  end
end

# The execution is journaled by the one who ran it, then admission is told it is over.
fn finish(journal: Handle(Journal), admission: Handle(Admission), call_id: String,
  envelope: Envelope, by: Duration)
  recorded = journal.ask(Executed(call_id: call_id, execution: envelope.execution,
    result: text(envelope)),
    within: by)
  admission.send(Finished(call_id: call_id))
  if recorded != Ok(true)
    admission.send(Close(why: "execution_unjournaled"))
  end
end

test "the scripted commands are test_owner.py's"
  assert scripted_command("slow").1 == 600
  assert scripted_command("binary").0.error == Some("output_encoding")
  assert scripted_command("timeout").0.state == "timeout"
  assert scripted_command("echo").0.state == "success"
end

test "a file call runs, is journaled by the worker, and frees admission"
  fs = Fs.fixture()
  assert fs.write("data/a", "héllo", within: 1.minute) is Ok(_)
  journal = Journal.start(fs, 4_194_304)
  assert journal.ask(Bind(binding: "{}"), within: 1.minute) == Ok(true)
  admission = Admission.start(journal, Clock.fixture(), Random.fixture(), 900_000)
  assert admission.ask(Open, within: 1.minute) == Ok(true)
  worker = Worker.start(fs.scoped("data"), journal, admission, production(), None)
  call = Call(run_id: "r", workspace_id: "0".repeat(32), call_id: "c1", operation: "read_file",
    args: Map.new().set("path", "a"), timeout_ms: 0)
  assert admission.ask(Admit(call_id: "c1", payload_sha256: "x", operation: "read_file"),
    within: 1.minute) is Ok(Yes(core_id: core, wait_ms: _))
  assert worker.ask(Do(call: call, core_id: core), within: 1.minute) is Ok(envelope)
  assert envelope.result == Some("{\"text\": \"héllo\", \"truncated\": false}")
  assert admission.ask(Status, within: 1.minute) is Ok(standing)
  assert !standing.active
  assert fs.read("owner.json", within: 1.minute) is Ok(journaled)
  assert journaled.contains?("\"execution\": \"completed\", \"result\": {\"version\"")
end

test "the production worker serves no command"
  fs = Fs.fixture()
  worked = worked(fs, production(),
    Call(run_id: "r", workspace_id: "w", call_id: "c", operation: "command", args: Map.new(),
    timeout_ms: 500),
    Deadline.fixture(1.minute))
  assert worked.0.error == Some("request_refused")
end

verified: types, contracts, tests (3), property (0 seeds), sim (200 runs)
          proven: not run
