# Step 31: a deferred reply — worker report

Where this sits: step 31 is chapter 10 §1, the first of the two changes "The language
after the rounds" asked for, and the last interpreter step before round 9 and the placement
step. It unblocks change 2 of the erosion round on the Mo queue: round 8's queue answered its
workers by `send(Want(from: me))` and a `Done` message back, because an `ask` would have cost
one fsync per request, and that `Done` was the wait no law bounded — the one that held every
connection when the queue crashed. With `Reply(T)` the queue can batch and still answer an
`ask`, so the worker keeps its deadline and sees `Down`. Zero new syntax: one type, one
binding, one method.

**Done when, against the brief.** Parts A to D are landed and pushed. `zig build test` is green
on the tree every commit leaves (`step31-scratch/full-test2.log`, exit 0); it was red on `main`
between `6f2727d` and my part A, because that commit swept in the `Reply` prelude type without
the `hideable` flag that the corpus needs, and it was red before this step began for a reason of
its own (decision 11). The corpus is green under `mo test`, `mo test --sim 100` with faults,
`mo run`, and as binaries, and no existing `.expected` changed — the one new one is
`deferred-reply.expected`. `mo fmt --check` is clean on the new file, and its `verified:` line
was written by `mo test --write --sim 100`. The spec lines are in. The numbers table is below.
One thing the brief asked for has no commit of its own: part A, which the lead's commits carried
in (decision 14).

## The rule

In the arm for a message that carries a reply, `reply_to` is bound as `state` and `reply_by`
are, of type `Reply(T)` for the message's reply type `T`. The arm answers the ask either by its
value, as today, or by moving `reply_to` into a `state` field; exactly one of the two. A
`Reply(T)` held in state is answered later by `reply.answer(value)`, which consumes it; the
asker's deadline travels with it, and an answer after the deadline is dropped, the asker having
seen `Timeout` and the message having arrived exactly once all the same. A held reply whose
process crashes or restarts is answered `Down` at once. A `Reply(T)` lives in a `state` field as
`Reply(T)`, `Option(Reply(T))`, `List(Reply(T))`, or `Map(K, Reply(T))`, never in a struct, a
message, or a return, and never sent on.

The paragraph is in `mo-wiki/spec/design-v0/03-semantics.md`, in the Processes list after the
`reply_by` sentence, marked "Session 8, step 31"; the `Reply(T)` row and its `answer` line are
in `09-stdlib.md` after the `Deadline` rows.

## The diagnostic

**MO0411**, `capabilities`, in `toolchain/src/caps.zig` (`keptReplies`), beside MO0410, whose
machinery it borrows.

What it says, in its two forms:

- `<Message>'s arm mentions reply_to but does not hand it to a state field; write
  state.<field> = ... reply_to ... once, and answer it later with reply.answer(value).`
- `reply_to is the state's once <Message>'s arm has kept it; read it back from the state field,
  or answer it with reply.answer(value).`

Why: An arm for a message that carries a reply answers the ask in one of two ways, never both
and never neither (chapter 3, processes; step 31): its value is the reply, as it has always
been, or it keeps the asker by moving `reply_to` into a state field and answers it from a later
arm with `reply.answer(value)`. `reply_to` moves as a capability in a message moves (MO0410):
the arm names it exactly once, inside an assignment to a place under `state`, and every later
read of it is refused, since the asker is the state's now. A `Reply` the state drops without
answering is no error: the asker times out at its own deadline, as it would if the process
never answered.

The third case the brief named — "neither" — is not MO0411 but the type error that was already
there: an arm that answers nothing and mentions no `reply_to` gives a value of the wrong type,
and the checker says so at the arm's last line. `reply_to` in an arm for a message with no
reply, in `main`, or in a test is MO0201 with the `reply_by` sentence, now naming both.

## What was built, part by part

### Part A: the rule, the type, the checker

- `types.zig`: a `reply` tag, `a` the reply type; it unifies, substitutes, and prints as
  `Reply(T)`.
- `prelude.zig`: the type row `Reply` (arity 1, stdlib), and the fn row
  `Reply(T).answer(T) : none`. No capability: the reply belongs to the process that received
  the ask, as a child's handle does.
- `check.zig`: `Reply(T)` resolves as a prelude type; `authorityIn` counts a `Reply` as
  authority, so a struct field, an enum field, a return, and an anonymous function's capture
  refuse it exactly as they refuse a handle. In the update's case, an arm whose message carries
  a reply binds `reply_to` beside `reply_by`; `armDefersReply` decides, from the arm's own
  nodes, whether it mentions `reply_to`, and a deferring arm is checked with `types.none` as
  its expected value, so its last line is one more statement.
- `caps.zig`: MO0411, and the state-field shapes — `keptHandle` now admits a `Reply` wherever
  it admits a `Handle`.
