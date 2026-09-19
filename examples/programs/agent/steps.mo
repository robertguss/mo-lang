module Agent.Steps
expose Setup, Phase, Counting, Progress, Ran, fresh, begun, asked, using, stopped, advanced, asks?, uses?, budget_end, not_begun, request_of, call_ms, ran_of, call_for, model_step, tool_step, model_outcome, error_text, reply_text, took

use Agent.Model{Model, Reply, ModelError, Request, spent?, tokens_of}
use Agent.Record{Budget, Order, Status}
use Agent.Shelf{Ending, ending}
use Agent.Tools{Call, Used}
use Agent.Transcript{Step, step_json}

intent "A run's loop as values: where the run is, what it has taken against its budget, the model call it makes and the step each call becomes, the tool call a reply names, and how a run ends when a budget is spent or the model fails."

never "a tool runs past its run's steps, tokens, or wall budget, or without the book's go"
  for r in Ran.all
    !r.go or r.spent or r.taken > r.steps or r.tokens_used > r.tokens
  end
end

# What a run was started for: its id, its order, and the model it asks.
struct Setup
  id: String
  order: Order
  model: Model
end

# Where a run is: not begun, asking the model, having a step written, using a tool, having its end
# written, or stopped.
enum Phase
  Ready
  Asking
  Recording
  Using
  Closing
  Stopped
end

# What a run's steps budget counts, chosen once when the run is configured: a plain run counts its
# model calls, and a fixture or application run counts every step it records, model and tool alike.
enum Counting
  ModelCalls
  RecordedSteps
end

# A run's loop so far: its id (for whoever reads the run's state), its deadline, its phase, the steps written (as the model is shown them), the
# last step's number, the model calls taken and their tokens, when the call in hand began, the
# model's reply and the tool's outcome in hand, the step and the end being written, and the book's
# answers missed in a row.
struct Progress
  id: String
  by: Option(Deadline)
  phase: Phase
  steps: List(String)
  n: UInt64
  taken: UInt64
  tokens: UInt64
  began: Option(Time)
  reply: Option(Result(Reply, ModelError))
  used: Option(Used)
  step: Option(Step)
  ending: Option(Ending)
  missed: UInt64
end

# One tool about to run, beside what it runs under: the book's go for it, whether the run's
# deadline is spent, and the steps and tokens taken against their bounds.
struct Ran
  go: Bool
  spent: Bool
  taken: UInt64
  steps: UInt64
  tokens_used: UInt64
  tokens: UInt64
end

fn fresh(id: String) : Progress
  Progress(id: id, by: None, phase: Ready, steps: [], n: 0, taken: 0, tokens: 0, began: None,
    reply: None, used: None, step: None, ending: None, missed: 0)
end

# A run begun on its budget's deadline: it asks the model next.
fn begun(run: Progress, by: Deadline) : Progress
  var next = run
  next.by = Some(by)
  next.phase = Asking
  next
end

fn asked(run: Progress, reply: Result(Reply, ModelError), now: Time) : Progress
  var next = run
  next.phase = Recording
  next.reply = Some(reply)
  next.used = None
  next.began = Some(now)
  next.step = None
  next
end

fn using(run: Progress, tool: Used, now: Time) : Progress
  var next = run
  next.phase = Recording
  next.used = Some(tool)
  next.began = Some(now)
  next.step = None
  next
end

fn stopped(run: Progress) : Progress
  var next = run
  next.phase = Stopped
  next
end

# A run once the book holds its step: the step is shown to the model from now on, and a model call
# counts against steps and tokens.
fn advanced(run: Progress, step: Step) : Progress
  var next = run
  next.missed = 0
  next.step = None
  next.n = step.n
  next.steps = run.steps.push(step_json(step))
  if step.kind == "model"
    next.taken = run.taken + 1
    next.tokens = run.tokens + step.tokens
  end
  next
end

# Whether a run asks the model now: it is its turn, time is left, a model step fits the steps
# budget, and tokens are left.
fn asks?(run: Progress, setup: Setup, by: Deadline, counting: Counting) : Bool
  run.phase == Asking and !spent?(by) and fits?(run, setup, counting,
    "model") and run.tokens < setup.order.budget.tokens
end

# Whether a run uses the tool its model named now: it is its turn, time is left, a tool step fits
# the steps budget, and tokens have not passed theirs; a model call that spent exactly the budget
# still has its tool used.
fn uses?(run: Progress, setup: Setup, by: Deadline, counting: Counting) : Bool
  run.phase == Using and !spent?(by) and fits?(run, setup, counting,
    "tool") and run.tokens <= setup.order.budget.tokens
