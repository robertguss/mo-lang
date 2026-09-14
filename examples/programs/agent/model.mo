# recipe: Recipes.ModelClient.ModelClient
module Agent.Model
expose Model, Request, Reply, ModelError, Attempts, Taken, Fake, Fakes, body, parsed, complete, spent?, tokens_of

use Agent.Wire{posted}

intent "The model client recipe (examples/recipes/model-client.mo) implemented for agent over Http: the request as JSON posted to /complete, the reply read into a tool to use or an answer, every attempt on the caller's deadline, retried at once on a model error while attempts and the deadline last, and a reply read after the deadline refused as Late."

never "a call is made more than retries + 1 times"
  for a in Attempts.all
    a.made > a.allowed
  end
end

never "a reply is used after its call's deadline"
  for t in Taken.all
    t.late
  end
end

# Where the model answers, and the tools a reply may name: every tool its harness can run, granted
# to the run or not.
struct Model
  host: String
  port: UInt16
  tools: List(String)
end

# What the model is asked: the run it is for (sent as the x-run header, not in the body), the
# goal, the tools the run granted, and the steps so far, each the JSON object the transcript
# holds.
struct Request
  run: String
  goal: String
  tools: List(String)
  transcript: List(String)
end

# What the model said to do next: use a tool with string arguments, or stop with an answer; each
# with the tokens it spent.
enum Reply
  UseTool(tool: String, args: Map(String, String), tokens: UInt64)
  Answer(text: String, tokens: UInt64)
end

# Every way a call fails. Unreachable: nothing answered at the model's address. Late: the deadline
# passed before a reply that could be used. Status: an answer that is not 200. The rest are
# replies that cannot be acted on.
enum ModelError
  Unreachable
  Late
  Status(code: UInt16)
  NotJson
  UnknownTool(name: String)
  BadShape(why: String)
end

# One attempt of a call: its number, from 1, beside the most the call may make.
struct Attempts
  made: UInt64
  allowed: UInt64
end

# A reply a call gave back, and whether its deadline had passed when it did.
struct Taken
  late: Bool
end

# A model for the recipe's tests: it answers each request with the next reply in its list, and
# after the list with an answer that says so; every read of `slow` it makes first moves the clock
# by that Fs's delay.
process Fake(replies: List(String), slow: Fs)
  state
    served: UInt64
    delayed: Bool
    answered: Bool
  end

  message Accepted(exchange: Exchange)
  message Idle
  message Served : UInt64

  fn update(state, message)
    case message
      Accepted(exchange):
        state.delayed = slow.size("late", within: 1.minute) is Ok(_)
        text = replies.get(state.served) or "{\"done\": \"no more replies\", \"tokens\": 0}"
        state.served += 1
        state.answered = exchange.reply(Response(status: 200, body: text),
          within: 1.minute) is Ok(_)
      Idle:
        state.answered = false
      Served: state.served
    end
  end
end

supervisor Fakes(replies: List(String), slow: Fs)
  child Fake(replies, slow), restart: :always
end

# The JSON a call posts: the goal, the granted tools, and the transcript's steps as they are.
fn body(request: Request) : String
  goal = Json.encode(request.goal)
  tools = Json.encode(request.tools)
  "{\"goal\": #{goal}, \"tools\": #{tools}, \"transcript\": [#{String.join(request.transcript, ", ")}]}"
end

fn parsed(model: Model, text: String) : Result(Reply, ModelError)
  case Json.decode(text)
    Ok(Object(fields)): replied(model, fields)
    Ok(_): Error(BadShape(why: "a reply is a JSON object"))
    Error(_): Error(NotJson)
  end
end

fn complete(http: Http, model: Model, request: Request, retries: UInt32,
  by: Deadline) : Result(Reply, ModelError)
  requires retries <= 10

  return Error(Late) if spent?(by)
  tried(http, model, request, Attempts(made: 1, allowed: retries.to_u64 + 1), by)
end

# Whether a deadline has nothing left: tightening it to now gives it back unchanged only once it
# has passed.
fn spent?(by: Deadline) : Bool
  by.at_most(0.ms) == by
end

fn tokens_of(reply: Reply) : UInt64
  case reply
    UseTool(tool: _, args: _, tokens: tokens) | Answer(text: _, tokens: tokens): tokens
  end
end