- `loops.zig`: answering an ask is an effect, so a `for` whose body answers is not a pure loop
  (MO0501 would otherwise refuse the flush).

### Part B: the runtimes

A `Reply(T)` is the ask's sequence number and nothing else: `Value.reply: u64` in the
interpreter, `MO_REPLY` with `as.u` in the C runtime. The deadline stays with the asker, which
already drops what it no longer waits for, so a late `answer` needs no clock of its own.

- The deferral is a static fact about the arm, so it is an instruction: `defer_reply`, emitted
  as the first instruction of the arm `armDefersReply` picks out. `reply_to` is a second
  instruction, bound once at the update's head as `reply_by` is; `answer` is a third, lowered
  like `send`.
- `sim.zig` (`mo test`, `--sim`, one scheduler): a process keeps `kept`, the seqs of the asks
  it holds, and `answers`, the answers of the running update. An answer commits with the update,
  as a send does, so an update that crashes after `answer` answers `Down` instead. `askInline`
  grew a second phase: once the arm that took its message kept the asker, the ask stops
  delivering to its target and runs ordinary rounds, moving simulated time to the next delayed
  send, until the answer comes, the target goes down, or its own deadline passes.
- `turns.zig` (`mo run`, several schedulers) needed no change: the asker already parks on
  `awaiting[seq]` until `answers[seq]` or its deadline, and `answer` from the holder's
  scheduler wakes it exactly as a reply from an arm does. A `Reply` never crosses a scheduler,
  since it cannot be sent.
- A crash or a restart answers every held ask `Down` at once (`downKept`, `down_kept`), found
  by the per-process list, not by walking the crashed state. I chose the list over the region
  walk of step 29b because it is O(held) rather than O(state), needs no type information at
  run time, and is the same three lines in Zig and in C; the cost is that the runtime cannot
  see a `Reply` the state drops (below).
- `mo_rt.c` and `emit_c.zig`: the same protocol, `mo_reply_to`, `mo_defer_reply`, `mo_answer`,
  and the same second phase in `ask_inline`. The corpus file's binary prints what `mo run`
  prints.

**Can the runtime see a dropped `Reply` cheaply?** No, not with the per-process list, and I did
not build it. The list holds seqs; nothing connects a seq to the state field that held it, so
a state field overwritten or a list rebuilt without a `Reply` leaves the seq in `kept` and the
asker waiting until its own deadline. Seeing it cheaply would need the region walk — every
`Reply` reachable from the new state, compared with `kept`, after every update of a process
that keeps one — which is O(state) per update on the hot path, for an event. The asker times
out at its deadline either way, which is the rule, so the event would buy a diagnosis, not a
behaviour. Worth revisiting only if a program loses askers in the field.

### Part C: the corpus and the spec

`examples/processes/deferred-reply.mo`, a `Batcher` whose `Put(key, me) : UInt64` arm never
answers: it pushes `reply_to` into a `List(Reply(UInt64))` and arms a `Flush` with a delayed
send, and the flush answers the whole batch with `reply.answer(batch)`. Its invariant, "the
batch keeps an asker for every key in it", is the claim the shape rests on, and the `Orphan`
message trips it. Three tests, all holding under `--sim 100 --faults`: ten asks all answered by
a flush and never by the arm that took them; an asker whose deadline is shorter than the flush
sees `Timeout` while the key is still written, so the message arrived exactly once and the
later answer was dropped; and a `test rejects` where a crash between the ask and the flush
gives the asker it kept `Down`.

The file also has a `main`: eight `Asker` processes put at once, so one flush answers a real
batch, which an ask from `main` can never show (an ask from `main` is synchronous, so each of
the ten in the first test is its own batch of one).

## Numbers

Best of five, on the M3 Max (14 cores, 96 GiB), nothing else running. "Before" is step 30's
binary, copied aside before part A (`step31-scratch/mo-step30`, `mo-bench-step30`). Both
binaries were run back to back for each row, because a first pass an hour apart showed drifts of
8 to 11 percent that the back-to-back pass did not reproduce; the numbers below are the
back-to-back pass. `MO_CORES=1` is this machine's best (the scaling run of 15 Sep).

### The standing rows: unchanged within noise

Microseconds for the whole row, lower is better.

| row | before c1 | after c1 | before c14 | after c14 |
| --- | --- | --- | --- | --- |
| `echo-1k` | 24,747 | 20,191 (-18%) | 126,268 | 106,138 (-16%) |
| `echo-1k-c` | 27,384 | 26,248 (-4%) | 107,950 | 107,782 (-0%) |
| `http-1k` | 58,325 | 61,152 (+5%) | 73,563 | 66,217 (-10%) |
| `http-1k-c` | 55,479 | 55,030 (-1%) | 69,212 | 62,067 (-10%) |
| `kv-10k-get` | 431,145 | 418,898 (-3%) | 1,248,260 | 1,247,878 (-0%) |
| `kv-10k-get-c` | 209,608 | 212,861 (+2%) | 1,036,547 | 1,026,465 (-1%) |