end

# Whether one more step of this kind fits the steps budget: under ModelCalls only a model step
# counts, and under RecordedSteps every step does.
fn fits?(run: Progress, setup: Setup, counting: Counting, kind: String) : Bool
  case counting
    ModelCalls: kind != "model" or run.taken < setup.order.budget.steps
    RecordedSteps: run.n < setup.order.budget.steps
  end
end

# Which budget a run that may not go on has spent: its time, its steps as the run counts them, or its
# tokens.
fn budget_end(run: Progress, setup: Setup, by: Deadline, counting: Counting) : Ending
  return ending(OverBudget, None, Some("wall_ms")) if spent?(by)
  counted = case counting
    ModelCalls: run.taken
    RecordedSteps: run.n
  end
  return ending(OverBudget, None, Some("steps")) if counted >= setup.order.budget.steps
  ending(OverBudget, None, Some("tokens"))
end

fn not_begun() : Ending
  ending(Failed, None, Some("the run was not begun"))
end

fn request_of(setup: Setup, run: Progress) : Request
  Request(run: setup.id, goal: setup.order.goal, tools: setup.order.tools, transcript: run.steps)
end

# The most any one call of the run may take.
fn call_ms(setup: Setup) : Duration
  setup.order.budget.tool_ms.to_i64.ms
end

fn ran_of(run: Progress, setup: Setup, by: Deadline) : Ran
  budget = setup.order.budget
  Ran(go: run.phase == Using, spent: spent?(by), taken: run.taken, steps: budget.steps,
    tokens_used: run.tokens, tokens: budget.tokens)
end

# The tool call the model's reply names, made only with the book's go and within the budget.
fn call_for(setup: Setup, run: Progress, ran: Ran) : Call
  requires ran.go
  requires !ran.spent
  requires ran.taken <= ran.steps
  requires ran.tokens_used <= ran.tokens

  case run.reply
    Some(Ok(UseTool(tool: tool, args: args, tokens: _))):
      Call(tool: tool, args: args, granted: setup.order.tools, hosts: setup.order.hosts)
    Some(Ok(Answer(text: _, tokens: _))) | Some(Error(_)) | None:
      Call(tool: "", args: Map.new(), granted: [], hosts: [])
  end
end

# The model call in hand as its step, or the step already built for it.
fn model_step(run: Progress, now: Time) : Step
  case run.step
    Some(step): step
    None:
      Step(n: run.n + 1, kind: "model", name: "model", args: Map.new(),
        output: reply_text(run.reply), tokens: reply_tokens(run.reply),
        took_ms: took(run.began, now), refused: false)
  end
end

# The tool call in hand as its step, or the step already built for it.
fn tool_step(run: Progress, now: Time) : Step
  case run.step
    Some(step): step
    None:
      tool = run.used or Used(output: "", refused: true, allowed: false)
      named = named_tool(run.reply)
      Step(n: run.n + 1, kind: "tool", name: named.0, args: named.1, output: tool.output, tokens: 0,
        took_ms: took(run.began, now), refused: tool.refused)
  end
end

fn named_tool(reply: Option(Result(Reply, ModelError))) : (String, Map(String, String))
  case reply
    Some(Ok(UseTool(tool: tool, args: args, tokens: _))): (tool, args)
    Some(Ok(Answer(text: _, tokens: _))) | Some(Error(_)) | None: ("", Map.new())
  end
end

# How a run ends once its model step is written, or None when it goes on to the tool: over budget
# once its tokens pass theirs, done with an answer, and failed on a model error, or over budget when
# that error is its wall budget running out.
fn model_outcome(run: Progress, setup: Setup) : Option(Ending)
  return Some(ending(OverBudget, None, Some("tokens"))) if run.tokens > setup.order.budget.tokens
  case run.reply
    Some(Ok(UseTool(tool: _, args: _, tokens: _))): None
    Some(Ok(Answer(text: text, tokens: _))): Some(ending(Done, Some(text), None))
    Some(Error(error)): Some(failed_end(run, error))
    None: Some(ending(Failed, None, Some("the model gave no reply")))
  end
end

fn failed_end(run: Progress, error: ModelError) : Ending
  return ending(OverBudget, None, Some("wall_ms")) if error == Late and wall_spent?(run)
  ending(Failed, None, Some(error_text(error)))
end

