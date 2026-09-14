# toolchain/

The Mo toolchain in Zig (0.16). Build order per `mo-wiki/spec/design-v0/07-toolchain.md`: interpreter first, C via Zig for release (step 13, `mo build`), a native backend only if a real program demands it. The milestone is `mo-wiki/spec/design-v0/08-milestone.md`: lex, parse, typecheck, and run `examples/payments/refund.mo` with its tests, contracts at tier 2, `rejects` tests tripping, the `verified:` line computed.

```
zig build              → zig-out/bin/mo         mo check [--recipe Module.Recipe] <file.mo> [--json]
                                                mo test [--all | --write] [--sim [N]] [--seed S] [--faults P] [--until F] <file.mo> [--json]
                                                mo run [--clock ISO-8601] [--events N] [--surface PORT] <file.mo> [-- args...]   main on Mo.Server
                                                mo build <file.mo> [-o name] [--no-contracts] [--tests] [--target triple] [--surface]
                                                                                 C via zig cc: zig-out/mo-build/<name>/<name>
                                                mo fmt [--check | --stdout] <file.mo>
                                                mo fix [--dry-run] <file.mo>     every fix of confidence 100
                                                ReleaseSafe; zig build -Ddebug for Debug
zig build test         → every stage's tests + the corpus test over ../examples, the interpreter and mo build side by side
zig build bench        → zig-out/bin/mo-bench   times every stage over ../examples
zig build errors       → ../mo-wiki/spec/errors.md, the error catalog, rendered from the diagnostic tables
bench/rebuild.sh       → the toolchain's own incremental build time
```

## mo build

`mo build file.mo` checks the program (tier 1; `MO0408` without a `main` unless `--tests`), emits its C (`src/emit_c.zig`), and compiles it with the runtime (`runtime/mo_rt.c`, embedded in `mo`) by `zig cc -std=c11 -Wall -Werror -O2` into one binary that runs `main` on Mo.Server. The C, the runtime, and the binary go to `zig-out/mo-build/<name>/` under the working directory, and the binary's path is printed. The name is the file's, or its folder's for a `main.mo`; `-o` gives another.

- **Contracts run in every build** (chapter 3): `requires`, `ensures`, and refinements are checked in the binary, as `mo run` checks them. `--no-contracts` turns them off for a measurement and says so on stderr; `MO_CONTRACTS=0` or `1` overrides a build at run time, and `MO_CLOCK=<ISO-8601>` starts `main`'s clock there, advancing with the wall, as `mo run --clock` does (step 19). A test binary always checks them.
- **Overflow traps and asserts** are on in every binary; there is no flag.
- `--tests` builds a binary that runs the file's tests and prints what `mo test` prints.
- `--target <zig triple>` cross-compiles. A Linux target links statically against musl; a macOS binary links only libSystem, which Apple ships no static form of.
- `zig` is found next to the running `mo`, else on PATH; it is the only dependency.
- **Processes, `Net`, and `Http` compile** (steps 15 and 16). The scheduler `mo run` uses (`sim.zig`, `turns.zig`) is the runtime's: under `main` every update runs on main's thread, each on a fiber of its own borrowed from a pool for one delivery, and a call that waits switches back and keeps its fiber until a kqueue or epoll poller reports its socket or its deadline passes (step 21); a process at rest holds no stack and no thread. A process a start call began ends once its mailbox is empty, no update of it runs, and no handle to it is reachable (step 19): functions that can hold a handle list their frame's locals, and main's thread sweeps them, the live processes' start arguments, held sends, and waiting replies every 64 quiet events or more, freeing the process's parcels and region and keeping the regions of the last 64 ended ids for the next starts. An update about to wait in `accept`, `read_line`, or `ask` on what only a send it holds could bring (a process it sent to holds the unanswered exchange or connection that wait hears from) crashes with a report naming the send and the call, in a test as under `main` (step 19). `Net` and `Http` are POSIX sockets under `main` and their fixtures in a test binary. `Listener.serve`, `Conn.lines`, and `HttpListener.serve` (step 20) are pumped as `sources.zig` pumps them: in a test binary at the start of each delivery round, and under `main` from main's thread, which pumps only a source just added, one whose socket the poller reported ready, one paused at its target's bound, and one whose idle time a heap of deadlines says ran out; a `main` that calls `exit` stops them when it returns. `--tests` runs process tests in the fixed order; `mo test --sim` has no compiled form.
- **The runtime surface** (step 23): `platform.runtime` is `Some` under `mo run` and `None` in a binary unless it was built with `--surface` (design-v0/09, `## Runtime`). Both runtimes keep the ring of events the surface reads, 4,096 by default: `mo run --events N`, and `MO_EVENTS=N` for a binary. `mo run --surface PORT` serves the rows as JSON over HTTP on 127.0.0.1 (`GET /processes`, `/state/<id>`, `/recent/<id>?n=`, `/events?since=&n=`, `/crashes?n=`, `/sources`, `/memory`, `/slowest?n=`; `POST /send/<id>` with the message as the body, `/pause/<id>`, `/resume/<id>`), and so does a binary built with `--surface` when `MO_SURFACE=PORT` is set: a module of Mo (`src/surface.mo`) the toolchain puts first in the program and starts before main, a process serving an `HttpListener` into itself whose updates answer between the program's, which the surface does not list and whose listener does not keep a program running. Session 5, step 23.
- The interpreter is the reference. `zig build test` builds every corpus module with `--tests` and every program, and each must print and exit exactly as `mo test` and `mo run` do. `bench/results.tsv` records the compiled logstat (`logstat-4k-c`) beside the interpreter (`logstat-4k`), without overflow checks (`-wrap`), and without contracts (`-nocontracts`); the compiled echo and kv (`echo-1k-c`, `kv-10k-get-c`) beside theirs; kv's resident memory after 50,000 SETs under `mo run` and as a binary (`kv-50k-set-rss-kib`, `kv-50k-set-rss-kib-c`, in KiB); and 1,000 `GET /hello` round trips to `httpd serve` under `mo run` and as a binary (`http-1k`, `http-1k-c`), with each server's resident memory after them (`http-1k-rss-kib`, `http-1k-rss-kib-c`).

