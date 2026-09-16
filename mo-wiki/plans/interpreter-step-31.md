---
title: "Step 31: a deferred reply, brief for the worker"
created: 2026-09-15
updated: 2026-09-15
type: plan
tags: [runtime, processes, language]
sources:
  [
    spec/design-v0/10-language-after-the-rounds.md,
    spec/design-v0/03-semantics.md,
    plans/control-run-8.md,
    plans/control-run-10.md,
    plans/interpreter-step-30.md,
  ]
status: queued
---

# Step 31: a deferred reply

Chapter 10 §1, Fable's recommendation of 15 Sep 2026 after round 8's outage and
round 10's P6: the arm for a message that carries a reply may keep the asker
instead of answering, and answer it from a later arm. Round 8's queue answered
its workers by `send(Want(from: me))` and a `Done` message back because an `ask`
would have forced one fsync per request; the batch is why the Mo binary makes
1,420 pairs a second, and the wait for `Done` is the wait no law bounds, the one
that held every connection when the queue crashed. This step gives the batching
process a way to answer an `ask` later, so a worker keeps the `ask` deadline and
sees `Down` when the queue crashes. Zero new syntax: one type, `Reply(T)`, one
binding, `reply_to`, one method, `answer`.

A **deferred reply** (three lines): a process receives an `ask`, does not answer
in that arm, keeps a token for the asker, and answers it from a later arm.
Erlang's `GenServer.reply(from, value)` after `{:noreply, state}`. The asker
still sees one `ask` with one deadline.

## Orientation

