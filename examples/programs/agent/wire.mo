module Agent.Wire
expose posted

intent "The HTTP request a model call sends, built in a module of its own: Agent.Model declares the recipe's Request, which hides the prelude's Request from that module's code, so the prelude's is built here."

# A model call: the body posted to /complete as JSON, with the run it is for in x-run, which
# the scripted model plays its script by.
fn posted(run: String, body: String) : Request
  headers = Map.new().set("content-type", "application/json").set("x-run", run)
  Request(method: "POST", path: "/complete", headers: headers, body: body)
end

test "a model call posts its body to /complete with its run in x-run"
  sent = posted("r_7", "{}")
  assert sent.method == "POST" and sent.path == "/complete" and sent.body == "{}"
  assert sent.headers.get("x-run") == Some("r_7")
end

verified: types, contracts, tests (1), property (0 seeds), sim (not run)
          proven: not run
