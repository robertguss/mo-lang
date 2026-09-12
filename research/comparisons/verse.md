---
title: "Mo vs Verse"
created: 2026-09-12
updated: 2026-09-12
type: comparison
tags: [research, errors, processes]
sources: [raw/articles/book-of-verse-00_overview.md, raw/articles/book-of-verse-08_failure.md, raw/articles/book-of-verse-13_effects.md, raw/articles/book-of-verse-14_concurrency.md, raw/papers/verse-calculus-icfp23.md, raw/articles/road-to-ue6-2026.md, raw/articles/gamedeveloper-ue6-verse-2026.md, raw/articles/epic-autortfm-verse-transactions-cpp.md, raw/articles/spj-oplss-2026-verse-lectures.md]
confidence: medium
---

# Mo vs Verse

**One line:** Epic's functional-logic language with transactional semantics. It's the wildcard on the list: could transactions replace or complement Mo's crash-and-restart story ([[d18-two-kinds-of-failure|direction 18]], [[d21-autonomous-crash-fixing|direction 21]])? Read skeptically.

## What it is (status as of Sep 2026)

Verse is Epic's language for Unreal Editor for Fortnite. It draws "from functional, logic, and imperative traditions".[116] In June 2026 Epic said Unreal Engine 6 moves gameplay programming to Verse, "which transactionalizes C++". Epic calls Verse "the foundation for Epic's future programming model", where "global state just works".[121] UE6 Early Access is due in late 2027.[122] The core calculus (ICFP 2023, with Simon Peyton Jones and Tim Sweeney among the authors) gives Verse a rewrite semantics that is confluent for well-behaved terms.[120] Peyton Jones's 2026 lectures on its types and semantics are labelled "work in progress".[124]

## The ideas, one by one

- **Failure as control flow.** An expression succeeds with a value or fails with none. `<decides>` functions and `if` conditions are *failure contexts*, and `?` turns a value into a failable test.[117]
  - *Mo today:* `Result`/`Option`, exhaustive `case`, and `try` ([[p06-results-and-propagation|pick 6]]). Rain carries a typed reason, as in `WindowExpired(captured_at:, now:)` ([[d18-two-kinds-of-failure|direction 18]]).
  - *Verdict:* **reject** at function boundaries. A Verse failure carries no reason, and Mo's error variants are part of the spec.

- **State changes roll back.** Inside a failure context, writes to mutable variables "are provisional—they only become permanent if the entire context succeeds". If a later check fails, the write is undone automatically.[117]
  ```verse
  AttemptPurchase(Cost:int)<transacts><decides>:void =
      set PlayerGold = PlayerGold - Cost   # provisional
      # a failing check here rolls the subtraction back
  ```
  Under the hood, all Verse code runs in a transaction whose scope is set by the outermost caller. Failure contexts are nested transactions, and effects in native C++ must be undoable too.[123] Epic's AutoRTFM compiler instruments C++ so every store can be undone. Fortnite servers have used it since version 28.10, and it needed "94 code changes" to the Fortnite codebase.[123]
  - *Mo today:* a process's `update` mutates `state` directly ([[p10-process|pick 10]]). A bug crashes the process and a supervisor restarts it ([[d18-two-kinds-of-failure|direction 18]]).
  - *Verdict:* **open**. See the skeptical answer below.

- **Runtime errors are a different thing, and can't be caught.** "Runtime errors represent unrecoverable conditions that terminate execution … and cannot be caught or recovered within Verse code".[117] Per Epic, a runtime error should abort the whole transaction. Its own blog admits that "currently, Verse runtime errors do not correctly rollback the aborted transaction".[123]
  - *Mo today:* exactly [[d18-two-kinds-of-failure|direction 18]]: rain is a value, a broken roof crashes, and nothing converts one into the other.
  - *Verdict:* **already have.** Verse is independent industrial confirmation of the two-mechanism split.

- **Time is frozen inside a transaction.** Within one transaction, `GetSecondsSinceEpoch()` "returns the same value every time it is called". A retry sees a new, consistent timestamp.[118]
  - *Mo today:* the runtime intercepts every effect ([[d16-direct-style-io|direction 16]]). Crashes replay from seed plus log ([[d21-autonomous-crash-fixing|direction 21]]).
  - *Verdict:* **steal**: `clock.now` returns one value for the duration of an `update`.

- **Effect specifiers.** `<transacts>`, `<decides>`, `<suspends>`, `<computes>` and others are viral: a caller must declare its callees' effects.[118] A failable function can't be `spawn`ed.[119] `<no_rollback>` marks code that can't be undone, and Epic plans to deprecate it once AutoRTFM covers the C++ side.[123]
  - *Mo today:* capabilities, no effect types ([[d15-effects-via-capabilities|direction 15]]; weighed on [[koka]]).
  - *Verdict:* **reject.** Verse needs specifiers largely because rollback must know what's undoable.