fn wall_spent?(run: Progress) : Bool
  case run.by
    Some(by): spent?(by)
    None: false
  end
end

fn error_text(error: ModelError) : String
  case error
    Unreachable: "the model did not answer at its address"
    Late: "the model did not answer in time"
    Status(code): "the model answered #{code}"
    NotJson: "the model's reply is not JSON"
    UnknownTool(name): "the model named a tool the harness does not have: #{name}"
    BadShape(why): "the model's reply is not one the harness reads: #{why}"
  end
end

# A reply as its model step shows it: the tool and arguments it names, its answer, or the error.
fn reply_text(reply: Option(Result(Reply, ModelError))) : String
  case reply
    Some(Ok(UseTool(tool: tool, args: args, tokens: _))):
      "{\"tool\": #{Json.encode(tool)}, \"args\": #{Json.encode(args)}}"
    Some(Ok(Answer(text: text, tokens: _))): "{\"done\": #{Json.encode(text)}}"
    Some(Error(error)): error_text(error)
    None: ""
  end
end

fn reply_tokens(reply: Option(Result(Reply, ModelError))) : UInt64
  case reply
    Some(Ok(answer)): tokens_of(answer)
    Some(Error(_)) | None: 0
  end
end

fn took(began: Option(Time), now: Time) : UInt64
  case began
    Some(at):
      ms = (now - at).ms
      return 0 if ms < 0
      ms.to_u64
    None: 0
  end
end

fn setup_with(tokens: UInt64) : Setup
  order = Order(goal: "g", folder: "work", tools: ["read_file"], hosts: ["h"],
    budget: Budget(steps: 2, tokens: tokens, wall_ms: 60_000, retries: 2, tool_ms: 5_000))
  Setup(id: "r_1", order: order, model: Model(host: "localhost", port: 1, tools: ["read_file"]))
end

fn read_reply() : Result(Reply, ModelError)
  Ok(UseTool(tool: "read_file", args: Map.new().set("path", "a.txt"), tokens: 7))
end

test "a model step shows the reply, and a tool step the tool's outcome, numbered on from the last"
  at = Time.fixture()
  run = asked(fresh("r_1"), read_reply(), at)
  step = model_step(run, at + 12.ms)
  assert step.n == 1 and step.kind == "model" and step.tokens == 7 and step.took_ms == 12
  assert step.output == "{\"tool\": \"read_file\", \"args\": {\"path\": \"a.txt\"}}"
  assert model_step(advanced(run, step), at) == Step(n: 2, kind: "model", name: "model",
    args: Map.new(), output: "{\"tool\": \"read_file\", \"args\": {\"path\": \"a.txt\"}}",
    tokens: 7, took_ms: 0, refused: false)
  after = advanced(run, step)
  assert after.taken == 1 and after.tokens == 7 and after.n == 1 and after.steps == [step_json(step)]
  tool = using(after, Used(output: "hi", refused: false, allowed: true), at)
  used_step = tool_step(tool, at + 3.ms)
  assert used_step.name == "read_file" and used_step.n == 2 and used_step.output == "hi" and used_step.took_ms == 3
  assert advanced(tool, used_step).taken == 1
  assert reply_text(Some(Ok(Answer(text: "42", tokens: 1)))) == "{\"done\": \"42\"}"
  assert reply_text(Some(Error(NotJson))) == "the model's reply is not JSON"
  assert took(None, at) == 0 and took(Some(at + 5.ms), at) == 0
end

test "a run ends done on an answer, failed on a model error, and over budget past its tokens"
  at = Time.fixture()
  setup = setup_with(10)
  assert model_outcome(asked(fresh("r_1"), read_reply(), at), setup) is None
  assert model_outcome(asked(fresh("r_1"), Ok(Answer(text: "x", tokens: 1)), at),
    setup) == Some(ending(Done, Some("x"), None))
  assert model_outcome(asked(fresh("r_1"), Error(NotJson), at),
    setup) == Some(ending(Failed, None, Some("the model's reply is not JSON")))
  var over = asked(fresh("r_1"), read_reply(), at)
  over.tokens = 11
  assert model_outcome(over, setup) == Some(ending(OverBudget, None, Some("tokens")))
  late = asked(begun(fresh("r_1"), Deadline.fixture(0.ms)), Error(Late), at)
  assert model_outcome(late, setup) == Some(ending(OverBudget, None, Some("wall_ms")))
  in_time = asked(begun(fresh("r_1"), Deadline.fixture(1.minute)), Error(Late), at)
  assert model_outcome(in_time,
    setup) == Some(ending(Failed, None, Some("the model did not answer in time")))
