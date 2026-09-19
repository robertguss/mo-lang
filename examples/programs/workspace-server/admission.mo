module WorkspaceServer.Admission
expose Admission, Admitted, Standing, Admissions, wait_for

use WorkspaceServer.Journal{Journal, entry_of}

intent "Admit at most one operation at a time and never queue one: a call is refused busy while another runs, conflict when its ID was admitted before, admission_closed once admission is closed or less than half a second of the 900-second lease is left, call_limit past 16 calls, and journal_full when the journal could not record its intent; an admitted call has its intent journaled before it is answered, so no effect precedes it. The lease runs from readiness and is never reset."

enum Admitted
  Yes(core_id: String, wait_ms: UInt64)
  No(error: String)
end

struct Standing
  open: Bool
  active: Bool
  calls: UInt64
  why: String
end

# How long a connection waits for an operation's reply: two seconds for a file tool, 300 for
# a command, never past the lease.
fn wait_for(operation: String, lease_left_ms: UInt64) : UInt64
  limit = if operation == "command": 300_000 else: 2_000
  min_of(limit, lease_left_ms)
end

process Admission(journal: Handle(Journal), clock: Clock, random: Random, lease_ms: UInt64)
  state
    lease_end: Option(Time)
    active: Option(String)
    calls: Set(String)
    closed: Bool
    why: String
    waiting: List(Reply(Bool))
  end

  invariant "no more than 16 calls are ever admitted"
    state.calls.size <= 16
  end

  message Open : Bool
  message Admit(call_id: String, payload_sha256: String, operation: String) : Admitted
  message Finished(call_id: String)
  message Close(why: String)
  message Status : Standing
  message Drained : Bool

  fn update(state, message)
    case message
      Open:
        state.lease_end = Some(clock.now + lease_ms.ms)
        true
      Admit(call_id: call_id, payload_sha256: sha, operation: operation):
        left = left_ms(state.lease_end, clock.now)
        refusal = refusal_of(state.active, state.calls, state.closed, left, call_id)
        if refusal != ""
          No(error: refusal)
        else
          core_id = Hash.hex(random.bytes(16))
          if journal.ask(Intent(call_id: call_id, entry: entry_of(core_id, sha, operation)), within: reply_by) == Ok(true)
            state.active = Some(call_id)
            state.calls = state.calls.add(call_id)
            Yes(core_id: core_id, wait_ms: wait_for(operation, left))
          else
            No(error: "journal_full")
          end
        end
      Finished(call_id):
        if state.active == Some(call_id)
          state.active = None
          for waiter in state.waiting
            waiter.answer(true)
          end
          state.waiting = []
        end
      Close(why):
        if !state.closed
          state.closed = true
          state.why = why
        end
      Status:
        open = !state.closed and left_ms(state.lease_end, clock.now) >= 500
        Standing(open: open, active: state.active != None, calls: state.calls.size, why: state.why)
      Drained:
        state.waiting = state.waiting.push(reply_to)
        if state.active == None
          for waiter in state.waiting
            waiter.answer(true)
          end
          state.waiting = []
        end
    end
  end
end

# What is left of the lease, in milliseconds; none before readiness opens it.
fn left_ms(lease_end: Option(Time), now: Time) : UInt64
  case lease_end
    Some(end_at):
      return 0 if end_at <= now
      (end_at - now).ms.to_u64
    None: 0
  end
end

# The first refusal that applies, in the bridge's order, or "" to admit.
fn refusal_of(active: Option(String), calls: Set(String), closed: Bool, left: UInt64,
  call_id: String) : String
  return "busy" if active != None
  return "conflict" if calls.has?(call_id)
  return "admission_closed" if closed or left < 500
  return "call_limit" if calls.size >= 16
  ""
end

supervisor Admissions(journal: Handle(Journal), clock: Clock, random: Random, lease_ms: UInt64)
  child Admission(journal, clock, random, lease_ms), restart: :never
end

test "one call at a time: a second is busy, and after the first finishes it is admitted"
  admission = Admission.start(Journal.start(Fs.fixture(), 4_194_304), Clock.fixture(), Random.fixture(), 900_000)
  assert admission.ask(Open, within: 1.minute) == Ok(true)
  assert admission.ask(Admit(call_id: "a", payload_sha256: "x", operation: "list_files"), within: 1.minute) is Ok(Yes(core_id: core, wait_ms: 2_000))
  assert core.byte_size == 32
  assert admission.ask(Admit(call_id: "b", payload_sha256: "x", operation: "list_files"), within: 1.minute) == Ok(No(error: "busy"))
  admission.send(Finished(call_id: "a"))
  assert admission.ask(Admit(call_id: "a", payload_sha256: "x", operation: "list_files"), within: 1.minute) == Ok(No(error: "conflict"))
  assert admission.ask(Admit(call_id: "b", payload_sha256: "x", operation: "list_files"), within: 1.minute) is Ok(Yes(core_id: _, wait_ms: _))
end

test "the refusals come in the bridge's order"
  assert refusal_of(Some("a"), Set.new().add("b"), true, 0, "b") == "busy"
  assert refusal_of(None, Set.new().add("b"), true, 0, "b") == "conflict"
  assert refusal_of(None, Set.new(), false, 499, "b") == "admission_closed"
  full = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15"]
  assert refusal_of(None, full.reduce(Set.new(), fn(s, id) s.add(id) end), false, 900_000, "b") == "call_limit"
  assert refusal_of(None, full.reduce(Set.new(), fn(s, id) s.add(id) end), true, 900_000, "b") == "admission_closed"
end

test "closed stays closed, and a lease not opened admits nothing"
  admission = Admission.start(Journal.start(Fs.fixture(), 4_194_304), Clock.fixture(), Random.fixture(), 900_000)
  assert admission.ask(Open, within: 1.minute) == Ok(true)
  admission.send(Close(why: "operator"))
  assert admission.ask(Admit(call_id: "a", payload_sha256: "x", operation: "read_file"), within: 1.minute) == Ok(No(error: "admission_closed"))
  unopened = Admission.start(Journal.start(Fs.fixture(), 4_194_304), Clock.fixture(), Random.fixture(), 900_000)
  assert unopened.ask(Admit(call_id: "a", payload_sha256: "x", operation: "read_file"), within: 1.minute) == Ok(No(error: "admission_closed"))
end

test "a journal that cannot hold the intent refuses the call, and nothing is active"
  journal = Journal.start(Fs.fixture(), 10)
  assert journal.ask(Bind(binding: "{}"), within: 1.minute) == Ok(true)
  admission = Admission.start(journal, Clock.fixture(), Random.fixture(), 900_000)
  assert admission.ask(Open, within: 1.minute) == Ok(true)
  assert admission.ask(Admit(call_id: "a", payload_sha256: "x", operation: "read_file"), within: 1.minute) == Ok(No(error: "journal_full"))
  assert admission.ask(Status, within: 1.minute) is Ok(standing)
  assert !standing.active and standing.calls == 0
end

test "waits: two seconds for a file, 300 for a command, never past the lease"
  assert wait_for("read_file", 900_000) == 2_000
  assert wait_for("command", 900_000) == 300_000
  assert wait_for("command", 700) == 700
end
