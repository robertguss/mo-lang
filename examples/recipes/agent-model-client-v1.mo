module Recipes.AgentModelClientV1
expose Model, Request, Reply, ModelError, Attempts, Taken, Fake, Fakes, StatusFake, StatusFakes, ModelClient

intent "Publish Agent model client policy v1: HTTP 401 is terminal without login or credential refresh; otherwise a retrying client for an agent's model, any plain-HTTP server that answers POST /complete, as intent, signatures, and tests, for an agent to implement over Http on its caller's deadline."

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

# A model for the tests: it answers each request with the next reply in its list, and after the
# list with an answer that says so; every read of `slow` it makes first moves the clock by that
# Fs's delay.
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

# Actual HTTP response statuses, separate from reply JSON, with a received-request counter.
process StatusFake(replies: List(Response))
  state
    served: UInt64
    answered: Bool
  end
  message Accepted(exchange: Exchange)
  message Idle
  message Served : UInt64
  fn update(state, message)
    case message
      Accepted(exchange):
        response = replies.get(state.served) or Response(status: 200,
          body: "{\"done\": \"unexpected request\", \"tokens\": 0}")
        state.served += 1
        state.answered = exchange.reply(response, within: 1.minute) is Ok(_)
      Idle:
        state.answered = false
      Served: state.served
    end
  end
end

supervisor StatusFakes(replies: List(Response))
  child StatusFake(replies), restart: :always
end