Every one of these rows is a socket round trip, and the run-to-run spread on this machine is
wider than any of these deltas; the signs are as often negative as positive. Nothing regressed.
The step adds three instructions to the interpreter's dispatch and two fields to a process, and
neither shows here, which is what "unchanged within noise" should look like.

### The deferred reply against the send-and-a-message-back shape

10,000 asks, `N` processes putting at once, one flush per full batch (the flush bound is `N`, so
it fires on a batch rather than on the tail timer). Both programs are
`step31-scratch/bench/deferred.mo` and `sendback.mo`; both time themselves inside the
batcher, from its first `Put`/`Want` to the flush that completes the run, and both `main`s
start the run and return, so neither harness polls and neither is inside the window. Asks (or
lease-and-ack pairs) a second, higher is better.

| cores | askers | runtime | deferred reply | send + Done back | deferred / send |
| --- | --- | --- | --- | --- | --- |
| 1 | 8 | `mo run` | 188,679 | 188,679 | 1.00 |
| 1 | 8 | binary | 227,272 | 204,081 | 1.11 |
| 14 | 8 | `mo run` | 78,740 | 57,471 | 1.37 |
| 14 | 8 | binary | 80,000 | 48,309 | 1.66 |
| 1 | 128 | `mo run` | 112,179 | 243,512 | **0.46** |
| 1 | 128 | binary | 525,473 | 475,428 | 1.11 |
| 14 | 128 | `mo run` | 142,628 | 172,137 | 0.83 |
| 14 | 128 | binary | 195,764 | 128,000 | 1.53 |

**The brief's claim holds for the shape the brief named.** At 8 asking processes, the one it
asked for, the deferred reply is level with the send-and-a-message-back shape under `mo run`
(1.00) and ahead of it as a binary (1.11) at one core, and ahead of it on both runtimes at
fourteen (1.37 and 1.66). Well inside ten percent, and on the right side of it.

**One row is not, and it is worth the lead's attention.** At 128 asking processes under `mo run`
on one scheduler, the deferred reply costs 2.2 times the send shape (112k against 244k). It is
not noise: five consecutive runs gave 109,714 / 109,714 / 110,933 / 106,212 / 106,212 against
221,866 / 212,425 / 221,866 / 237,714 / 237,714. It is not inherent to the mechanism either —
the same shape as a built binary is 1.11 *faster* than the send shape (525k against 475k). The
cost is the interpreter's: 128 asks held at once means 128 fibers parked in `turns.ask`, each
holding a stack and each woken through `answers[seq]`, where the send shape parks nothing and
runs entirely out of mailboxes. The C runtime's fibers are cheaper, so the row inverts there.
So: the deferred reply is free at the concurrency round 8's queue actually runs at, and the
interpreter's parked fiber is the thing to measure again if a program holds asks by the hundred.
That is a row for the placement step, not a reason to hold this one.

## Decisions the brief did not cover

1. **A `Reply(T)` is a sequence number, not a seq and a deadline.** The brief said the reply's
   seq and deadline live in the `Reply` value. They do not: the deadline lives with the asker,
   which already releases itself at it and forgets the seq, so an answer past it finds nothing
   waiting and is dropped. That keeps the value scalar — eight bytes, one `MoValue`, no
   allocation, nothing for a compaction or a sweep to walk — and keeps one clock instead of two.
2. **A per-process list of held seqs, not a walk of the crashed state.** The brief let the
   worker choose; the reasons are in part B above. The consequence is that a dropped `Reply` is
   invisible to the runtime, which the brief allowed.
3. **The deferral is a compiled fact, not a discovered one.** Whether an arm keeps its asker is
   decided once, by `check.armDefersReply`, and emitted as a `defer_reply` instruction at the
   head of that arm. The runtime never has to notice that a value was stored. The rule the
   checker uses is "the arm mentions `reply_to`", which is also the rule MO0411 reads, so the
   diagnostic and the lowering can never disagree.
4. **"Mentions `reply_to` exactly once, inside an assignment to a place under `state`."** This
   is the concrete form I gave "moved into a state field". It refuses the second mention with
   MO0411 rather than trying to model reads-after-move in every branch, and it is the same
   single pass over the arm's nodes that MO0410 already walks.
5. **A corpus file outside `programs/` that names a `# run:` line.** The brief put the file in
   `examples/processes/` and asked for its `.expected`, but the corpus test only ran
   `programs/<name>.mo` and `programs/<name>/main.mo` through `mo run` and `mo build`. Rather
   than move the file or add a program (the brief forbade both), `corpus.isRunnable` now also
   accepts any corpus file whose first line is `# run:`. One new rule, stated in
   `examples/README.md`, and `deferred-reply.mo` is its only user.
