# examples/

The Mo program corpus: 50 tiny modules. Together they cover every construct in `mo-wiki/spec/design-v0/04-syntax.md` and every production in `mo-wiki/spec/grammar.md`, one construct per file. The corpus is the first test of the syntax, the first training material for agents, and the first test suite for the interpreter.

Two rules a reader needs:

- **File path equals module path.** `module Basics.Bindings` lives at `basics/bindings.mo`. A multi-word segment is hyphenated: `Basics.AnonymousFunctions` lives at `basics/anonymous-functions.mo`.
- **Everything in `rejects/` must fail to compile.** Each file there breaks exactly one law, named on its `# expect MO0xxx: sentence` line: the code the checker's first diagnostic must carry, and the sentence it prints.

Where the grammar and chapter 4 ran out, the corpus used the plainest option and recorded it in `GAPS.md`.

`mo test <file>` runs a file's tests on the interpreter today, with processes on the deterministic `Mo.Sim` scheduler. Every `test` must pass with no crash in any process it starts, every `test rejects` must trip a `requires`, a refinement, an `invariant`, or a `never`, and every `property` must hold under 200 seeds. Every `never` is checked at the end of every test, `test rejects`, and property run, over the values the run held, with or without `--sim`. It then prints the `verified:` line. A recipe test that calls a signature no agent has implemented yet is skipped.

