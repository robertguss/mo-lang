# toolchain/

The Mo toolchain in Zig (0.16). Build order per `mo-wiki/spec/design-v0/07-toolchain.md`: interpreter first, C via Zig for release later, a native backend only if a real program demands it. The milestone is `mo-wiki/spec/design-v0/08-milestone.md`: lex, parse, typecheck, and run `examples/payments/refund.mo` with its tests, contracts at tier 2, `rejects` tests tripping, the `verified:` line computed.

```
zig build              → zig-out/bin/mo         mo check|test|run <file.mo> [--json]
                                                mo fmt [--check | --stdout] <file.mo>
zig build test         → every stage's tests + the corpus test over ../examples
zig build bench        → zig-out/bin/mo-bench   times every stage over ../examples
bench/rebuild.sh       → the toolchain's own incremental build time
```

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
| `src/caps.zig` | capabilities and `flows` | ch. 3 |
| `src/loops.zig` | MO0501: a `for` with a pure body | ch. 4 |
| `src/bytecode.zig` | instruction set and lowering | ch. 7 |
| `src/vm.zig` | the interpreter, the reference semantics | ch. 7 |
| `src/contracts.zig` | tier 2: `requires`, `ensures`, `invariant`, `never` at runtime | ch. 5 |
| `src/runner.zig` | `test`, `test rejects`, `property` | ch. 4 |
| `src/sim.zig` | Mo.Sim: processes, mailboxes, `update` as a transaction, supervisors | ch. 3, 8 |
| `src/diag.zig` | structured diagnostics, no warnings | ch. 5 |
| `src/verified.zig` | the `verified:` line | ch. 5 |
| `src/pipeline.zig` | the stages in order, `runTo(stage)` | |
| `src/fmt.zig` | `mo fmt`: the tree printed in its one shape (`FORMAT.md` is the rule table) | ch. 2, 4 |
| `src/diff.zig` | the unified diff `mo fmt --check` prints | |
| `src/corpus.zig` | the corpus test: `examples/` passes, `examples/rejects/` is rejected | |
| `src/main.zig` | the `mo` CLI | |
| `src/bench.zig` | the benchmark harness | ch. 8 |
| `bench/results.tsv` | one row per stage per recorded run | ch. 8 |
| `bench/rebuild.tsv` | incremental build times of this toolchain | Q13 |

Every stage that is not built yet returns `error.NotImplemented`. The corpus test counts those files as skipped and the harness prints `n/a`, so both are green on day one and tighten as stages land. Build the stages in table order; the first real number the harness should show is lexing the whole corpus.

## Rules

- Pointer-free, index-based data everywhere in the compiler (Roc's lesson, Q13).
- Overflow traps in every build mode of the interpreter, because Mo's semantics say so.
- Record a benchmark row (`zig build bench -- ../examples 20 --record`, `bench/rebuild.sh --record`) whenever a stage lands or a number moves. The targets are 50 ms for tier 1 incremental and 100 ms per changed function for tier 2.
- No dependency but Zig. `build.zig.zon` stays empty of packages.