# The attempt `attempts` counts, then the next after a model error, while attempts are left and
# the deadline has time; the last attempt's outcome.
fn tried(http: Http, model: Model, request: Request, attempts: Attempts,
  by: Deadline) : Result(Reply, ModelError)
  outcome = once(http, model, request, by)
  return outcome if outcome is Ok(_) or attempts.made >= attempts.allowed or spent?(by)
  tried(http, model, request, Attempts(made: attempts.made + 1, allowed: attempts.allowed), by)
end

fn once(http: Http, model: Model, request: Request, by: Deadline) : Result(Reply, ModelError)
  case http.send(posted(request.run, body(request)), host: model.host, port: model.port, within: by)
    Ok(response):
      return Error(Status(code: response.status)) if response.status != 200
      reply = try parsed(model, response.body)
      kept(reply, spent?(by))
    Error(Timeout): Error(Late)
    Error(Refused) | Error(Closed) | Error(Busy) | Error(Malformed) | Error(TooLarge) | Error(Unsupported):
      Error(Unreachable)
  end
end

# A reply read in time is used; one read after the deadline is Late, and no Taken records it.
fn kept(reply: Reply, late: Bool) : Result(Reply, ModelError)
  return Error(Late) if late
  Ok(handed(reply, Taken(late: late)))
end

# A reply handed back to the caller, beside the record of it the never reads.
fn handed(reply: Reply, taken: Taken) : Reply
  ensures !taken.late

  reply
end

fn replied(model: Model, fields: Map(String, Json)) : Result(Reply, ModelError)
  tokens = try tokens_in(fields)
  if fields.has?("tool") and fields.has?("done")
    return Error(BadShape(why: "a reply names a tool or is done, not both"))
  end
  return answered(fields, tokens) if fields.has?("done")
  used(model, fields, tokens)
end

fn tokens_in(fields: Map(String, Json)) : Result(UInt64, ModelError)
  wrong = BadShape(why: "tokens is a whole number from 0")
  case fields.get("tokens")
    Some(value):
      whole = value.to_i64 or -1
      return Error(wrong) if whole < 0
      Ok(whole.to_u64)
    None: Error(BadShape(why: "a reply says the tokens it spent"))
  end
end

fn answered(fields: Map(String, Json), tokens: UInt64) : Result(Reply, ModelError)
  case fields.get("done")
    Some(String(text)): Ok(Answer(text: text, tokens: tokens))
    Some(_): Error(BadShape(why: "done is a string"))
    None: Error(BadShape(why: "a reply names a tool or is done"))
  end
end

fn used(model: Model, fields: Map(String, Json), tokens: UInt64) : Result(Reply, ModelError)
  case fields.get("tool")
    Some(String(name)):
      return Error(UnknownTool(name: name)) if !model.tools.contains?(name)
      args = try args_in(fields)
      Ok(UseTool(tool: name, args: args, tokens: tokens))
    Some(_): Error(BadShape(why: "tool is a string"))
    None: Error(BadShape(why: "a reply names a tool or is done"))
  end
end

# A tool's arguments: an object of strings, or none at all.
fn args_in(fields: Map(String, Json)) : Result(Map(String, String), ModelError)
  case fields.get("args")
    Some(Object(args)): strings(args)
    Some(_): Error(BadShape(why: "args is an object"))
    None: Ok(Map.new())
  end
end

fn strings(args: Map(String, Json)) : Result(Map(String, String), ModelError)
  texts = args.values.flat_map(fn(value) text_of(value) end)
  return Error(BadShape(why: "every argument is a string")) if texts.size != args.size
  Ok(args.keys.zip(texts).reduce(Map.new(), fn(map, pair) map.set(pair.0, pair.1) end))
end

fn text_of(value: Json) : List(String)
  case value
    String(text): [text]
    Object(_) | Array(_) | Number(_) | Bool(_) | Null: []
  end
end

test "a reply's tokens come out of either kind"
  assert tokens_of(UseTool(tool: "now", args: Map.new(), tokens: 4)) == 4
  assert tokens_of(Answer(text: "x", tokens: 9)) == 9
end

test "a deadline with time left is not spent, and one with none is"
  assert !spent?(Deadline.fixture(1.minute))
  assert spent?(Deadline.fixture(0.ms))
end

test rejects "a call retried more than ten times"
  model = Model(host: "localhost", port: 1, tools: ["now"])
  asked = Request(run: "r_1", goal: "g", tools: ["now"], transcript: [])
  assert complete(Http.fixture(), model, asked, 11, Deadline.fixture(1.minute)) is Error(_)
end

verified: types, contracts, tests (3), property (0 seeds), sim (not run)
          proven: not run