`toolchain/src/turns.zig` (`ask` at about line 1077: the asker parks on
`awaiting[seq]`, the reply comes through `answers[seq]` from
`answer(seq, reply, parcel)` at about 1185, null meaning the target crashed;
`wakeAll` on a crash); `sim.zig` (`reply_by` per process at about 112,
`replyBy`, `ask` at 717, `askInline` for one scheduler; where an update's arm
value becomes the reply and where a crash answers null); `check.zig` (the arm of
a message with a reply binds `reply_by` at about 2460 with
`update_reads_reply_by`; the state-field type rules for `Handle(P)` from step
24, which `Reply(T)` copies); `moves.zig` (MO0410, a capability moved by a send;
`reply_to` moves the same way); `bytecode.zig`, `emit_c.zig`, and
`runtime/mo_rt.c` (`mo_ask` at about 5404, `turns_ask` at 7146, `ask_inline`,
`end_ask`: the C backend's copy of the same protocol); `prelude.zig` for the
type table; `03-semantics.md`, the Processes list, the sentence "`ask` blocks
with a mandatory deadline ... `reply_by` is bound"; `09-stdlib.md` for the
type's row. `examples/processes/` for the corpus files of steps 22 and 24
(`reply_by`, `registry.mo`) as the shape of the new one. The round 8 program,
`../mo-lang-control8-mo/examples/programs/jobq/queue.mo`, is the program this is
for: read `Worker` and `Queue` there, but do not change it (it is evidence).

## Write scope

`toolchain/`; `examples/processes/deferred-reply.mo` (new) and its `.expected`;
the spec lines in `03-semantics.md` (the Processes list, one paragraph) and
`09-stdlib.md` (one row) that part A states; `examples/README.md` for the new
file. No program under `examples/programs/` changes. Branch `main`, one commit
per part, `Step 31 part X` in the subject, push after every commit,
`zig build test` green at every commit. A timeout and a memory watchdog on every
`mo` process (kill past 4 GB). Never `tr`.

## Part A: the rule, the type, the checker

The rule, stated in one paragraph in the report and added to the Processes list:
**in the arm for a message that carries a reply, `reply_to` is bound as `state`
and `reply_by` are, of type `Reply(T)` for the message's reply type `T`. The arm
answers the ask either by its value, as today, or by moving `reply_to` into a
`state` field; exactly one of the two. A `Reply(T)` held in state is answered
later by `reply.answer(value)`, which consumes it; the asker's deadline travels
with it, and an answer after the deadline is dropped, the asker having seen
`Timeout`. A held reply whose process crashes or restarts is answered `Down` at
once. A `Reply(T)` lives in a `state` field as `Reply(T)`, `Option(Reply(T))`,
`List(Reply(T))`, or `Map(K, Reply(T))`, never in a struct, a message, or a
return, and never sent on.** Then:

1. `Reply(T)` in the type table, with the state-field rules `Handle(P)` has
   (step 24), and one method, `answer(value: T)`, an effect on the process that
   holds it (no capability needed: the reply belongs to the process that
   received the ask, as a child's handle does).
2. The checker binds `reply_to` in the arm (beside `reply_by`, which stays), and
   requires exactly one of: the arm's value is the reply, or `reply_to` is moved
   into a state field in that arm (the same move analysis as a capability in a
   message, MO0410's machinery). An arm that does both, or neither, or reads
   `reply_to` after moving it, is a diagnostic that says what to write (a new
   code in the MO04xx range; name it in the report). `reply_to` in an arm for a
   message with no reply, in `main`, or in a test is the diagnostic step 22
   gives `reply_by` there.
3. A `Reply(T)` that is dropped (the state field overwritten, the list rebuilt
   without it) without an answer is not a diagnostic: the asker times out at its
   deadline, as it would if the process never answered. Say in the report
   whether the runtime can see the drop cheaply and record an event; do not
   build it if it is not cheap.

## Part B: the runtimes

1. `mo test` and `--sim` (`sim.zig`, one scheduler): the arm that moved
   `reply_to` ends without calling `answer(seq, ...)`; the reply's `seq` and
   deadline live in the `Reply` value; `answer(value)` from a later update
   routes to the asker as today's arm value does; a crash of the holder answers
   every `Reply` its state held with null (`Down`), found by walking the crashed
   state as the region walk of step 29b does, or by a per-process list of held
   seqs (the worker chooses and says why). Under `--faults` a held reply is a
   wait the seed may doom, as an ask is.
2. `mo run` (`turns.zig`, several schedulers): the same through `answers` and
   `awaiting`; the `Reply` value crossing to another scheduler never happens,
   since it cannot be sent; `answer` from the holder's scheduler wakes the
   asker's as `answer` does today.
3. The C backend (`emit_c.zig`, `mo_rt.c`): the same protocol; a built binary of
   the corpus file matches its `.expected`.
4. The deadline: `answer` after `reply_by` has passed is dropped, the asker
   already released with `Timeout`; the message with the ask still counts as
   delivered exactly once (chapter 3, "What timeout means").

## Part C: the corpus and the spec

1. `examples/processes/deferred-reply.mo`: a `Batcher` process that takes
   `Put(key, value) : Ok` asks, keeps each `reply_to` in a `List(Pending)` (a
   struct of key, value, and `Reply(Ok)` is not allowed, so a
   `Map(String, Reply(Ok))` keyed by the ask, or two lists; the file shows the
   shape the rule allows), writes them all on a `Flush` message from a delayed
   send, and answers each; a test that ten asks from `main` are all `Ok` after
   one flush; a `test rejects` under `--sim` that a crash of the batcher between
   the asks and the flush gives every asker `Down`; a test that an asker with a
   deadline shorter than the flush sees `Timeout` and the later `answer` is
   dropped. The `.expected` under `mo run` and as a binary.
2. `03-semantics.md`: the paragraph from part A after the `reply_by` sentence in
   the Processes list, marked "Session 8, step 31". `09-stdlib.md`: the
   `Reply(T)` row. `examples/README.md`: the file's row.
3. The corpus green under `mo test`, `mo run`, and as binaries; every
   `.expected` unchanged; `mo fmt --check` clean; `mo test --write` for the new
   file's `verified:` line only.

## Part D: measured

Best of five, both runtimes (`mo run` and a `mo build` binary), `MO_CORES=1` and
the machine's cores, in the report as a table:

| row                                                                                                               | before (step 30's binary at `toolchain/zig-out/bin/mo` copied aside before part A) | after                                                               |
| ----------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `echo-1k`, `http-1k`, `kv-10k-get` from `mo-bench`                                                                |                                                                                    | unchanged within noise                                              |
| `deferred-reply.mo`: 10,000 asks from 8 processes answered through one flush per 100                              |                                                                                    | asks a second, both runtimes                                        |
| the same shape written as `send` and a `Done` message back (a second process in the same file, or a sibling file) |                                                                                    | asks a second; the deferred reply should be within 10 percent of it |

## Done when

Parts A to D landed and pushed, `zig build test` green, the corpus green in both
runtimes with every `.expected` unchanged, the spec lines in, the numbers table
filled, and the report at `REPORT-step-31.md` at the repo root (also in the
pane) with the rule's paragraph, the diagnostic's code and text, the numbers,
and a numbered list "Decisions the brief did not cover".

## Related

- [[10-language-after-the-rounds]]
- [[control-run-8]]
- [[control-run-10]]
- [[interpreter-step-30]]
- [[roadmap]]
