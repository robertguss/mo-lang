# 10. The language after the rounds

**Status:** draft, 15 Sep 2026, written by Fable at the pause after rounds 8 and
10 and measurements 1 and 2, for Robert. Each section is one candidate change,
the round row that motivates it, what it costs, code options, and Fable's
recommendation as a decision-log row. Zero new syntax stays the default: nothing
here adds a keyword. No change without a row behind it. Chapter 1 asked for this
page; the roadmap named it `09-`, but chapter 9 was the stdlib by then, so it is
chapter 10. Amended 16 Sep after P6 on Mo's change 2 program (§2, the table,
the reading). Amended 17 Sep: the 3-in-5 budget is Elixir `Supervisor`'s default,
not OTP's; Erlang's `supervisor` defaults to 1 in 5 s (Hermes, PR 2,
`hermes-daily-2026-09-16`, from the versioned docs and the round-10 source).

## What the rounds said, in one table

| row                                                 | round                        | what happened                                                                                                                                                                                                                | where it points |
| --------------------------------------------------- | ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------- |
| a wait hidden as a message pattern                  | 8, the outage; 10, P6        | the queue crashed on a replayed record and the service never answered again: the worker sent `Want` and waited for `Done`, a wait the deadline law cannot see; Elixir's supervisor restored the same service in under 600 ms | §1, §2          |
| a store that never restarts                         | P6 on Mo, 16 Sep             | the change 2 queue crashed by an input through the surface under load: `503` within 2 ms from then, nothing lost, no restart, because `opening` is computed in `main` and the line says `:never`; a restarted process re-runs its state initializers with its capabilities, so it could have reopened | §2, change 3    |
| the restart budget by default                       | 10, P6                       | four kills in 2 s and the Elixir node exits on Elixir `Supervisor`'s default of 3 restarts in 5 s (Erlang's own `supervisor` defaults to 1 in 5 s), which the program never wrote; Mo's budget is on the `child` line                                                                         | §2              |
| the six-parameter law                               | 8; measurement 1             | MO0303 cost the maintainer a loop and a `Making` struct, caught nothing                                                                                                                                                      | §3              |
| a `never` keyed on `(number, tries)`                | 8                            | a retry reset `tries` and the `never` tripped twice as a false positive: two loops, no bug                                                                                                                                   | §4              |
| MO0317 on a changed module's dependents             | measurement 2, round 8       | every regeneration and the maintainer lost a loop to it; first fix right 6 of 7                                                                                                                                              | §5, toolchain   |
| MO0403, `Time.fixture()` outside a test             | measurement 1                | four of ten regenerations, the same fix every time                                                                                                                                                                           | §5, no change   |
| a `never` at rest on the log                        | 10                           | the class of Elixir's torn-line defect; round 7's `store.mo` states it, Elixir has nowhere to                                                                                                                                | §4, keep        |
| the grammar forms that cost a loop in every program | 6 to 8, measurements 1 and 2 | MO0101 5/5, MO0501 4/4: an assignment on a `case` arm's line, a `for` with a pure body                                                                                                                                       | §5              |

## 1. A reply awaited as a message

**The row.** Round 8's queue (`control8-mo`, `queue.mo`): a worker answers a
request by `queue.send(Want(call: call, from: me))` and finishes its update; the
queue batches the `Want`s under one fsync and sends each worker `Done(outcome)`;
the worker's `Done` arm replies to the connection. The shape is right, it is why
the Mo binary makes 1,420 pairs a second against Go's 428, and it is where the
outage lives: when the queue crashed, a `:never` child, every `Want` was dropped
with a `Dropped` event, no `Done` ever came, and every worker sat in a wait no
law bounds, holding its connection, while the acceptor kept accepting. `ask` has
a mandatory deadline; a reply that arrives as a plain message has none, so the
deadline law was satisfied and the service was down.

A **deferred reply** (three lines): a process receives an `ask`, does not answer
in that arm, keeps a token for the asker, and answers it from a later arm.
Erlang's `GenServer.reply(from, value)` after `{:noreply, state}`. The asker
still sees one `ask` with one deadline.

**The cost.** A worker that used `ask` today would block its update until the
queue answered, which is fine (a worker holds one connection), but the queue's
arm must then reply before it returns, which forbids the batch: one fsync per
request, Go's shape, a third of the speed. So the program chose `send` and lost
the deadline. The language offers no third thing.

**Options.**

A. A reply token, zero syntax. The arm for a message with a reply may keep
`reply_to` in its state instead of answering, and answer it later. The deadline
travels with the token, as `reply_by` does now.

```ruby
message Want(call: Call) : Outcome            # a message with a reply, as today

fn update(state, message)
  case message
    Want(call):
      state.batch = state.batch.push(Pending(call: call, reply: reply_to))   # reply_to: Reply(Outcome), holds reply_by
    Flush:
      try store.append(state.batch.records, within: reply_by ...)
      for p in state.batch: p.reply.answer(outcome_for(p))                    # answers the ask; after reply_by it is a no-op and the asker saw Timeout
      state.batch = []
  end
end
```

