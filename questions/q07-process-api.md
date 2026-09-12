---
title: "Q7: Process API syntax: spawn, send, receive, supervise"
created: 2026-09-12
updated: 2026-09-12
type: question
tags: [processes, syntax]
sources: [raw/notion/open-questions-2026-09-12.md]
number: 7
status: answered
answer: in
asked: 2026-09-12
---

# Q7: Process API syntax: spawn, send, receive, supervise

**Recommendation:**
```ruby
queue = RefundQueue.start(db, clock, events)     # returns a typed handle
queue.send(Enqueue(request: r))                  # fire and forget
reply = try queue.ask(Status, within: 50.ms)     # request/response

supervisor Payments
  child RefundQueue, restart: :always, max_restarts: 5 per 1.minute
  child Reconciler,  restart: :on_crash
end
```
`send` never blocks. `ask` blocks with a mandatory deadline. A handle is typed by the process, so sending the wrong message is a compile error. Supervisors are declared, not coded.
**Why:** This is OTP's proven shape with the dynamic typing removed. Declared supervisors mean an agent cannot forget to supervise; a process not under a supervisor does not compile.
✅ **Robert: IN** (session 2). Details settled: `Name.start(caps...)` returns a `Handle(Name)`, so a wrong message is a compile error. Reply types declared on the message line (`message Status : QueueStatus`) so `ask` is typed. `send` never blocks or fails; `ask` requires `within:` and returns Result with Timeout as rain. Supervisor vocabulary: `:always`, `:on_crash`, `:never`, `max_restarts: N per Duration`; `main` is the root supervisor. No links, monitors, `Process.exit`, or `receive` in user code — `update` is the only message handler. Later stdlib sugar, not a primitive: `Task.run(fn ... end, within:)` for one-shot helpers.

## Related
- [[p10-process]]
- [[d14-processes-are-the-only-identity]]
- [[d17-mandatory-deadlines]]
- [[full-example-q1-q7]]