Every file outside `rejects/` ends with its `verified:` line, written by `mo test --write --sim 100 <file>` and recorded in the `.mo.ids` sidecar at its program root (the file's own folder, or `programs/` for the programs). The sidecar is the toolchain's: a stable id and a content hash per declaration, and the hash of the line. Editing a declaration, or the line, without running `mo test --write` again is `MO0317`, so the corpus test fails on a stale line. `processes/racy.mo` records `verified: types`, since its test fails under `--sim`.

`mo test --sim N <file>` is tier 3: every test that starts a process runs N more times (default 100), each under a seed that chooses the delivery order, whether a statement's sends are delivered before the next statement, the clock's advance, and which fixture calls fail or are slow. A failure prints its seed and the interleaving; a test that holds only when no fixture fails is reported as passing only without faults. The corpus test runs every file with `--sim 100`: every process test holds under faults, except `processes/racy.mo`, whose test must fail under `--sim` and pass without it.

`mo run <file> -- args` runs a program's `main` on the real platform, `Mo.Server`. A program's processes run there too, each on a thread of its own, taking turns, so one waiting on a socket does not hold up the others (`toolchain/src/turns.zig`). A file in `programs/` names its arguments on its first line (`# run: Ada`) and, when it ends with a code other than 0, that code on an `# exit: 3` line; `<name>.expected` beside it holds its exact stdout. The corpus test runs each program through `mo run`, as a subprocess, from inside `programs/`, so a program reads `data/` by that relative path. Its `test` blocks run like any other file's.

`mo build <file>` compiles a program to C and links it with `zig cc` into one binary (`toolchain/src/emit_c.zig`, `toolchain/runtime/mo_rt.c`); `mo build --tests <file>` makes a binary that runs the file's tests. The interpreter is the reference, so the corpus test sets the two side by side: every file outside `rejects/` is built with `--tests` and must print exactly what `mo test` prints and exit as it exits, and every program is built from its own folder and, once per `# run:` line, must print the same stdout and stderr and exit with the same code as `mo run`. Processes and `Net` compile to C (step 15), and so does `Http` (step 16): the corpus's process files, `effects/net.mo`, `effects/http.mo`, `stdlib/http.mo`, `programs/echo`, `programs/kv`, and `programs/httpd` are built and compared like every other file, their tests in the fixed order and their programs over real sockets on 127.0.0.1.

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
61. `basics/returns-nothing.mo`: a function with no return type, called for what it writes, and a negative number as a pattern

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
62. `contracts/never-trips.mo`: a `never` that plain test data breaks, tripping a `test rejects` under `mo test` without `--sim`
65. `contracts/property-refined.mo`: properties over refined types; `any(Percent)` never gives 65,535, and `any(Status)`, whose `where` few `UInt16` values pass, generates between its bounds

## effects
23. `effects/clock.mo`: a function that takes a `Clock`; `clock.now` cannot wait, so it takes no `within:`
24. `effects/pure-vs-effectful.mo`: the same computation with and without a capability
25. `effects/timeout.mo`: `Timeout` as an ordinary error the caller handles
26. `effects/narrowing.mo`: `fs.scoped(...).read_only` passed down
27. `effects/sim.mo`: `mo test` always runs on the simulator, so an effectful test is deterministic
58. `effects/net.mo`: an echo server whose listener process hands each connection to a worker process, driven by a test through `Net.fixture()` with no real socket, and holding under faults
63. `effects/http.mo`: a server process that accepts one exchange per message and answers `GET /hello?name=x` and `POST /echo`, driven by a test through `Http.fixture()` with no real socket, and holding under faults, with a raw `Net` server whose response has no `content-length`; `stdlib/http.mo` beside it writes requests by hand at an `HttpListener` to show what the reader makes of a body, a query, headers, and requests that are not HTTP, and reads what `reply` and `send` put on the wire

## processes
28. `processes/counter.mo`: `state`, two `message` lines, `update`
29. `processes/ask.mo`: a message with a reply type, and `ask` with `within:`
30. `processes/mailbox.mo`: `mailbox: N`, and the sender-crashes rule
31. `processes/invariant.mo`: `invariant` with `old(state.km)`
32. `processes/supervisor.mo`: `supervisor` with `restart:` and `max_restarts:`
33. `processes/pipeline.mo`: two processes, one sending to the other
52. `processes/invariant-trips.mo`: chapter 4's `invariant "done never goes backwards"` tripping a `test rejects`
57. `processes/racy.mo`: a race the fixed order hides; its test passes under `mo test` and fails under `mo test --sim`

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
67. `rejects/captured-capability.mo`: a capability captured by an anonymous function (step 18)

## payments (the milestone)
51. `payments/refund.mo`: chapter 4's refund module, with the differences `GAPS.md` records

## programs (`main` on Mo.Server)
53. `programs/hello.mo`: `fn main(platform: Platform)`, an argument, and `stdout`
54. `programs/count-lines.mo`: `platform.fs.scoped("data").read_only` and a real read with `within:`
55. `programs/exit-code.mo`: a line on `stderr` and `platform.exit(3)`
66. `programs/not-text.mo`: `bytes/not-text.txt` holds a byte that is not UTF-8, so `read`, `read_lines`, `fold_lines` handing `out` on (after printing the line before it), and `fold_lines` counting bytes are `NotText`, and `read_bytes` gives its 36 bytes; its second run reads `bytes/text.txt`, which every row reads
68. `programs/runaway.mo`: recursion past the depth limit of 10,000 nested calls crashes `main` with a report naming the function, and exits 70, under `mo run` and as a binary (step 18)
56. `programs/logstat/`: program 2 (`mo-wiki/spec/programs/02-log-analyzer.md`) in four modules, `parse.mo`, `stats.mo`, `report.mo`, and `main.mo`, over the three logs in `fixture/`. `examples/programs/mo.root` makes `programs/` the root its `use` lines load from; `main.mo`'s four `# run:` lines are the text report, the JSON report (`logstat-2.expected`), `--top 0` exiting 2, and no `.log` file exiting 1. `programs/logstat/TOOLCHAIN-BUGS.md` records what the program found and the commits that fixed it.
59. `programs/echo/`: a real TCP echo on 127.0.0.1 through `mo run`. The corpus test cannot start a server in the background, so `main` starts it all itself: an acceptor process, a worker process per connection, and client processes it asks in turn, and it prints every round trip. Its two `# run:` lines are three lines from one client and one line from each of three clients.
60. `programs/kv/`: program 3 (`mo-wiki/spec/programs/03-kv-store.md`), a key-value server over TCP in five modules, `protocol.mo`, `log.mo`, `store.mo`, `server.mo`, and `main.mo`. The corpus test cannot start a server in the background, so its first `# run:` line is `kv check`: it serves `data/demo`, whose log ends in a line cut short, on a free port, and plays `data/session.txt` through kv's own client, one real connection per line. The other four are `kv compact` on the same folder, a usage error exiting 2, a missing folder exiting 1, and a client with no server exiting 1. `programs/kv/TOOLCHAIN-BUGS.md` records what the program found.
64. `programs/httpd/`: a hello server over HTTP on 127.0.0.1 through `mo run`, in the shape of echo. `main` starts it all itself: an acceptor process that answers each exchange, one request per connection, and client processes it asks in turn, each sending `GET /hello?name=...` with `http.send` and printing the status and body. Its two `# run:` lines are one name from one client and two names from each of three clients. `httpd serve --port N` serves until it is stopped, for the bench's `http-1k` rows.