The worker writes `case queue.ask(Want(call), within: 10.s)` and handles
`Error(Timeout)` and `Error(Down)` with a 503. A crash of the queue answers
every held `Reply` with `Down` at once (its state is discarded, the runtime
holds the askers). `Reply(T)` is a state-field type like `Handle(P)`, owned by
one process, never in a struct, never sent on.

B. A diagnostic only. MO04xx: "a `send` to a process whose `child` line says
`restart: :never` from a process that is not its supervisor; the message is
dropped if it is down; `ask` it". Catches this program; misses the same wait to
an `:always` child during its restart, and it misses `send` from a supervisor
sibling that is legitimate.

C. A deadline on the message type:
`message Done(outcome: Outcome) within: 10.s`, the runtime crashing a worker
that waits longer. New syntax on the `message` line and a new kind of failure (a
wait tripped as a bug, where a timeout is a value everywhere else). Rejected by
the laws as written.

**Recommendation.** A, and B as its companion diagnostic once A exists (then the
diagnostic can say "ask it and keep `reply_to`"). A changes chapter 3's "the arm
for a message that carries a reply" paragraph and chapter 4's example by one
field type and one method, no grammar. First tested by change 2's Mo program
under `p6.py`: the same three kills, `/health` back, nothing acknowledged lost,
and the erosion round's third suite. Cost to the runtime: a table of held
replies per process, answered `Down` on crash; a step.

## 2. The failure model on the declaration, checked at the caller

**The row.** `child Queue(fs, clock, opening), restart: :never` was the right
declaration (chapter 3: a store that does not replay its own state must say so)
and nobody who held a `Handle(Queue)` could see it. The Elixir round says what
the runtime's row is worth: `rest_for_one` in 70 lines of `server.ex` restored
the service three times in 261 to 583 ms with nothing lost, then gave up on the
fourth kill inside 2 s because Elixir `Supervisor`'s default intensity is 3 in
5 s (Erlang's own `supervisor` defaults to 1 in 5 s; the round-10 `server.ex`
sets neither) and the program never wrote a number. Mo's `max_restarts: 5 per 1.minute` is on the
`child` line where the reader is; the queue's line had no budget because
`:never` has none.

**Options.**

A. `Down` is a variant every `ask` can return, as today, and the checker
requires the `Error` arm to exist (it does: `Error(_)`). No change; the outage
was a `send`. Folds into §1: once a worker asks, `Down` reaches it.