end

test "a run asks and uses a tool only in its turn, with time, steps, and tokens left"
  setup = setup_with(10)
  by = Deadline.fixture(1.minute)
  ready = begun(fresh("r_1"), by)
  assert asks?(ready, setup, by, ModelCalls) and !uses?(ready, setup, by, ModelCalls)
  assert !asks?(ready, setup, Deadline.fixture(0.ms), ModelCalls)
  assert budget_end(ready, setup, Deadline.fixture(0.ms), ModelCalls) == ending(OverBudget, None,
    Some("wall_ms"))
  var spent_steps = ready
  spent_steps.taken = 2
  assert !asks?(spent_steps, setup, by, ModelCalls)
  assert budget_end(spent_steps, setup, by, ModelCalls) == ending(OverBudget, None, Some("steps"))
  var spent_tokens = ready
  spent_tokens.tokens = 10
  assert !asks?(spent_tokens, setup, by, ModelCalls)
  assert budget_end(spent_tokens, setup, by, ModelCalls) == ending(OverBudget, None, Some("tokens"))
  var tool_turn = asked(ready, read_reply(), Time.fixture())
  tool_turn.phase = Using
  assert uses?(tool_turn, setup, by, ModelCalls) and !asks?(tool_turn, setup, by, ModelCalls)
  assert call_for(setup, tool_turn, ran_of(tool_turn, setup, by)) == Call(tool: "read_file",
    args: Map.new().set("path", "a.txt"), granted: ["read_file"], hosts: ["h"])
  assert request_of(setup, ready) == Request(run: "r_1", goal: "g", tools: ["read_file"],
    transcript: [])
  assert call_ms(setup) == 5_000.ms
end

test "a steps budget counts model calls or every recorded step, and a tool is used at exactly the token budget"
  setup = setup_with(10)
  by = Deadline.fixture(1.minute)
  var after_tool = begun(fresh("r_1"), by)
  after_tool.taken = 1
  after_tool.n = 2
  assert asks?(after_tool, setup, by, ModelCalls) and !asks?(after_tool, setup, by, RecordedSteps)
  assert budget_end(after_tool, setup, by, RecordedSteps) == ending(OverBudget, None, Some("steps"))
  var named = asked(begun(fresh("r_1"), by), read_reply(), Time.fixture())
  named.phase = Using
  named.taken = 1
  named.n = 1
  assert uses?(named, setup, by, ModelCalls) and uses?(named, setup, by, RecordedSteps)
  named.n = 2
  assert uses?(named, setup, by, ModelCalls) and !uses?(named, setup, by, RecordedSteps)
  named.n = 1
  named.tokens = 10
  assert uses?(named, setup, by, ModelCalls) and uses?(named, setup, by, RecordedSteps)
  named.tokens = 11
  assert !uses?(named, setup, by, ModelCalls) and !uses?(named, setup, by, RecordedSteps)
  var at_bound = begun(fresh("r_1"), by)
  at_bound.tokens = 10
  assert !asks?(at_bound, setup, by, ModelCalls) and !asks?(at_bound, setup, by, RecordedSteps)
  assert budget_end(at_bound, setup, by, ModelCalls) == ending(OverBudget, None, Some("tokens"))
  assert budget_end(at_bound, setup, by, RecordedSteps) == ending(OverBudget, None, Some("tokens"))
end

test rejects "a tool call without the book's go"
  setup = setup_with(10)
  call_for(setup, fresh("r_1"),
    Ran(go: false, spent: false, taken: 0, steps: 2, tokens_used: 0, tokens: 10))
end

test rejects "a tool call once the wall budget is spent"
  setup = setup_with(10)
  call_for(setup, fresh("r_1"),
    Ran(go: true, spent: true, taken: 0, steps: 2, tokens_used: 0, tokens: 10))
end

test rejects "a tool call past the steps budget"
  setup = setup_with(10)
  call_for(setup, fresh("r_1"),
    Ran(go: true, spent: false, taken: 3, steps: 2, tokens_used: 0, tokens: 10))
end

test rejects "a tool call past the tokens budget"
  setup = setup_with(10)
  call_for(setup, fresh("r_1"),
    Ran(go: true, spent: false, taken: 0, steps: 2, tokens_used: 11, tokens: 10))
end

verified: types, contracts, tests (8), property (0 seeds), sim (not run)
          proven: not run
