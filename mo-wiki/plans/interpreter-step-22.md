---
title: "Step 22: what program 1 and round 5 found, brief for the worker"
created: 2026-09-14
updated: 2026-09-14
type: plan
tags: [runtime, stdlib, tooling, contracts]
sources: [plans/program-1.md, plans/control-run-5.md, decisions/decision-log.md, spec/design-v0/02-laws.md, spec/design-v0/03-semantics.md]
status: in-progress
---

# Step 22: what program 1 and round 5 found

Program 1 ([[program-1]]) found one toolchain bug, five gaps, and the evidence the decision log asked for: literal deadlines lie where they nest. Round 5 ([[control-run-5]]) added one grammar form a diagnostic can cover. This step fixes the bug, closes the gaps that need no syntax, designs the derived deadline, and rewrites `jobq` on it. No grammar change: the `state` and `old` field names and the one-line `if` are Robert's questions for the morning.

## Orientation

`examples/programs/jobq/TOOLCHAIN-BUGS.md` and the six `jobq` lines of `examples/GAPS.md`; `examples/programs/jobq/server.mo` and `main.mo` (the three derived sums in comments); `examples/recipes/store.mo` and both implementations (`notes/store.mo`, `jobq/store.mo`); `toolchain/src/recipe.zig`, `check.zig` (`MO0302`), `server.zig` and `runtime/mo_rt.c` (the fixture `Fs`), `json.zig`, `sim.zig`, `turns.zig`, `sources.zig` (deadlines under both runtimes), `diag.zig`, `errors.zig`; `spec/design-v0/02-laws.md` (the deadline law), `03-semantics.md` (the `ask` paragraph), `09-stdlib.md` (`Fs`, `Json`, `## Http`); the decision rows of 14 Sep night.

## Write scope

`toolchain/`, `examples/`, and these spec lines only: the deadline law's sentence in `02-laws.md`, the `ask` paragraph of `03-semantics.md`, the `Fs.fixture`, `Json`, and `Deadline` rows of `09-stdlib.md` and `PRELUDE.md`, the recipe's intent line in `examples/recipes/store.mo`; each with a "Session 5, step 22" line. Branch `session-05`, one commit per part, `Step 22 part X` in the subject, push after every commit, `zig build test` green at every commit.

## Part A: the bug and two gaps

1. `mo check --recipe` counts only the file's own lines against `MO0302`; the recipe's tests are not the file. `jobq/store.mo` may take back the two tests it dropped if the worker judges them worth it.
2. `Fs.fixture().list` on a folder that is not there is `Error(Missing("."))`, as the real `Fs` answers; both runtimes; the fixture's row says so; `jobq`'s `books.mo` test that could not be written is written.
3. A `Json` row that gives an integer: the worker chooses the smallest addition consistent with the table (a `Json` value's whole number as `Int64`, or a decode into a typed struct field that is an integer), both runtimes, a corpus test, the spec row; `jobq/job.mo` stops reading counts through `to_string(0).to_u64`.

## Part B: the derived deadline

The evidence: `jobq` wrote 15 chosen `within:` literals and 3 derived by hand as sums in comments, and two of the sums were wrong once. The law does not change: every call that can wait carries `within:`. What changes is what `within:` may be given.

A prelude type `Deadline`, a point in time on the process's clock. Inside an `update` arm for a message that carries a reply, the name `reply_by` is bound to the asker's deadline, as `state` is bound: the runtime knows it, since the `ask` carried it. `within:` accepts a `Deadline` where it accepts a `Duration`: the call gets what remains, and is `Timeout` at once when nothing remains. `deadline.at_most(d: Duration)` gives the earlier of the deadline and now plus `d`, so a nested `within:` may tighten and never extend; there is no way to make a `Deadline` later than the one it came from. `main` has no asker, so its calls stay literal; a process arm for a message with no reply has no `reply_by`. Under `Mo.Sim` the seed decides what remains, as it decides timeouts today; `--faults` can make `reply_by` already past. Both runtimes. A corpus file in `examples/processes/` shows an `ask` whose callee makes two `Fs` calls on `reply_by` and times out as a whole, not per call.

Then `jobq`: the worker's asks of the queue keep their literal, the service's file calls run on `reply_by`, `main`'s `Open` keeps its literal and the replay runs on `reply_by`; the three sums and their comments go. Report the count after: chosen, derived, and whether any literal is still a sum.

## Part C: the recipe's rewrite rule

`Recipes.Store`'s intent says what both implementations must do with a log that may end in part of a change: it is rewritten whole at the next change, and changes are taken from then on (jobq's rule), so work resumes after faults stop. `notes/store.mo` follows it (its `503 on a torn log` becomes a rewrite at the next change), `mo check --recipe` green on both, `notes`'s `.expected` files unchanged or the commit says why.

## Part D: two diagnostics

1. `MO0206`'s catalog `why` loses the sentence about a method binding to a literal; that sentence lives in the message of the one case it names (a call on the last integer of a range), as step 21 wrote it. Round 5's `MO0101` at `x is Ok(_) == y` says that `is` binds loosely inside a comparison and shows `(x is Ok(_)) == y`. Corpus `rejects/` files for both, the catalog regenerated.

## Numbers

`kv-10k-get`, `http-1k`, and their native rows before and after (part B touches the ask path), best of five, nothing over 10 percent slower; `jobq`'s lease-and-ack rate with 32 workers before and after, native; the `within:` count after.

## Done when

Green at every commit; the bug fixed and the two gaps closed with corpus tests; `Deadline` and `reply_by` in both runtimes and the spec lines, the corpus file, `jobq` rewritten on it with the count; the recipe's rule and both implementations green under `--recipe`; the two diagnostics; the numbers; pushed; a numbered list "Decisions the brief did not cover".

## Related
- [[program-1]]
- [[control-run-5]]
- [[interpreter-step-21]]
- [[d17-mandatory-deadlines]]
