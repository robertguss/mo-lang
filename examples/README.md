# examples/

The Mo program corpus: 50 tiny modules. Together they cover every construct in `mo-wiki/spec/design-v0/04-syntax.md` and every production in `mo-wiki/spec/grammar.md`, one construct per file. The corpus is the first test of the syntax, the first training material for agents, and the first test suite for the interpreter.

Two rules a reader needs:

- **File path equals module path.** `module Basics.Bindings` lives at `basics/bindings.mo`. A multi-word segment is hyphenated: `Basics.AnonymousFunctions` lives at `basics/anonymous-functions.mo`.
- **Everything in `rejects/` must fail to compile.** Each file there breaks exactly one law, named on its `# expect MO0xxx: sentence` line: the code the checker's first diagnostic must carry, and the sentence it prints.

Where the grammar and chapter 4 ran out, the corpus used the plainest option and recorded it in `GAPS.md`.

`mo test <file>` runs a file's tests on the interpreter today, with processes on the deterministic `Mo.Sim` scheduler. Every `test` must pass with no crash in any process it starts, every `test rejects` must trip a `requires`, a refinement, an `invariant`, or a `never`, and every `property` must hold under 200 seeds. Every `never` is checked at the end of every test, `test rejects`, and property run, over the values the run held, with or without `--sim`. It then prints the `verified:` line. A recipe test that calls a signature no agent has implemented yet is skipped.

