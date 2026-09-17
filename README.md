# Mo

**The wiki is a site: [robertguss.github.io/mo-lang](https://robertguss.github.io/mo-lang/).** Start with [the state of the project](https://robertguss.github.io/mo-lang/state-of-the-project), the whole picture rewritten at every pause; the spec, every control round, every measurement, and the decision log are one link from there.

Mo is a programming language for code that agents write and people review at the level of intent: signatures, contracts, `never` clauses, effects, and tests. It reads like Ruby, keeps Go's discipline, runs processes under supervisors as BEAM does, and turns every style rule into a compiler law with a stable error code. This repository holds the design, a Zig toolchain that checks, tests, simulates, formats, fixes, and runs Mo programs on an interpreter, and the corpus of Mo files the toolchain is measured against.

## A one-minute tour

```ruby
module Tour

fn split(total: UInt32, people: UInt32) : UInt32
  requires people > 0

  total / people
end

test "a bill splits evenly"
  assert split(90, 3) == 30
end

test rejects "a bill for nobody"
  split(90, 0)
end
```

`requires` states what a caller must guarantee. `test rejects` proves the guarantee is enforced: the call inside it must trip the contract. `mo test tour.mo` runs both tests and computes the `verified:` line, the weakest obligation first:

```
pass  test "a bill splits evenly"
pass  test rejects "a bill for nobody": tripped requires people > 0
2 passed, 0 failed, 0 skipped
verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run
```

The rules are laws, checked before anything runs. Delete the `test rejects` block and `mo check tour.mo` refuses the file:

```
tour.mo:3:4: MO0311 split has requires people > 0, but no test rejects trips it.
  fn split(total: UInt32, people: UInt32) : UInt32
     ^
  why: Every requires has a test rejects that trips it (chapter 2, contract laws). Tier 1 checks that a test rejects calls the function; tier 2 checks that the call trips.
```

Some findings carry a fix the toolchain is sure of. Bind `share = total / people` and never read it, and `mo check` reports `MO0307`; `mo fix tour.mo` deletes the line and says so (`tour.mo:6: MO0307 delete the line that binds share`). `mo test --write tour.mo` writes the `verified:` line at the bottom of the file; a line edited by hand, or left behind by a changed declaration, is `MO0317`.

## Build and run

The toolchain needs Zig 0.16 and nothing else.

```sh
cd toolchain
zig build                  # zig-out/bin/mo (ReleaseSafe)
zig build test             # every stage's unit tests, and the corpus test over ../examples
zig build bench            # times every stage over the corpus
zig build errors           # regenerates mo-wiki/spec/errors.md from the diagnostic tables
```

```sh
mo check file.mo            # tier 1: types, laws, capabilities; --json prints one record per line
mo test file.mo             # tier 2: tests, contracts, properties; prints the verified: line
mo test --sim 100 file.mo   # tier 3: each process test again under 100 seeds with faults
mo test --write file.mo     # also writes the verified: line and records it in .mo.ids
mo run file.mo -- args      # main on the real platform
mo fmt file.mo              # rewrites the file in its one shape; --check prints the diff
mo fix file.mo              # applies every fix of confidence 100; --dry-run prints the diff
```

`cd examples/programs && mo run hello.mo -- Ada` prints `Hello, Ada!`.

## Where things are

| path | what |
|---|---|
| `mo-wiki/spec/design-v0/` | the design in nine chapters: premise, laws, semantics, syntax, verification, packages, toolchain, milestone, stdlib |
| `mo-wiki/spec/grammar.md` | the grammar |
| `mo-wiki/spec/errors.md` | every diagnostic code with its `what`, its `why`, and what `mo fix` does; generated |
| `mo-wiki/spec/programs/` | the specs of the programs Mo is tested on |
| `examples/` | the corpus: 68 Mo files, one construct each, 12 that must not compile, 5 programs; its `README.md` lists them |
| `toolchain/` | the Zig toolchain; its `README.md` names every source file, and `FORMAT.md` the formatter's rules |
| `mo-wiki/` | the design wiki: directions, questions, decisions, research, sessions |

## Numbers

Recorded 13 Sep 2026 by `zig build bench -- ../examples 20 --record`, best of 20, into `toolchain/bench/results.tsv`. A stage row is the whole corpus through that stage. The targets are 50 ms for tier 1 incremental and 100 ms per changed function for tier 2 (`design-v0/08-milestone.md`).

| measure | time |
|---|---|
| lex the corpus (68 files) | 466 µs |
| through parsing | 739 µs |
| through checking (tier 1) | 1,266 µs |
| through lowering to bytecode | 1,447 µs |
| through running every test (tier 2) | 10,054 µs |
| format the corpus | 665 µs |
| every `# run:` of the 5 programs through `mo run`, process start included | 27.2 ms |
| `logstat` over 4,000 log lines | 13.3 ms, 3 µs a line |
| the refund module's tests under 100 seeds | 623 µs |
| incremental rebuild of the toolchain (`bench/rebuild.sh`) | 116 ms |

`mo-wiki/plans/control-run.md` holds the other measurement: the same program written from the same spec in Mo, Go, and Python by the same model.

## How it is built

Robert Guss decides. Claude (Fable) designs with him in the wiki, then writes a brief for each step of the toolchain: `mo-wiki/plans/interpreter-step-N.md` names the files to read, the write scope, the parts, and when the step is done. A worker model runs each brief in a fresh session on a feature branch, one commit per part, and lists every decision the brief did not cover. Fable verifies the step and records each decision in `mo-wiki/decisions/decision-log.md`: who made it, whether it is provisional or locked, and what will first test it. `CHANGELOG.md` says what shipped; `mo-wiki/plans/roadmap.md` says what is next. Nothing is built on `main`.

The wiki follows [Karpathy's LLM-wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f): `mo-wiki/SCHEMA.md` holds its conventions, `mo-wiki/index.md` lists every page, `mo-wiki/log.md` says what changed, and `HANDOFF.md` starts the next session. `python3 mo-wiki/tools/lint.py` checks its links and frontmatter.
