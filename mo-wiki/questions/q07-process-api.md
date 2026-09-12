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

## Session 3 note (tension 5: `send` never blocks vs bounded everything)

Robert (session 3): "I want you to decide 3 through 7 because we need an answer and then we need to test everything, so your decisions are as good as mine." So this is Claude's call, provisional, and marked with what tests it. **Decision:** every mailbox is bounded. The bound is declared in the process header (`process RefundQueue(db: Ledger) mailbox: 10_000`) with a default from the law numbers ([[q12-law-numbers|Q12]]). `send` still never blocks and has no `try`. A full mailbox is a broken roof: the *sender* crashes, because overflow means the design has no flow control, and the fix is `ask` (which has a deadline and gives backpressure) or a bigger declared bound. The supervisor restarts, the agent gets the crash as a task ([[d21-autonomous-crash-fixing|direction 21]]). → [[d33-bounded-mailboxes|direction 33]]. **First tested by:** `Mo.Sim` under load with a slow consumer.

## Related
- [[p10-process]]
- [[d14-processes-are-the-only-identity]]
- [[d17-mandatory-deadlines]]
- [[full-example-q1-q7]]
