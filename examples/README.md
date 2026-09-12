# examples/

Tiny Mo programs that exercise every construct in `spec/design-v0/04-syntax.md` and every production in `spec/grammar.md`.

Rules:

- File path equals module path: `module Basics.Bindings` lives at `basics/bindings.mo`.
- `rejects/` must fail to compile.

## basics/

1. `basics/bindings.mo` — `x =`, `var`, `+=`
2. `basics/numbers.mo` — sized ints, `10_000`, `checked_add`, `saturating_sub`, `wrapping_mul`, a float
3. `basics/strings.mo` — interpolation, `"""`, `size` in graphemes vs `bytes`
4. `basics/predicates.mo` — `?` functions and dot-call sugar
5. `basics/tuples.mo` — build, `.0`, destructure in `case`
6. `basics/lists.mo` — literal, `push`, `map`, `filter`, `reduce`
7. `basics/option.mo` — `Some`, `None`, `or`, `case`
8. `basics/result.mo` — `Ok`, `Error`, `try` through two calls
9. `basics/if.mo` — statement, expression form, trailing `if` on `return`
10. `basics/case.mo` — guards, nested destructuring, literal arms, `_` inside a pattern
11. `basics/for.mo` — range, list, `break`; `for` because of `break`, not a combinator
12. `basics/anonymous-functions.mo` — one-line and block form as arguments

## types/

13. `types/struct.mo` — named construction, `var copy` update
14. `types/enum.mo` — data variants and matching
15. `types/refinement.mo` — `type Money = UInt64 where ...`, a `rejects` test at the boundary
16. `types/generics.mo` — `fn first(xs: List(T)) : Option(T)` and a `where T: Trait` bound
17. `types/trait.mo` — `trait` plus `impl`, one function
18. `types/nested.mo` — `Result(Option(T), E)` handled fully

## contracts/

19. `contracts/requires.mo` — `requires` with its `rejects` test
20. `contracts/ensures.mo` — `result`, `old`, `is`, `implies`
21. `contracts/never.mo` — two-generator comprehension with a guard
22. `contracts/flows.mo` — `flows(CardNumber, into: Events)` beside a struct that carries one

## effects/

23. `effects/clock.mo` — a function taking `Clock`, `within:` on the call
24. `effects/pure-vs-effectful.mo` — the same computation with and without a capability parameter
25. `effects/timeout.mo` — `Timeout` as an ordinary error variant handled by the caller
26. `effects/narrowing.mo` — `fs.scoped(...).read_only` passed down
27. `effects/sim.mo` — `use Mo.Sim` and a test that runs against it

## processes/

28. `processes/counter.mo` — `state`, two `message` lines, `update`
29. `processes/ask.mo` — a message with a reply type, `ask` with `within:`
30. `processes/mailbox.mo` — `mailbox: N` and the sender-crashes rule
31. `processes/invariant.mo` — `invariant` with `old(state.n)`
32. `processes/supervisor.mo` — `supervisor` with `restart:` and `max_restarts:`
33. `processes/pipeline.mo` — two processes, one sends to the other

## tests/

34. `tests/test.mo` — `assert`, `assert x is Ok(c)`
35. `tests/rejects.mo` — one `requires`, one `rejects`
36. `tests/property.mo` — `any(Type)` with a guard

## recipes/

37. `recipes/rate-limiter.mo` — the recipe from chapter 6, `needs Clock`
38. `recipes/pure-recipe.mo` — `needs nothing`

## rejects/

Programs that must **not** compile. First line after `intent` is `# expect error: ...`.

39. `rejects/rebinding.mo` — rebinding a name
40. `rejects/unused-binding.mo` — unused binding
41. `rejects/missing-rejects-test.mo` — `requires` without `test rejects`
42. `rejects/catch-all-arm.mo` — `_` as a whole arm on a closed enum
43. `rejects/unconsumed-result.mo` — unconsumed `Result`
44. `rejects/seven-parameters.mo` — seven parameters
45. `rejects/aliased-var.mo` — anonymous function captures a `var`
46. `rejects/stored-anonymous-function.mo` — anonymous function bound to a name
47. `rejects/default-parameter.mo` — default parameter
48. `rejects/missing-within.mo` — effectful call without `within:`
49. `rejects/hand-edited-verified.mo` — hand-edited `verified:` line
50. `rejects/unsupervised-process.mo` — process with no supervisor