recipe ModelClient
  intent "A call to an agent's model over plain HTTP: POST /complete with the goal, the granted tools, and the transcript as JSON, read back as a tool to use with string arguments or an answer, each with its tokens; a reply that is not JSON, names a tool the model's harness does not have, or has fields of the wrong shape is a model error, and so is no answer or a status other than 200; HTTP 401 returns Error(Status(code: 401)) immediately with no further request or login or credential refresh; every other model error is retried at once up to retries more times, every attempt on the caller's deadline, and a reply that comes after it is Late and never used"
  needs Http
  fn body(request: Request) : String
  end
  fn parsed(model: Model, text: String) : Result(Reply, ModelError)
  end
  fn complete(http: Http, model: Model, request: Request, retries: UInt32,
    by: Deadline) : Result(Reply, ModelError)
    requires retries <= 10
  end
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
  test "the body is the goal, the granted tools, and the steps so far"
    asked = Request(run: "r_1", goal: "count \"a\"", tools: ["now", "read_file"],
      transcript: ["{\"n\": 1}", "{\"n\": 2}"])
    assert body(asked) == "{\"goal\": \"count \\\"a\\\"\", \"tools\": [\"now\", \"read_file\"], \"transcript\": [{\"n\": 1}, {\"n\": 2}]}"
    assert body(Request(run: "r_2", goal: "", tools: [],
      transcript: [])) == "{\"goal\": \"\", \"tools\": [], \"transcript\": []}"
  end
  test "a reply names a tool with string arguments, or answers, with its tokens"
    model = Model(host: "localhost", port: 7_951, tools: ["now", "read_file"])
    args = Map.new().set("path", "notes/a.txt")
    tool = "{\"tool\": \"read_file\", \"args\": {\"path\": \"notes/a.txt\"}, \"tokens\": 12}"
    assert parsed(model, tool) == Ok(UseTool(tool: "read_file", args: args, tokens: 12))
    assert parsed(model,
      "{\"tool\": \"now\", \"tokens\": 0}") == Ok(UseTool(tool: "now", args: Map.new(), tokens: 0))
    assert parsed(model, "{\"done\": \"42\", \"tokens\": 3}") == Ok(Answer(text: "42", tokens: 3))
  end
  test "a reply that is not JSON, names a tool the harness lacks, or has a field of the wrong shape is a model error"
    model = Model(host: "localhost", port: 7_951, tools: ["now", "read_file"])
    assert parsed(model, "the file says 42") == Error(NotJson)
    assert parsed(model,
      "{\"tool\": \"rm\", \"args\": {}, \"tokens\": 1}") == Error(UnknownTool(name: "rm"))
    assert parsed(model, "[1, 2]") is Error(BadShape(_))
    assert parsed(model,
      "{\"tool\": \"read_file\", \"args\": {\"path\": 7}, \"tokens\": 1}") is Error(BadShape(_))
    assert parsed(model,
      "{\"tool\": \"read_file\", \"args\": [\"a\"], \"tokens\": 1}") is Error(BadShape(_))
    assert parsed(model, "{\"done\": \"42\"}") is Error(BadShape(_))
    assert parsed(model, "{\"done\": \"42\", \"tokens\": 1.5}") is Error(BadShape(_))
    assert parsed(model, "{\"done\": \"42\", \"tokens\": -1}") is Error(BadShape(_))
    assert parsed(model, "{\"done\": 42, \"tokens\": 1}") is Error(BadShape(_))
    assert parsed(model,
      "{\"done\": \"42\", \"tool\": \"now\", \"tokens\": 1}") is Error(BadShape(_))
    assert parsed(model, "{\"tokens\": 1}") is Error(BadShape(_))
  end
  test "a model that is garbage twice and then right is answered under two retries"
    http = Http.fixture()
    assert http.listen(0, within: 1.minute) is Ok(listener)
    fake = Fake.start(["garbage", "{\"done\": 7}", "{\"done\": \"7\", \"tokens\": 5}"],
      Fs.fixture())
    listener.serve(into: fake, idle: 5_000.ms)
    model = Model(host: "localhost", port: listener.port, tools: ["now"])
    asked = Request(run: "r_1", goal: "g", tools: ["now"], transcript: [])
    assert complete(http, model, asked, 2,
      Deadline.fixture(1.minute)) == Ok(Answer(text: "7", tokens: 5))
    assert fake.ask(Served, within: 1.minute) == Ok(3)
  end
  test "a model that is garbage three times fails under two retries, after three calls"
    http = Http.fixture()
    assert http.listen(0, within: 1.minute) is Ok(listener)
    fake = Fake.start(["garbage", "garbage", "garbage", "{\"done\": \"7\", \"tokens\": 5}"],
      Fs.fixture())
    listener.serve(into: fake, idle: 5_000.ms)
    model = Model(host: "localhost", port: listener.port, tools: ["now"])
    asked = Request(run: "r_1", goal: "g", tools: ["now"], transcript: [])
    assert complete(http, model, asked, 2, Deadline.fixture(1.minute)) == Error(NotJson)
    assert fake.ask(Served, within: 1.minute) == Ok(3)
  end
  test "a deadline with nothing left makes no call"
    http = Http.fixture()
    assert http.listen(0, within: 1.minute) is Ok(listener)
    fake = Fake.start(["{\"done\": \"7\", \"tokens\": 5}"], Fs.fixture())
    listener.serve(into: fake, idle: 5_000.ms)
    model = Model(host: "localhost", port: listener.port, tools: ["now"])
    asked = Request(run: "r_1", goal: "g", tools: ["now"], transcript: [])
    assert complete(http, model, asked, 10, Deadline.fixture(0.ms)) == Error(Late)
    assert fake.ask(Served, within: 1.minute) == Ok(0)
  end
  test "a reply that comes after the deadline is Late, and no call follows it"
    http = Http.fixture()
    assert http.listen(0, within: 1.minute) is Ok(listener)
    fake = Fake.start(["{\"done\": \"7\", \"tokens\": 5}", "{\"done\": \"8\", \"tokens\": 5}"],
      Fs.fixture(delay: 1.minute))
    listener.serve(into: fake, idle: 5_000.ms)
    model = Model(host: "localhost", port: listener.port, tools: ["now"])
    asked = Request(run: "r_1", goal: "g", tools: ["now"], transcript: [])
    assert complete(http, model, asked, 2, Deadline.fixture(100.ms)) == Error(Late)
    assert fake.ask(Served, within: 1.minute) == Ok(1)
  end
  test "a model with nothing listening is Unreachable"
    model = Model(host: "localhost", port: 1, tools: ["now"])
    asked = Request(run: "r_1", goal: "g", tools: ["now"], transcript: [])
    assert complete(Http.fixture(), model, asked, 0,
      Deadline.fixture(1.minute)) == Error(Unreachable)
  end
  test rejects "a call retried more than ten times"
    model = Model(host: "localhost", port: 1, tools: ["now"])
    asked = Request(run: "r_1", goal: "g", tools: ["now"], transcript: [])
    assert complete(Http.fixture(), model, asked, 11, Deadline.fixture(1.minute)) is Error(_)
  end
  test "401 is terminal before a valid reply"
    http = Http.fixture()
    assert http.listen(0, within: 1.minute) is Ok(listener)
    fake = StatusFake.start([Response(status: 401, body: "garbage"), Response(status: 200, body: "{\"done\": \"7\", \"tokens\": 5}")])
    listener.serve(into: fake, idle: 5_000.ms)
    model = Model(host: "localhost", port: listener.port, tools: ["now"])
    asked = Request(run: "r_1", goal: "g", tools: ["now"], transcript: [])
    assert complete(http, model, asked, 2, Deadline.fixture(1.minute)) == Error(Status(code: 401))
    assert fake.ask(Served, within: 1.minute) == Ok(1)
  end
  test "503 then 401 is terminal"
    http = Http.fixture()
    assert http.listen(0, within: 1.minute) is Ok(listener)
    fake = StatusFake.start([Response(status: 503, body: "garbage"), Response(status: 401, body: "garbage"), Response(status: 200, body: "{\"done\": \"7\", \"tokens\": 5}")])
    listener.serve(into: fake, idle: 5_000.ms)
    model = Model(host: "localhost", port: listener.port, tools: ["now"])
    asked = Request(run: "r_1", goal: "g", tools: ["now"], transcript: [])
    assert complete(http, model, asked, 2, Deadline.fixture(1.minute)) == Error(Status(code: 401))
    assert fake.ask(Served, within: 1.minute) == Ok(2)
  end
  test "malformed 200 then 401 is terminal"
    http = Http.fixture()
    assert http.listen(0, within: 1.minute) is Ok(listener)
    fake = StatusFake.start([Response(status: 200, body: "garbage"), Response(status: 401, body: "garbage"), Response(status: 200, body: "{\"done\": \"7\", \"tokens\": 5}")])
    listener.serve(into: fake, idle: 5_000.ms)
    model = Model(host: "localhost", port: listener.port, tools: ["now"])
    asked = Request(run: "r_1", goal: "g", tools: ["now"], transcript: [])
    assert complete(http, model, asked, 2, Deadline.fixture(1.minute)) == Error(Status(code: 401))
    assert fake.ask(Served, within: 1.minute) == Ok(2)
  end
  test "503 still retries to success"
    http = Http.fixture()
    assert http.listen(0, within: 1.minute) is Ok(listener)
    fake = StatusFake.start([Response(status: 503, body: "garbage"), Response(status: 200, body: "{\"done\": \"7\", \"tokens\": 5}")])
    listener.serve(into: fake, idle: 5_000.ms)
    model = Model(host: "localhost", port: listener.port, tools: ["now"])
    asked = Request(run: "r_1", goal: "g", tools: ["now"], transcript: [])
    assert complete(http, model, asked, 2, Deadline.fixture(1.minute)) == Ok(Answer(text: "7", tokens: 5))
    assert fake.ask(Served, within: 1.minute) == Ok(2)
  end
  test "three 503 responses exhaust two retries"
    http = Http.fixture()
    assert http.listen(0, within: 1.minute) is Ok(listener)
    fake = StatusFake.start([Response(status: 503, body: "garbage"), Response(status: 503, body: "garbage"), Response(status: 503, body: "garbage"), Response(status: 200, body: "{\"done\": \"7\", \"tokens\": 5}")])
    listener.serve(into: fake, idle: 5_000.ms)
    model = Model(host: "localhost", port: listener.port, tools: ["now"])
    asked = Request(run: "r_1", goal: "g", tools: ["now"], transcript: [])
    assert complete(http, model, asked, 2, Deadline.fixture(1.minute)) == Error(Status(code: 503))
    assert fake.ask(Served, within: 1.minute) == Ok(3)
  end
  test "a valid reply needs one request"
    http = Http.fixture()
    assert http.listen(0, within: 1.minute) is Ok(listener)
    fake = StatusFake.start([Response(status: 200, body: "{\"done\": \"7\", \"tokens\": 5}")])
    listener.serve(into: fake, idle: 5_000.ms)
    model = Model(host: "localhost", port: listener.port, tools: ["now"])
    asked = Request(run: "r_1", goal: "g", tools: ["now"], transcript: [])
    assert complete(http, model, asked, 2, Deadline.fixture(1.minute)) == Ok(Answer(text: "7", tokens: 5))
    assert fake.ask(Served, within: 1.minute) == Ok(1)
  end
  test "401 with no retries makes one request"
    http = Http.fixture()
    assert http.listen(0, within: 1.minute) is Ok(listener)
    fake = StatusFake.start([Response(status: 401, body: "garbage"), Response(status: 200, body: "{\"done\": \"7\", \"tokens\": 5}")])
    listener.serve(into: fake, idle: 5_000.ms)
    model = Model(host: "localhost", port: listener.port, tools: ["now"])
    asked = Request(run: "r_1", goal: "g", tools: ["now"], transcript: [])
    assert complete(http, model, asked, 0, Deadline.fixture(1.minute)) == Error(Status(code: 401))
    assert fake.ask(Served, within: 1.minute) == Ok(1)
  end
end

verified: types, contracts, tests (1), property (0 seeds), sim (not run)
          proven: not run
