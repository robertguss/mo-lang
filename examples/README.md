# Mo example corpus

Read these 50 tiny modules in order. Each includes tests; the last twelve are deliberate compile failures.

- File path equals module path: `Basics.Bindings` lives at `basics/bindings.mo`; compound CapCase names use hyphenated filenames (mapping gap recorded below).
- Files in `rejects/` must fail to compile for the single law named in their `# expect error:` comment.

Unresolved grammar, API, and execution details are recorded in [GAPS.md](GAPS.md). The toolchain is a scaffold; source checks do not establish compilation, process execution, or simulation.

## basics/

1. [bindings](basics/bindings.mo) — Immutable bindings and local mutation.
2. [numbers](basics/numbers.mo) — Sized numbers and named arithmetic.
3. [strings](basics/strings.mo) — Interpolation, multiline strings, graphemes and bytes.
4. [predicates](basics/predicates.mo) — Predicate names and dot calls.
5. [tuples](basics/tuples.mo) — Construction, field access and destructuring.
6. [lists](basics/lists.mo) — List construction and combinators.
7. [option](basics/option.mo) — Some, None, defaults and matching.
8. [result](basics/result.mo) — Result propagation through two calls.
9. [if](basics/if.mo) — Statement, expression and guarded-return forms.
10. [case](basics/case.mo) — Guards and nested patterns.
11. [for](basics/for.mo) — Finite loops with early exits.
12. [anonymous-functions](basics/anonymous-functions.mo) — Inline and block call arguments.

## types/

13. [struct](types/struct.mo) — Named fields and mutable copies.
14. [enum](types/enum.mo) — Data variants and exhaustive matching.
15. [refinement](types/refinement.mo) — Primitive boundary checks.
16. [generics](types/generics.mo) — Generic elements and a trait bound.
17. [trait](types/trait.mo) — One-function trait and implementation.
18. [nested](types/nested.mo) — A result containing an optional value.

## contracts/

19. [requires](contracts/requires.mo) — Precondition and rejecting test.
20. [ensures](contracts/ensures.mo) — Result, entry values and implication.
21. [never](contracts/never.mo) — Guarded two-generator prohibition.
22. [flows](contracts/flows.mo) — Keep card data out of events.

## effects/

23. [clock](effects/clock.mo) — Explicit Clock and deadline.
24. [pure-vs-effectful](effects/pure-vs-effectful.mo) — Pure formatting with a clock-taking caller.
25. [timeout](effects/timeout.mo) — Exhaustive timeout handling.
26. [narrowing](effects/narrowing.mo) — Scoped read-only capability passed down.
27. [sim](effects/sim.mo) — Deterministic test with Mo.Sim selected.

## processes/

28. [counter](processes/counter.mo) — State, two messages and update.
29. [ask](processes/ask.mo) — Typed reply and bounded ask.
30. [mailbox](processes/mailbox.mo) — Mailbox bound and sender-crashes rule.
31. [invariant](processes/invariant.mo) — Compare state against the previous value.
32. [supervisor](processes/supervisor.mo) — Restart policy and restart budget.
33. [pipeline](processes/pipeline.mo) — Two supervised processes and message forwarding.

## tests/

34. [test](tests/test.mo) — Assertions and success-pattern bindings.
35. [rejects](tests/rejects.mo) — A rejecting test for a precondition.
36. [property](tests/property.mo) — Guarded generated inputs.

## recipes/

37. [rate-limiter](recipes/rate-limiter.mo) — Clock-dependent token-bucket specification.
38. [pure-recipe](recipes/pure-recipe.mo) — Capability-free specification.

## rejects/

39. [rebinding](rejects/rebinding.mo) — Reject immutable rebinding.
40. [unused-binding](rejects/unused-binding.mo) — Reject an unused local.
41. [missing-rejects-test](rejects/missing-rejects-test.mo) — Reject an unpaired precondition.
42. [catch-all-arm](rejects/catch-all-arm.mo) — Reject a catch-all on a closed enum.
43. [unconsumed-result](rejects/unconsumed-result.mo) — Reject a discarded Result.
44. [seven-parameters](rejects/seven-parameters.mo) — Reject a seventh parameter.
45. [aliased-var](rejects/aliased-var.mo) — Reject capture of a mutable local.
46. [stored-anonymous-function](rejects/stored-anonymous-function.mo) — Reject a stored anonymous function.
47. [default-parameter](rejects/default-parameter.mo) — Reject a default parameter.
48. [missing-within](rejects/missing-within.mo) — Reject a missing deadline.
49. [hand-edited-verified](rejects/hand-edited-verified.mo) — Reject a handwritten verification claim.
50. [unsupervised-process](rejects/unsupervised-process.mo) — Reject a process with no supervisor.
