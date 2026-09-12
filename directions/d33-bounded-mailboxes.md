---
title: "Direction 33: Bounded mailboxes; `send` never blocks; overflow is a roof"
created: 2026-09-12
updated: 2026-09-12
type: direction
tags: [processes, laws]
sources: [research/comparisons/go.md, research/comparisons/elixir.md]
number: 33
status: liked
origin: "Claude's decision at Robert's request (session 3)"
confidence: low
---

# Direction 33: Bounded mailboxes; `send` never blocks; overflow is a roof

Resolves tension 5 of the [[comparison-synthesis-draft]]: "`send` never blocks or fails" ([[q07-process-api|Q7]]) against bounded everything ([[d04-style-rules-become-laws|direction 4]]).

- Every mailbox has a bound. It is declared in the process header, with a default from the law numbers ([[q12-law-numbers|Q12]]).
- `send` never blocks and has no `try`. The source stays as it was.
- A full mailbox is a broken roof ([[d18-two-kinds-of-failure|direction 18]]): the sender crashes. Overflow means the design has no flow control. The fixes are `ask` (deadline, backpressure) or a larger declared bound, and the agent gets the crash as a task ([[d21-autonomous-crash-fixing|direction 21]]).

```ruby
process RefundQueue(db: Ledger, clock: Clock) mailbox: 10_000
  ...
end

queue.send(Enqueue(request: r))      # never blocks; crashes the sender if the mailbox is full
```

Why the sender and not the receiver: crashing the receiver loses the messages it already holds; crashing the sender loses one message and points at the code that lacks flow control. TigerBeetle's fixed-size-everything makes the same call: hitting a limit is an assertion, not a wait.

First tested by: `Mo.Sim` under load with a slow consumer. Reopen if real programs need `send` to return rain instead.

## Related
- [[q07-process-api]]
- [[d04-style-rules-become-laws]]
- [[d17-mandatory-deadlines]]
- [[go]]