B. The `child` line is the whole failure model, and a process that replays its
state in `start` may be `:always`. No program does this yet: change 2's queue
and kv's store both take an `Opening` that `main` computed and say `:never`. A
restarted process re-runs its `state` initializers with its capabilities
(verified 16 Sep, `erosion-round-suite/reopen-run.mo`, both runtimes), so a
queue whose state opens the folder from `fs` and `dir` at start restarts
correctly today, and the erosion round's change 3 asks for it. Change 3's Mo
maintainer did it (16 Sep, 10:45): `:always`, the board rebuilt inside the
process, the killed queue back in 106 ms under load. What it could not do is
put the budget on the line: `max_restarts` takes a literal, and the budget came
from the command line, so it wrote a `Warden` process whose invariant trips when
the budget is spent. So §2 asks for one more thing, zero syntax: `max_restarts`
and its window may be values the supervisor's arguments carry, as `child
Queue(fs, clock, dir), restart: :always, max_restarts: rules.max_restarts per
rules.window`. Then
`:never` is for a process whose state is truly unrecoverable, and the compiler
asks for a `max_restarts` on every `:always` line (today it defaults). Zero
syntax; one diagnostic: "an `:always` child without `max_restarts`; the budget
is the poison bound (chapter 3)".

**Recommendation.** B, with the default kept at `5 per 1.minute` and the
diagnostic a project setting off by default, since it is a count, not a bug
class. Row for Robert: whether the runtime should answer a `send` to a down
`:never` child with a crash of the sender (the mailbox law's shape) instead of a
`Dropped` event; Fable says no, a dropped send is a value the runtime already
reports, and §1 is the fix.

## 3. The counted shape laws as project settings

**The row.** Chapter 1 (session 6) already says a rule that counts is a setting,
not a law; chapter 2 still lists 70 lines, 6 parameters, depth 3, 12 fields as
laws, and MO0303 enforced the 6 in round 8 for one loop and a struct, catching
nothing. Round 7's longest function was 20 lines; the corpus never met the 70.

**Options.** A. `mo.toml` under `[shape]`: `function_lines = 70`,
`parameters = 6`, `nesting = 3`, `state_fields = 12`, tightened per project,
loosened only there. The diagnostics stay, the numbers move. B. Drop the four
counts. Chapter 2's "projects may tighten, never loosen" becomes the settings'
rule.

**Recommendation.** A. It is what Robert agreed to on 14 Sep; it is a chapter 2
edit and one toolchain step. The measure for the future: a shape diagnostic that
costs a loop in a round is recorded against its number.

## 4. `never`, `invariant`, and the false positive

**The row.** Round 8's "held by two workers at once" `never` was keyed on
`(number, tries)`; the change let a retry reset `tries`, the key collided, and
the `never` tripped twice on correct code. A `never` is a claim in the program's
own words, and a wrong claim costs loops in the language that runs it and
nothing in the language that cannot write it. On the other side of the ledger,
round 7's `never` at rest on the log is exactly the torn-line defect that cost
Elixir a cause in round 10, and Go's maintainer added an `invariant` by hand for
the retry and Python's `_LEGAL` gained five edges: every language wrote the
claim, only Mo checked it at every value at rest.

**Options.** A. Keep `never` and `invariant` as they are; record false positives
as a column from round 9 on. B. Let a `never` name the values it is about
(`never "held by two workers" on lease` with a scope) so a re-keying is a local
edit. C. Retire `invariant` (Robert's item) and keep `never`: an `invariant`
after every update is what round 8's Go maintainer wrote by hand and what the
ledger is built around; nothing has tripped one outside a test.

**Recommendation.** A. Neither construct has cost a loop that was not the
program's own wrong claim, and one has caught a class of defect a baseline paid
for. The `invariant` question stays open until the ledger is changed in the
erosion round, the first program built around one.

## 5. Diagnostics that say what to write

**The row.** Over rounds 6 to 8 and measurements 1 and 2 the same three
diagnostics cost a loop in almost every session: MO0101 (an assignment on a
`case` arm's line, 5 of 5, first fix right 5 times), MO0501 (a `for` with a pure
body that must be a `reduce`, 4 of 4), MO0317 (a dependent module's stale
`verified:` line, 6 of 7, and the only one whose fix is not obvious). MO0403
(`Time.fixture()` outside a test) hit four regenerations of ten with the same
fix. Robert's item names the forms: `return` in a `case` arm, a qualified call,
a split lambda body.

**Options.** A. Each of these diagnostics carries the rewrite (a `--fix` the
agent applies), as MO0101's already does for the arm form; MO0317 names the
changed module and the one `--write` order. B. Accept the forms (`return` in an
arm, a multi-line lambda) as grammar. C. Nothing; the rates are all above 0.7.

**Recommendation.** A for MO0317 now (a toolchain step, the loop every
regeneration lost), C for the rest until one falls under 0.7 at ten sightings,
as chapter 8's rule says. B is a grammar change and needs a row that shows the
diagnostic failing, not merely firing; a diagnostic with a first fix right every
time is the language teaching, which is what the third layer is for.

## 6. Already decided, recorded here so the page is whole

- **Placement** stays the runtime's, no syntax: step 30 put a process on the
  scheduler with the fewest live processes; step 34 (16 Sep) places it with its
  starter while that scheduler holds at most twice its share, and made the
  crossing cheap (chapter 3, chapter 7). The Mac scaling run of 15 Sep and step
  34's rows at 1, 4, and 14 cores are its measure.
- **The runtime surface is a capability**, `platform.runtime`, chapter 3,
  direction 37. It has been used only by a worker's probe; program 7 is where an
  agent operates a service through it.
- **A named function where an anonymous function goes** (Robert's item): zero
  syntax; chapter 4's call-argument rule admits a name. One step, first tested
  by the corpus.
- **The "frozen fixture clock" note** in chapter 3 was stale since step 24; a
  fixture call's wait moves the run's clock. Edited (chapter 3 and chapter 9 carry step 28's rule).
- **A contract tripped by replayed data** is a refusal at open, not a crash
  (change 2, the fourth oracle, both rounds' Go and Python). That is the
  program's and the spec's; the runtime did what chapter 3 says.

## The reading

After ten rounds the language layer has cost the second agent loops (nine to
Go's eight) and caught nothing the tests missed, in every language alike; the
runtime layer's own row went to the BEAM on the Mac. What Mo holds is exact and
small: 0 defects where every baseline had at least one, the loop under a second,
zero dependencies, and one construct, a `never` at rest, that states the
durability claim Elixir's maintainer could only test. The changes above spend
nothing on syntax and everything on the two places the rounds found the language
silent: a reply awaited as a message, and a restart budget nobody wrote. §1 is
the one step that decides whether Mo's program can answer P6 as Elixir's did; it
runs before round 9's models see the language. Built and probed (16 Sep): with
§1 the change 2 queue's crash under load costs the requests in flight, and every
request after it answers `503` within 2 ms with nothing acknowledged lost, the
outage closed; the service does not come back because the program said
`:never`, and the runtime already re-runs a process's state initializers at
restart, so the reopening store is change 3's to write, not the language's.