## Layout

| file | stage | design-v0 |
|---|---|---|
| `src/token.zig` | token kinds and the keyword table | grammar §1 |
| `src/lexer.zig` | bytes → tokens | grammar §1 |
| `src/ast.zig` | flat, index-based tree (memcpy to the disk cache) | ch. 7 |
| `src/parser.zig` | tokens → tree, one function per production | grammar §2–11 |
| `src/prelude.zig` | stdlib types, variants, functions as data (`PRELUDE.md` is the table) | grammar, Session 5 |
| `src/types.zig` | the checker's type pool, unification, inference variables | ch. 5 |
| `src/check.zig` | tier 1: types, exhaustiveness, the laws | ch. 2, 5 |
| `src/caps.zig` | capabilities and `flows`; a message line may declare a capability or a handle, and a capability sent in a message moves, so the sender's later use of it is MO0410 (step 20); an Fs narrowed to read_only is followed into a process's start arguments, a supervisor's child lines, and a message's fields, as into a function's parameters (MO0404, step 24) | ch. 3 |
| `src/loops.zig` | MO0501: a `for` with a pure body, and the three accumulator loops `mo fix` rewrites | ch. 4 |
| `src/bytecode.zig` | instruction set and lowering | ch. 7 |
| `src/vm.zig` | the interpreter, the reference semantics | ch. 7 |
| `src/stdlib.zig` | the stdlib rows of design-v0/09: numbers, strings, lists, maps and sets, time, files, output | ch. 6, 09 |
| `src/json.zig` | `Json.encode` and `Json.decode` | 09 |
| `src/region.zig` | the bump region `mo run` allocates values in, freed at the vm's safe points | ch. 7 |
| `src/contracts.zig` | tier 2: `requires`, `ensures`, `invariant`, `never` at runtime | ch. 5 |
| `src/runner.zig` | `test`, `test rejects`, `property` | ch. 4 |
| `src/recipe.zig` | `mo check --recipe`: an implementation against its recipe's signatures (`MO0326`), then the recipe's tests and nevers run against it; the corpus test runs it for each file whose first lines say `# recipe: Module.Recipe`, and so does a plain `mo check` of such a file (step 20) | ch. 6 |
| `src/mutation.zig` | mutation tests of the contract machinery: mutants of a `never`, an `ensures`, and an `invariant` in three corpus files, each caught by `mo test` but the survivors it lists | ch. 5 |
| `src/net.zig` | `Net`: nonblocking TCP for `mo run`, waiting in the poller (step 21), and `Net.fixture()` for `mo test` | 09 |
| `src/fiber.zig` | fibers (step 21): a stack reserved whole and committed as touched, and a switch in a few lines of assembly that runtime/mo_rt.c shares | ch. 7 |
| `src/poller.zig` | the poller (step 21): kqueue or epoll, one-shot waiters, on main's thread | ch. 7 |
| `src/http.zig` | `Http`: HTTP/1.1 over `Net`, the request and response reader and writer, and `Http.fixture()` | 09 |
| `src/events.zig` | the ring of structured runtime events (step 23) both runtimes keep, read by the runtime surface and printed after a failed seed's interleaving | ch. 3 |
| `src/surface.zig` | the runtime surface (step 23): the `Runtime` rows, reads between updates, and `send`'s message parsed from its printed form | ch. 3, 09 |
| `src/sim.zig` | Mo.Sim: processes, mailboxes, `update` as a transaction, supervisors | ch. 3, 8 |
| `src/sources.zig` | the loops the runtime owns (step 20): `Listener.serve`, `Conn.lines`, and `HttpListener.serve` accept or read and send each result to a process as a message; pumped each delivery round under Mo.Sim, and under Mo.Server from main's thread when the poller, a paused target, or a deadline says a source can act (step 21); backpressure at a mailbox's bound less 4, resuming at half; MO0223 when the process does not declare the messages | ch. 3, 09 |
| `src/emit_c.zig` | the C backend: the checked tree as one C11 translation unit, lowered construct for construct as `bytecode.zig` lowers it | ch. 7 |
| `src/cbuild.zig` | `mo build`: writes the C beside the runtime and compiles it with `zig cc` (`-std=c11 -Wall -Werror -O2`; static on Linux) | ch. 7 |
| `runtime/mo_rt.h`, `runtime/mo_rt.c` | the C runtime a built program links, embedded in `mo`: values, the stdlib rows, overflow traps, crash reports, regions freed at the vm's safe points, Mo.Server's platform parts, and the test runner | ch. 7, 09 |
| `src/server.zig` | Mo.Server: the real platform `mo run` gives `main` (args, env, streams, a scoped `Fs`, the wall clock, exit) | ch. 3, Q18 |
| `src/diag.zig` | structured diagnostics, no warnings; a fix's edits; the catalog row every table uses | ch. 5 |
| `src/errors.zig` | the error catalog: every table's rows in code order, rendered as `mo-wiki/spec/errors.md` (`src/errors_gen.zig` writes it) | ch. 5 |
| `src/verified.zig` | the `verified:` line | ch. 5 |
| `src/ids.zig` | the `.mo.ids` sidecar: a stable id and a content hash per declaration, and the `verified:` line `mo test --write` recorded; `MO0317` when the line is not that one | ch. 5, 7 |
| `src/pipeline.zig` | the stages in order, `runTo(stage)` | |
| `src/program.zig` | a program: the file given and every module it uses, by path under the `mo.root` root, in dependency order | grammar, Session 5 |
| `src/fmt.zig` | `mo fmt`: the tree printed in its one shape (`FORMAT.md` is the rule table) | ch. 2, 4 |
| `src/fix.zig` | `mo fix`: the fixes of MO0307 and MO0312, and applying every fix of confidence 100 until none applies | ch. 5, 7 |
| `src/diff.zig` | the unified diff `mo fmt --check` and `mo fix --dry-run` print | |
| `src/corpus.zig` | the corpus test: `examples/` passes, `examples/rejects/` is rejected; every module's tests and every program built by `mo build` print what the interpreter prints | |
| `src/main.zig` | the `mo` CLI | |
| `src/bench.zig` | the benchmark harness | ch. 8 |
| `bench/results.tsv` | one row per stage per recorded run | ch. 8 |
| `bench/rebuild.tsv` | incremental build times of this toolchain | Q13 |

Every stage that is not built yet returns `error.NotImplemented`. The corpus test counts those files as skipped and the harness prints `n/a`, so both are green on day one and tighten as stages land. Build the stages in table order; the first real number the harness should show is lexing the whole corpus.

## Rules

- Pointer-free, index-based data everywhere in the compiler (Roc's lesson, Q13).
- Overflow traps in every build mode of the interpreter and in every binary `mo build` makes, because Mo's semantics say so. The interpreter is the reference: a difference between a built binary and `mo run` or `mo test` is a bug, and the interpreter wins unless it is shown to be the one that is wrong.
- Record a benchmark row (`zig build bench -- ../examples 20 --record`, `bench/rebuild.sh --record`) whenever a stage lands or a number moves. The targets are 50 ms for tier 1 incremental and 100 ms per changed function for tier 2.
- No dependency but Zig. `build.zig.zon` stays empty of packages.