- **Structured concurrency, five shapes.** `sync` waits for all. `race` takes the first result and cancels the losers "immediate[ly]". `rush` takes the first and lets the others run on. `branch` is fire-and-forget, "automatically canceled when execution leaves the enclosing function scope". `spawn` is "Verse's single concession to unstructured concurrency".[119]
  - *Mo today:* `ask … within:` ([[q07-process-api|Q7]]), planned `Task.run`, and the structured-task proposal on [[hylo]].
  - *Verdict:* **steal** `race`'s cancel-the-losers rule for deadlines, and `branch`'s scope-bound lifetime for `Task.run`. **Reject** `rush` and `spawn` in user code: supervised processes are Mo's only unstructured concurrency.

- **A functional-logic core.** Choice, unification and logical variables, formalized as the Verse calculus.[120]
  - *Mo today:* nothing like it, by taste ([[d27-simple-and-elegant-like-ruby|direction 27]]).
  - *Verdict:* **reject.** It is powerful, but even its designers are still writing up its semantics.[124]

## What it gives up

- **Undoing the outside world.** Most C++ couldn't be transactional without a new compiler, which is why `<no_rollback>` spread "polluting a lot of function signatures".[123] Network I/O can't be un-sent. Epic describes transactions across the network only as future work.[123]
- **Parallelism, for now.** AutoRTFM is "single-threaded transactions" only. Transactional memory for parallelism comes later.[123]
- **A finished story for errors.** Runtime errors don't yet roll back correctly.[123]
- **Reasons on failure.** A failed expression produces "no value".[117]

## Evidence

- **Production:** some Fortnite servers compiled with AutoRTFM since v28.10, after 94 source changes.[123]
- **Roadmap:** UE6 Early Access in late 2027, with Verse as its programming model.[121][122]
- **Performance overhead of transactions:** no numbers found in the extracted text.
- **LLMs and Verse:** no evidence found this pass.

## What Mo should take from this

- **The skeptical answer:** transactions do *not* replace crash-and-restart. Verse keeps uncatchable runtime errors beside rollback,[117] hasn't yet made those errors roll back,[123] and can't undo I/O.[123] They *can* complement it at one boundary Mo already has. A process's `update` owns private state ([[d14-processes-are-the-only-identity|direction 14]]) and hands effects to the runtime as commands ([[d16-direct-style-io|direction 16]]). So `update` is a natural transaction, with no C++ to instrument.
- **Proposal:** if `update` crashes, the runtime discards that message's state writes *and* its queued outgoing effects (sends, `events.emit`). Nothing half-done leaks. This is AutoRTFM's on-commit and on-abort behaviour, at the process level.[123]
- **Question for Robert:** after a crash, does the supervisor restart from `init` (OTP, and direction 18 as written), or resume from the last committed state with the poison message set aside for the agent ([[d21-autonomous-crash-fixing|direction 21]])? Both keep the rule that a bug is never handled as rain.
- **Proposal:** freeze `clock.now` for the length of one `update`.[118] That makes a message's handling a pure function of state, message and one timestamp, which is what replay needs.
- **Proposal:** `race` semantics for deadlines: when `within:` fires, the pending work is cancelled at once.[119] `Task.run` gets `branch`'s scope-bound lifetime, with no `rush` or `spawn`.
- **Confirmed, no change:** direction 18's split between failure and bugs. Verse reached the same design independently.[117]

## Related
- [[language-landscape]]
- [[d18-two-kinds-of-failure]]
- [[d21-autonomous-crash-fixing]]
- [[d14-processes-are-the-only-identity]]
- [[d16-direct-style-io]]
- [[q07-process-api]]
- [[koka]]
- [[hylo]]

## Sources

[116] https://verselang.github.io/book/00_overview — Book of Verse: Overview
[117] https://verselang.github.io/book/08_failure — Book of Verse: Failure
[118] https://verselang.github.io/book/13_effects — Book of Verse: Effects
[119] https://verselang.github.io/book/14_concurrency — Book of Verse: Concurrency
[120] https://simon.peytonjones.org/assets/pdfs/verse-icfp23.pdf — The Verse Calculus: A Core Calculus for Deterministic Functional Logic Programming (Augustsson et al., ICFP 2023)
[121] https://www.unrealengine.com/news/the-road-to-ue-6 — The road to Unreal Engine 6 (Epic, June 2026)
[122] https://www.gamedeveloper.com/programming/unreal-engine-6-will-merge-ue5-and-uefn-into-a-single-unified-engine- — Unreal Engine 6 will merge UE5 and UEFN (Game Developer, June 2026)
[123] https://www.unrealengine.com/tech-blog/bringing-verse-transactional-memory-semantics-to-c — Bringing Verse Transactional Memory Semantics to C++ (AutoRTFM, Epic, 2024)
[124] https://simon.peytonjones.org/oplss-26 — The Verse Language: Types, Semantics, and Verification (Peyton Jones, OPLSS 2026)