6. **Answering is an effect for the loop rule.** `for held in state.waiting ... held.answer(n)`
   was MO0501, a pure loop, because `loops.effectful` only knew capabilities and handles. A
   `Reply` is authority like both, so it joined them.
7. **An answer commits with its update.** `reply.answer(v)` goes in a per-update list and is
   routed when the update commits, exactly as a send is, so an update that crashes after
   answering gives the asker `Down`, not the value. The brief did not say; the transaction rule
   (chapter 3, "`update` is a transaction") does.
8. **A second answer to the same ask is dropped, silently.** Nothing at the type level stops a
   program reading a `Reply` out of a `Map` twice and answering twice; the runtime holds the
   list of asks it still owes and ignores an answer to any other seq. The asker is already gone
   in every such case, so there is nothing to report to.
9. **`mo-wiki/spec/errors.md` was regenerated.** It is `zig build errors`' output, not wiki
   prose, and the corpus test fails without it. It is outside the brief's `mo-wiki/` write
   scope by the letter; I read the scope as excluding wiki pages, not the toolchain's own
   generated catalog.
10. **`Reply` is a hideable prelude type.** Three corpus modules already declare their own
    `Reply` — `programs/agent/model.mo`, `programs/kv/main.mo`, `recipes/model-client.mo` — so
    the new prelude type collided with them (MO0205, "Reply is already a prelude type", eleven
    of them across the corpus). `Reply` therefore joins `Event`, `RuntimeError`, and
    `EntryKind` as `hideable`: a module's own `Reply` hides the prelude's from that module's
    code, and the prelude's rows still mean the prelude's. The cost is that a module which
    declares its own `Reply` cannot also write `Reply(T)`; none does, and the same is already
    true of `Event`. I found this by running `zig build test` on the step's own tree, not from
    the brief, which named no such collision.
11. **A pre-existing crash in `zig build test` on this Mac, fixed in place.** The unit test
    `vm: a recursion frees what each level made while the levels inside it run` overran the
    native stack and crashed with SIGSEGV. It is not step 31's: I ran it on a clean worktree of
    `main` at `afdc495`, with none of this step's changes, and it crashes identically
    (`step31-scratch/base-recursion.log`). The cause is environmental: the test drives the vm
    on the Zig test runner's own thread, which macOS gives 8 MiB, while `mo` itself runs Mo
    code on a thread of `contracts.vm_stack_bytes`, 256 MiB (`main.zig`, `turns.zig`), and the
    test's comment already assumed "the test thread's native stack". The body now runs on a
    thread with that same stack size, so the test tests the stack the product runs on and no
    longer depends on the platform's default. Nothing else about the test changed: the same
    1,500 levels, the same 256 MiB regions, the same assertions. Without this, `zig build test`
    could not be green at any commit on this machine.
12. **The measurement's batch could not be one flush per 100 with eight asking processes.** An
    `ask` blocks, so eight processes put at most eight replies in flight and a bound of 100
    never fires: the batch then waits out the tail timer, and the row measures the timer, not
    the mechanism (a first pass with a 1 ms timer gave 6,4xx a second for every configuration,
    all of them timer-bound, which is what put me on to it). The flush bound is therefore set to
    the number of asking processes, so it fires on a full batch and no timer is in the window;
    the brief's shape is the 8-asker row, and the 128-asker row stands in for "one flush per
    100" with a real batch of 128.
13. **Both measured programs had to stop polling before either number meant anything.** The
    send-and-a-message-back shape gives `main` nothing to block on — no worker answers an ask —
    so my first harness polled the workers, and the poll dominated: 103 a second at 128 workers,
    against the deferred reply's 16,584, which is a measurement of the harness and nothing else.
    Both programs now time themselves inside the batcher, from its first message to the flush
    that completes the run, and both `main`s start the run and return, since `mo run` and a
    binary go on handing out turns until no message waits and no update is in progress. Neither
    harness polls, both cost the same, and neither is inside the window. This is the whole
    reason the 8-asker rows moved from "deferred 1.02x ahead" to a clean 1.00 and 1.11.
14. **The lead's commits swept parts of this step in before I could commit them.** `6f2727d`
    ("Measurement 1 complete") and `92a4c46` ("Round 9: kimi-k3 on Python") each carried this
    worker's staged files — the whole of part A between them — because the files were sitting in
    the shared tree's index when the lead committed. Part A therefore has no `Step 31 part A`
    commit of its own; parts B, C, and D do. The lead has since recorded the rule in `236cb1c`
    ("The lead commits by path only"). For my side of it: I now stage and commit in one command
    and never leave the index populated between calls.
