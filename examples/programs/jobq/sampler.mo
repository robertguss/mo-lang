module Jobq.Sampler
expose Step, Problem, step_of, printed, played, main

use Jobq.Board{Command, Call, Outcome, Board, Decision, board, decide}
use Jobq.Job{Job, phase_named, shown, queue?, payload?, reason?, token?, attempts?, lease_ms?}

intent "Play a script of calls through one board, each line a call at its own millisecond after 2026-09-14T10:00:00Z, and print what each call decided: its outcome, then every write in the decision's order, so two boards can be compared by what they print."

# One script line read: the milliseconds after the start, and the call.
struct Step
  ms: UInt64
  call: Call
end

enum Problem
  Usage(detail: String)
  Unread(script: String, why: String)
end

fn start() : Time
  Time.parse("2026-09-14T10:00:00Z") or Time.from_parts(2026, 9, 14, 10, 0, 0)
end

# A line as a call, or None when it does not parse. Its values must keep the rules the API
# checks before a call reaches the board, so no call breaks a contract of Jobq.Job; the
# milliseconds stop at 10^12, about 31 years.
fn step_of(line: String) : Option(Step)
  words = line.split(" ")
  ms = try (words.first or "").to_u64
  return None if ms > 1_000_000_000_000
  worker = words.get(1) or ""
  return None if !token?(worker)
  command = try command_of(words.drop(2))
  Some(Step(ms: ms, call: Call(worker: worker, command: command)))
end

fn command_of(words: List(String)) : Option(Command)
  args = words.drop(1)
  case words.first or ""
    "create": creating(args)
    "fetch": if args.size == 1: Some(Fetch(id: args.first or "")) else: None
    "list": listing(args)
    "remove": if args.size == 1: Some(Remove(id: args.first or "")) else: None
    "lease": leasing(args)
    "ack": if args.size == 1: Some(Ack(id: args.first or "")) else: None
    "fail": failing(args)
    "health": if args.size == 0: Some(Health) else: None
    _: None
  end
end

# A queue, the attempts, and the payload: the rest of the line, spaces and all.
fn creating(args: List(String)) : Option(Command)
  return None if args.size < 3
  queue = args.first or ""
  max_attempts = try (args.get(1) or "").to_u64
  payload = String.join(args.drop(2), " ")
  return None if !queue?(queue) or !attempts?(max_attempts) or !payload?(payload)
  Some(Create(queue: queue, payload: payload, max_attempts: max_attempts))
end

fn listing(args: List(String)) : Option(Command)
  return None if args.size != 2
  queue = args.first or ""
  state = args.get(1) or ""
  return None if queue != "-" and !queue?(queue)
  phase = if state == "-": None else: Some(try phase_named(state))
  Some(Listing(queue: if queue == "-": None else: Some(queue), state: phase))
end

fn leasing(args: List(String)) : Option(Command)
  return None if args.size != 2
  queue = args.first or ""
  lease_ms = try (args.get(1) or "").to_u64
  return None if !queue?(queue) or !lease_ms?(lease_ms)
  Some(Lease(queue: queue, lease_ms: lease_ms))
end

# An id and the reason: the rest of the line, spaces and all.
fn failing(args: List(String)) : Option(Command)
  return None if args.size < 2
  reason = String.join(args.drop(1), " ")
  return None if !reason?(reason)
  Some(Fail(id: args.first or "", reason: reason))
end

# A line that is empty, only spaces, or a comment is not a call.
fn skipped?(line: String) : Bool
  line.starts_with?("#") or line.bytes.all?(fn(b) b == 32 end)
end

# What script line `n` decided, as it prints: the outcome, then each write in order.
fn printed(n: UInt64, decision: Decision) : List(String)
  said(n, decision.outcome).concat(decision.writes.map(fn(w) written(w) end))
end

fn said(n: UInt64, outcome: Outcome) : List(String)
  case outcome
    Made(job): ["#{n} Made #{shown(job)}"]
    Found(job): ["#{n} Found #{shown(job)}"]
    Listed(jobs): ["#{n} Listed #{jobs.size}"].concat(jobs.map(fn(j) "  J #{shown(j)}" end))
    Removed: ["#{n} Removed"]
    Missing: ["#{n} Missing"]
    Conflict(reason): ["#{n} Conflict #{reason}"]
    Empty: ["#{n} Empty"]
    Healthy(counts):
      ["#{n} Healthy queued=#{counts.queued} leased=#{counts.leased} done=#{counts.done} dead=#{counts.dead} uptime_ms=#{counts.uptime_ms}"]
    Unavailable(reason): ["#{n} Unavailable #{reason}"]
  end
