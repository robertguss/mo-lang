# examples/

The Mo program corpus: 50 tiny modules. Together they cover every construct in `mo-wiki/spec/design-v0/04-syntax.md` and every production in `mo-wiki/spec/grammar.md`, one construct per file. The corpus is the first test of the syntax, the first training material for agents, and the first test suite for the interpreter.

Two rules a reader needs:

- **File path equals module path.** `module Basics.Bindings` lives at `basics/bindings.mo`. A multi-word segment is hyphenated: `Basics.AnonymousFunctions` lives at `basics/anonymous-functions.mo`.
- **Everything in `rejects/` must fail to compile.** Each file there breaks exactly one law, named on its `# expect error:` line.

Where the grammar and chapter 4 ran out, the corpus used the plainest option and recorded it in `GAPS.md`.

## basics
1. `basics/bindings.mo`: `x =` binds once, `var` changes, `+=`
2. `basics/numbers.mo`: sized integers, `10_000`, `checked_add`, `saturating_sub`, `wrapping_mul`, a float
3. `basics/strings.mo`: interpolation, `"""`, `size` in graphemes and `bytes`
4. `basics/predicates.mo`: `?` functions and dot-call sugar
5. `basics/tuples.mo`: build a tuple, read `.0`, destructure in `case`
6. `basics/lists.mo`: a list literal, `push`, `map`, `filter`, `reduce`
7. `basics/option.mo`: `Some`, `None`, `or`, `case`
8. `basics/result.mo`: `Ok`, `Error`, `try` through two calls
9. `basics/if.mo`: `if` as a statement, as a value, and trailing on `return`
10. `basics/case.mo`: guards, nested destructuring, literal arms, `_` inside a pattern
11. `basics/for.mo`: `for` over a range and a list, `break`, and why these are loops
12. `basics/anonymous-functions.mo`: one-line and block form, as call arguments

## types
13. `types/struct.mo`: named construction and the `var` copy update
14. `types/enum.mo`: data variants and matching every one
15. `types/refinement.mo`: `type Percent = UInt32 where ...` and a `rejects` test at the boundary
16. `types/generics.mo`: `fn first(xs: List(T)) : Option(T)` and a `where T: Trait` bound
17. `types/trait.mo`: a `trait` and its `impl`
18. `types/nested.mo`: `Result(Option(T), E)` handled in full

## contracts
19. `contracts/requires.mo`: `requires` with its `test rejects`
20. `contracts/ensures.mo`: `result`, `old`, `is`, `implies`
21. `contracts/never.mo`: a two-generator `never` with a guard
22. `contracts/flows.mo`: `flows(CardNumber, into: Events)` beside a struct that carries one

## effects
23. `effects/clock.mo`: a function that takes a `Clock`; `clock.now` cannot wait, so it takes no `within:`
24. `effects/pure-vs-effectful.mo`: the same computation with and without a capability
25. `effects/timeout.mo`: `Timeout` as an ordinary error the caller handles
26. `effects/narrowing.mo`: `fs.scoped(...).read_only` passed down
27. `effects/sim.mo`: `mo test` always runs on the simulator, so an effectful test is deterministic

## processes
28. `processes/counter.mo`: `state`, two `message` lines, `update`
29. `processes/ask.mo`: a message with a reply type, and `ask` with `within:`
30. `processes/mailbox.mo`: `mailbox: N`, and the sender-crashes rule
31. `processes/invariant.mo`: `invariant` with `old(state.km)`
32. `processes/supervisor.mo`: `supervisor` with `restart:` and `max_restarts:`
33. `processes/pipeline.mo`: two processes, one sending to the other

## tests
34. `tests/test.mo`: `assert`, and `assert x is Ok(user)`
35. `tests/rejects.mo`: one `requires`, one `test rejects`
36. `tests/property.mo`: `any(Type)` with a guard

## recipes
37. `recipes/rate-limiter.mo`: chapter 6's rate limiter, `needs Clock`
38. `recipes/pure-recipe.mo`: a recipe that `needs nothing`

## rejects (must not compile)
39. `rejects/rebinding.mo`: a name bound twice
40. `rejects/unused-binding.mo`: a binding never read
41. `rejects/missing-rejects-test.mo`: a `requires` with no `test rejects`
42. `rejects/catch-all-arm.mo`: `_` as a whole arm on a closed enum
43. `rejects/unconsumed-result.mo`: a dropped `Result`
44. `rejects/seven-parameters.mo`: seven parameters where six is the limit
45. `rejects/aliased-var.mo`: a `var` captured by an anonymous function
46. `rejects/stored-anonymous-function.mo`: an anonymous function bound to a name
47. `rejects/default-parameter.mo`: a parameter with a default value
48. `rejects/missing-within.mo`: a capability call with no `within:`
49. `rejects/hand-edited-verified.mo`: a `verified:` line written by hand
50. `rejects/unsupervised-process.mo`: a process no supervisor names