Every file outside `rejects/` ends with its `verified:` line, written by `mo test --write --sim 100 <file>` and recorded in the `.mo.ids` sidecar at its program root (the file's own folder, or `programs/` for the programs). The sidecar is the toolchain's: a stable id and a content hash per declaration, and the hash of the line. Editing a declaration, or the line, without running `mo test --write` again is `MO0317`, so the corpus test fails on a stale line. `processes/racy.mo` records `verified: types`, since its test fails under `--sim`.

`mo test --sim N <file>` is tier 3: every test that starts a process runs N more times (default 100), each under a seed that chooses the delivery order, whether a statement's sends are delivered before the next statement, the clock's advance, and which fixture calls fail or are slow. A failure prints its seed and the interleaving; a test that holds only when no fixture fails is reported as passing only without faults. The corpus test runs every file with `--sim 100`: every process test holds under faults, except `processes/racy.mo`, whose test must fail under `--sim` and pass without it.

`mo run <file> -- args` runs a program's `main` on the real platform, `Mo.Server`. A program's processes run there too, each update on a fiber of its own on main's thread, so one waiting on a socket does not hold up the others and a process at rest costs no thread (`toolchain/src/turns.zig`, step 21). A file in `programs/` names its arguments on its first line (`# run: Ada`) and, when it ends with a code other than 0, that code on an `# exit: 3` line; `<name>.expected` beside it holds its exact stdout. The corpus test runs each program through `mo run`, as a subprocess, from the folder its main file is in: `programs/` for `programs/<name>.mo`, so it reads `data/` by that relative path, and `programs/<name>/` for `programs/<name>/main.mo`, so its `# run:` paths are relative to its own folder. Its `test` blocks run like any other file's.

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
9. `basics/if.mo`: `if` as a statement, as a value in block form and on one line (`if c: a else: b`, step 25), the one-line form also as a call's argument, an arm's value, an anonymous function's body, and inside an interpolation, and as a function's whole body on its last line (step 26), and trailing on `return`
10. `basics/case.mo`: guards, nested destructuring, literal arms, `_` inside a pattern
11. `basics/for.mo`: `for` over a range and a list, `break`, and why these are loops
12. `basics/anonymous-functions.mo`: one-line and block form, as call arguments
61. `basics/returns-nothing.mo`: a function with no return type, called for what it writes, and a negative number as a pattern
73. `basics/in-place.mo`: a field set on a var and a string grown by interpolation write in place (step 21), and a copy taken before either never sees it, as with `push`

## types
13. `types/struct.mo`: named construction and the `var` copy update
14. `types/enum.mo`: data variants and matching every one
15. `types/refinement.mo`: `type Percent = UInt32 where ...` and a `rejects` test at the boundary
16. `types/generics.mo`: `fn first(xs: List(T)) : Option(T)` and a `where T: Trait` bound
17. `types/trait.mo`: a `trait` and its `impl`
18. `types/nested.mo`: `Result(Option(T), E)` handled in full
86. `types/keyword-fields.mo`: `state` and `old` as a struct's fields, declared, given by name when it is built, read and set after a dot, encoded as the keys they are named, beside a process whose `state` holds one (step 25)

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
27. `effects/sim.mo`: `mo test` always runs on the simulator, so an effectful test is deterministic; its `# sim: --faults 20 --until 0.5` line runs its process test's seeds with faults that stop halfway, and the test asserts that a failed save is never counted and that every save lands once faults stop (step 18)
58. `effects/net.mo`: an echo server whose listener the runtime serves into a server process, which has each connection read into a worker process of its own (step 20), driven by a test through `Net.fixture()` that has what comes back read into a collector process, with no real socket, and holding under faults
63. `effects/http.mo`: a server process the runtime serves its listener into, which hands each exchange to a worker that answers `GET /hello?name=x` and `POST /echo`, driven by a test through `Http.fixture()` with no real socket, and holding under faults, with a raw `Net` server whose response has no `content-length`, written by a reader process at the blank line after the request's headers; `stdlib/http.mo` beside it writes requests by hand at an `HttpListener` to show what the reader makes of a body, a query, headers, and requests that are not HTTP, and reads what `reply` and `send` put on the wire
78. `effects/runtime.mo`: the runtime surface (step 23): a test's `Runtime.fixture()` lists the process it started, reads its state between updates, its events, and the slowest update, and a `Runtime` that may act pauses a process, sends it a message from its printed form, and resumes it, where a read-only one refuses; holding under faults
72. `effects/served.mo`: the runtime owns the loop (step 20): a listener served into a process delivers each connection as `Accepted`, a connection read into a process delivers each `Line`, a line too long, and its end, an HTTP listener served into a process delivers each whole request and answers one that is not HTTP itself, and a process with a mailbox of 8 is fed 2,000 lines without its mailbox overflowing, all holding under faults

## processes
28. `processes/counter.mo`: `state`, two `message` lines, `update`
29. `processes/ask.mo`: a message with a reply type, and `ask` with `within:`
30. `processes/mailbox.mo`: `mailbox: N`, and the sender-crashes rule
31. `processes/invariant.mo`: `invariant` with `old(state.km)`
32. `processes/supervisor.mo`: `supervisor` with `restart:` and `max_restarts:`
33. `processes/pipeline.mo`: two processes, one sending to the other
52. `processes/invariant-trips.mo`: chapter 4's `invariant "done never goes backwards"` tripping a `test rejects`
57. `processes/racy.mo`: a race the fixed order hides; its test passes under `mo test` and fails under `mo test --sim`
71. `processes/handoff.mo`: a `Conn` handed to a process in a message and on to another in a second message, which writes to it; once the front has sent the connection it is no longer the front's to use (MO0410, step 20)
81. `processes/registry.mo`: a registry whose `state` keeps a worker's handle per key in a `Map(String, Handle(Worker))`, starts a worker the first time a key is bumped, and routes each bump through the map; a worker whose key it forgets ends, which `Runtime.fixture().processes` shows in a test (step 24)
84. `processes/timer.mo`: a process that sends itself a `Tick` with `send(..., delay: 10.ms)` and stops after three; the test waits in a fixture that answers after 10 ms before each look, since simulated time passes only while something waits (step 24)

## tests
34. `tests/test.mo`: `assert`, and `assert x is Ok(user)`
35. `tests/rejects.mo`: one `requires`, one `test rejects`
36. `tests/property.mo`: `any(Type)` with a guard

## recipes
37. `recipes/rate-limiter.mo`: chapter 6's rate limiter, `needs Clock`
38. `recipes/pure-recipe.mo`: a recipe that `needs nothing`
69. `recipes/store.mo`: `Recipes.Store`, a durable string map over an append-only log, `needs Fs`, with two nevers declared at the module's head; its tests skip until an implementation exists, and `programs/notes/store.mo` is one

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
74. `rejects/one-line-if-statement.mo`: a one-line `if` on a line of its own that is not a body's last; `MO0310` says its value is dropped, the form a value only, and shows the block form (step 21; steps 25, 26)
85. `rejects/one-line-if-without-else.mo`: a one-line `if` value with no `else:`; `MO0101` says both branches are required (step 25)
75. `rejects/positional-variant.mo`: a variant matched by position; `MO0101` names its fields (step 21)
76. `rejects/method-on-range-end.mo`: `0..60.map(...)`, whose `map` binds to 60; `MO0206` says so (step 21)
82. `rejects/read-only-start-argument.mo`: an `Fs` narrowed to `read_only` handed as the start argument of a process that writes through it; `MO0404` refuses the start (step 24)
83. `rejects/read-only-message-field.mo`: an `Fs` narrowed to `read_only` sent in a message whose arm writes through it; `MO0404` refuses the message (step 24)
87. `rejects/state-binding.mo`: `state = 1` outside a process; `state` alone is the process's state, so `MO0201` says a binding takes another name (step 25)
88. `rejects/read-only-if-argument.mo`: an `Fs` narrowed to `read_only` in a branch of a one-line `if` handed as a process's start argument; `MO0404` names the branch (step 25)
89. `rejects/var-state.mo`: `var state = n`; `state` is a keyword, so `MO0101` says what it names, that a binding or a parameter takes another name, and that a struct's field may take it (step 26)
90. `rejects/old-parameter.mo`: a parameter named `old`; `old` is a keyword, so `MO0101` says what it names, that a binding or a parameter takes another name, and that a struct's field may take it (step 26)

## payments (the milestone)
51. `payments/refund.mo`: chapter 4's refund module, with the differences `GAPS.md` records

## programs (`main` on Mo.Server)
53. `programs/hello.mo`: `fn main(platform: Platform)`, an argument, and `stdout`
54. `programs/count-lines.mo`: `platform.fs.scoped("data").read_only` and a real read with `within:`
55. `programs/exit-code.mo`: a line on `stderr` and `platform.exit(3)`
66. `programs/not-text.mo`: `bytes/not-text.txt` holds a byte that is not UTF-8, so `read`, `read_lines`, `fold_lines` handing `out` on (after printing the line before it), and `fold_lines` counting bytes are `NotText`, and `read_bytes` gives its 36 bytes; its second run reads `bytes/text.txt`, which every row reads
68. `programs/runaway.mo`: recursion past the depth limit of 10,000 nested calls crashes `main` with a report naming the function, and exits 70, under `mo run` and as a binary (step 18)
59. `programs/echo/`: a real TCP echo on 127.0.0.1 through `mo run`. The corpus test cannot start a server in the background, so `main` starts it all itself: a listener the runtime serves into an acceptor process, a worker process per connection that takes each line as a message, and a client process per client that `main` asks once per line, and it prints every round trip; `main` ends with `exit`, since the listener would be served on (step 20). Its two `# run:` lines are three lines from one client and one line from each of three clients.
60. `programs/kv/`: program 3 (`mo-wiki/spec/programs/03-kv-store.md`), a key-value server over TCP in five modules, `protocol.mo`, `log.mo`, `store.mo`, `server.mo`, and `main.mo`. The corpus test cannot start a server in the background, so its first `# run:` line is `kv check`: it serves `data/demo`, whose log ends in a line cut short, on a free port, and plays `data/session.txt` through kv's own client, one real connection per line. The other four are `kv compact` on the same folder, a usage error exiting 2, a missing folder exiting 1, and a client with no server exiting 1. `programs/kv/TOOLCHAIN-BUGS.md` records what the program found.
64. `programs/httpd/`: a hello server over HTTP on 127.0.0.1 through `mo run`, in the shape of echo. `main` starts it all itself: a listener the runtime serves into an acceptor process that answers each exchange as it arrives, one request per connection, and client processes it asks in turn, each sending `GET /hello?name=...` with `http.send` and printing the status and body. Its two `# run:` lines are one name from one client and two names from each of three clients. `httpd serve --port N` serves until it is stopped, for the bench's `http-1k` rows.
70. `programs/notes/`: program 4 (`mo-wiki/spec/programs/04-web-backend.md`), a notes service over HTTP in seven modules: `limits.mo` and `store.mo` implement `recipes/rate-limiter.mo` and `recipes/store.mo` by hand, `note.mo` holds the note and its rules, `service.mo` the process, `api.mo` the routes and JSON, `server.mo` the acceptor the runtime serves the listener into, and `main.mo` the commands. Its first `# run:` line is `notes check`: it serves `data/demo`, whose log ends in a line cut short, on a free port and plays `data/session.txt` through its own client over a real socket, one connection per line, with the clock's times steadied; the other four are `notes compact`, a usage error exiting 2, a missing folder exiting 1, and a client with no server exiting 1. `programs/notes/TOOLCHAIN-BUGS.md` records what the program found.
91. `programs/logstat/`: program 2 (`mo-wiki/spec/programs/02-log-analyzer.md`), a log analyzer in four modules: `parse.mo` turns a line into a record and stars out a card number in its path, with a `never` that no record holds one; `stats.mo` folds lines into a summary as `fold_lines` reads them, with a `never` that its counts add up; `report.mo` prints the text report and the JSON object; `main.mo` reads the options and every `.log` file directly inside the folder, read-only and one at a time, reading a file with a line that is not UTF-8 again as bytes. Its `# run:` lines, run from its own folder, read `fixture` (three logs, one with malformed lines, a card number in a path, a byte that is not UTF-8, and a carriage return, beside a `notes.txt` that is not read) as text, as JSON, and with `--top 2 --since`; the other two are a `--top` of 101 exiting 2 and a folder that is not there exiting 1. `programs/logstat/TOOLCHAIN-BUGS.md` records what the program found.
92. `programs/jobq/`: program 1 (`mo-wiki/spec/programs/01-job-queue.md`), a durable job queue over HTTP in ten modules. `store.mo` implements `recipes/store.mo` (`# recipe:`), copied by hand from `programs/notes/store.mo` with its log named `jobq.log`; `job.mo` holds a job, its four states and the moves between them with their `requires` and `ensures`, the rules, the JSON, and two `never`s; `books.mo` the store and every job in it, each record put in the store before the books take it, ids reserved ahead, replay, and the `never` that a replay loses no job; `board.mo` each call on the board, a lease that ran out put back at the next look, and three `never`s (no job held by two workers at once, no response before its record is durable, no run-out lease still held after a look); `queue.mo` the one process that holds the board of every queue, with a race of two workers and a restart from the store; `api.mo` the routes, bodies, and statuses; `server.mo` the acceptor the runtime serves the listener into, a worker per exchange, and a `# sim: --faults 20 --until 0.5` test in which every job ends done or dead once faults stop; `client.mo` one request; `check.mo` the check; and `main.mo` the commands. Its first `# run:` line is `jobq check`: it serves `data/demo`, whose log holds a done, a queued, a dead, and a deleted job, a lease that ran out, an id reservation, and a last line cut short, on a free port, and plays `data/session.txt` through its own client over a real socket, one connection per line, with the clock's times steadied; its `crowd 1200` line opens 1,200 connections that send nothing and keeps them open while the next request is answered. The other four are `jobq compact` on `data/compact`, a usage error exiting 2, a missing folder exiting 1, and a client with no server exiting 1. `programs/jobq/TOOLCHAIN-BUGS.md` records what the program found.
79. `programs/surface/`: a program that asks its own runtime surface over HTTP (step 23): `main` starts a tally, then sends the surface at the port it is given a GET of the processes, a state, and recent events, a message to deliver and one that does not parse, and a route that does not exist, printing what each answer says. Its `# run:` line finds nothing listening at port 1; the corpus test also runs it under `mo run --surface PORT` and as a binary built with `--surface` given `MO_SURFACE=PORT`, and both print the same eight lines.
80. `programs/agent/`: program 5 (`mo-wiki/spec/programs/05-agent-harness.md`), an agent harness that runs a model's loop under permissions, budgets, and retries, in eighteen modules. `model.mo` implements `recipes/model-client.mo` (`# recipe:`), the retrying model call on its caller's `Deadline`, building its HTTP request itself though it declares the recipe's `Request` (step 24); `record.mo` holds a run's order, budget, record, and their rules; `transcript.mo` a run's log lines and their replay; `shelf.mo` and `filing.mo` what the book of runs holds and how it writes each change to a run's log before it takes it; `book.mo` the process that does it; `steps.mo` a run's loop as values; `run.mo` the process per run, which takes its budget's deadline from the ask that begins it and steps by messages it sends itself, with two `invariant`s its `test rejects` trip; `tools.mo` each tool over only its narrowed capability, `write_file` through a `Writer` process that only a run granted it is started with (step 25); `registry.mo` starts the runs; `mock.mo` the scripted model; `runs.mo` the runs end to end against it, each budget spent, refusals, retries, and a cancel; `api.mo`, `server.mo` (with a `# sim: --faults 20 --until 0.5` test in which every run ends once faults stop), `client.mo`, `check.mo`, `operator.mo` (the operator's view over the runtime surface), and `main.mo` the commands. Its first `# run:` line is `agent check`, which copies `data/demo`'s run logs (a run done, a run left running with a last line cut short) into `runs.check`, serves the folder with the scripted model on free ports, and plays `data/runs.txt`: seven runs to done, over each budget, failed, and cancelled, their transcripts, and every status; the others are one `agent run` against a model that is not there exiting 3, a script that cannot be read exiting 1, a usage error exiting 2, a missing folder exiting 1, and a client with no server exiting 1. `programs/agent/TOOLCHAIN-BUGS.md` records what the program found.