end

fn written(write: (String, Option(String))) : String
  case write.1
    Some(value): "  W #{write.0} #{value}"
    None: "  W #{write.0} DEL"
  end
end

# Every line of the script played through one board that starts empty, numbering its first job 1.
fn played(out: Out, lines: List(String))
  var held = board(start(), 1)
  for e in lines.enumerate
    held = stepped(out, held, e.0 + 1, e.1)
  end
end

# The board after script line `n`, with what the line decided written out; a line skipped or
# not parsed leaves the board as it was.
fn stepped(out: Out, held: Board, n: UInt64, line: String) : Board
  return held if skipped?(line)
  case step_of(line)
    Some(step):
      decision = decide(held, step.call, start() + step.ms.to_i64.ms)
      for text in printed(n, decision)
        out.write_line(text)
      end
      decision.board
    None:
      out.write_line("#{n} BadLine")
      held
  end
end

fn script_of(fs: Fs, args: List(String)) : Result(List(String), Problem)
  return Error(Usage(detail: "sampler takes one script")) if args.size != 1
  script = args.first or ""
  case fs.read_only.read_lines(script, within: 10_000.ms)
    Ok(lines): Ok(lines)
    Error(Missing(_)): Error(Unread(script: script, why: "is not a script sampler can read"))
    Error(Timeout): Error(Unread(script: script, why: "took longer than 10 seconds to read"))
    Error(NotText): Error(Unread(script: script, why: "is not UTF-8 text"))
  end
end

fn main(platform: Platform)
  case script_of(platform.fs, platform.args)
    Ok(lines):
      played(platform.stdout, lines)
      platform.stdout.flush
    Error(Usage(detail)):
      platform.stderr.write_line("sampler: #{detail}; usage: sampler <script>")
      platform.exit(2)
    Error(Unread(script: script, why: why)):
      platform.stderr.write_line("sampler: #{script} #{why}")
      platform.exit(1)
  end
end

test "a line parses into its call, and a line that does not, or breaks a job's rules, is none"
  made = Call(worker: "p", command: Create(queue: "emails", payload: "weekly report, \"three\"",
    max_attempts: 3))
  assert step_of("0 p create emails 3 weekly report, \"three\"") == Some(Step(ms: 0, call: made))
  assert step_of("300 p list - dead") == Some(Step(ms: 300,
    call: Call(worker: "p", command: Listing(queue: None, state: Some(Dead)))))
  assert step_of("300 w3 fail j_2 smtp down") == Some(Step(ms: 300,
    call: Call(worker: "w3", command: Fail(id: "j_2", reason: "smtp down"))))
  assert step_of("5 p health") == Some(Step(ms: 5, call: Call(worker: "p", command: Health)))
  assert step_of("this line is not a call") is None
  assert step_of("0 p health now") is None
  assert step_of("0 p create emails 2") is None
  assert step_of("0 p list emails running") is None
  assert step_of("400 w1 lease reports 50") is None
  assert step_of("0  p health") is None
  assert step_of("-1 p health") is None
end

test "a decision prints its outcome, then each write, in order"
  made = decide(board(start(), 1),
    Call(worker: "p", command: Create(queue: "q", payload: "a b", max_attempts: 1)), start())
  assert made.outcome is Made(job)
  assert printed(3, made) == ["3 Made #{shown(job)}", "  W ids 1001", "  W j_1 #{shown(job)}"]
  listed = decide(made.board, Call(worker: "p", command: Listing(queue: None, state: None)),
    start())
  assert printed(4, listed) == ["4 Listed 1", "  J #{shown(job)}"]
  gone = decide(made.board, Call(worker: "p", command: Remove(id: "j_1")), start())
  assert printed(5, gone) == ["5 Removed", "  W j_1 DEL"]
end

test "a script plays through one board, counting the lines it skips"
  out = Out.fixture()
  played(out, ["# a comment", "", "0 p create q 1 x", "not a call", "100 p remove j_1",
    "100 p health"])
  assert out.written.size == 7
  assert out.written.get(3) == Some("4 BadLine\n")
  assert out.written.drop(4) == ["5 Removed\n", "  W j_1 DEL\n",
    "6 Healthy queued=0 leased=0 done=0 dead=0 uptime_ms=100\n"]
end

verified: types, contracts, tests (3), property (0 seeds), sim (not run)
          proven: not run
