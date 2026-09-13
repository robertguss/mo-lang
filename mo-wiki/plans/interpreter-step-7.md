---
title: "Step 7: programs of many modules, and the runtime that can hold them, brief for the worker"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [compiler, runtime, performance]
sources: [examples/programs/logstat/TOOLCHAIN-BUGS.md, spec/design-v0/07-toolchain.md]
status: in-progress
---

# Step 7: programs of many modules, and the runtime that can hold them

Program 2 (`examples/programs/logstat/`) found three toolchain bugs and two runtime limits. This step fixes all five so that `logstat` runs from its four source files with no join script and no lifted law.

## Orientation

`examples/programs/logstat/TOOLCHAIN-BUGS.md` (read first, it has the reproductions), `examples/programs/logstat/check.sh` and `join.awk` (the workaround to delete), `toolchain/src/pipeline.zig`, `check.zig` (`registerModule`, `use`), `corpus.zig`, `vm.zig` (values, lists, the arena), `spec/design-v0/02-laws.md` (one module per file, file path equals module path, no cycles), the Session 5 decisions in `spec/grammar.md`.

## Write scope

`toolchain/` and `examples/`, branch `session-05`, `git pull --rebase --autostash` before every push, one commit per part.

## Part A: `use` brings in functions

Grammar change (Fable updates `grammar.md`; you implement): `use A.B{X, y}` names types and functions, `TypeName | ident`, and everything named must be on `A.B`'s `expose` line. Types and functions from `A.B` are then in scope by their bare name. A name on no `use` line is `MO0201` as today. `use A.B` with no braces brings nothing into scope and is `MO0321`, "name what you use". No aliases, no wildcards.

## Part B: a program is a tree of files

`mo check`, `mo test`, and `mo run` take one file, then load every module it `use`s by path: `A.B` is `a/b.mo` relative to the **program root**, which is the nearest ancestor directory of the given file that contains a `mo.root` marker file (empty), else the given file's own directory. Modules load once, in dependency order; a cycle is `MO0318`. Each file keeps its own 500-line law. Every loaded module is checked; `mo test file.mo` runs the tests of that file only, `mo test --all file.mo` runs every loaded module's tests. `logstat`'s four files get a `mo.root` and their `# copy of` types are deleted.

## Part C: the corpus test holds multi-file programs

A program is either `programs/<name>.mo` with `# run:` and `<name>.expected` as today, or `programs/<name>/main.mo` with `# run:` and `programs/<name>/<name>.expected` (plus `<name>-json.expected` when a second `# run:` line names `--json`; generalize: every `# run:` line in `main.mo` is one run, matched against `<name>.expected`, `<name>-2.expected`, …). The count assertion becomes a list of the programs found. `logstat` runs in the corpus test; `check.sh` and `join.awk` are deleted; `TOOLCHAIN-BUGS.md` marks each bug fixed with the commit.

## Part D: memory

A `var` list that is unaliased grows in place on `push`: the VM tracks a unique-owner bit on list values (set when bound to a `var` from a literal or a fresh call result, cleared on any copy), and `push` on a unique list appends without copying. Per-iteration garbage: each `for` iteration and each call frame frees what it allocated on exit, unless the value escapes into the result or an outer `var` (move it). Measure: `logstat` on 200,000 lines must run in bounded memory, and a `push` loop of 200,000 must take under a second. Record before and after numbers in the commit.

## Part E: speed

Profile `logstat` on the 4,000-line file (3.7 ms per line today). The usual suspects: string copies on every `bytes` fold, list copies, interpolation, `case` dispatch. Fix what the profile shows until a log line costs under 50 µs; stop there and report what remains. Do not change semantics.

## Part F: numbers

`zig build bench -- ../examples 20 --record`, `bench/rebuild.sh --record`; add a `logstat-4k` row (run the program over a 4,000-line generated file) so the speed has a permanent number.

## Done when

`zig build test` green with `logstat` in the corpus test from its four files, no join script, no lifted law, `push` linear, the 4k row under 200 ms, pushed. Then list every decision the brief did not cover.

## Related
- [[program-2]]
- [[control-run]]
- [[interpreter-step-8]]
- [[decision-log]]
