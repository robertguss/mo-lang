---
title: "Step 6: main and Mo.Server, brief for the worker"
created: 2026-09-12
updated: 2026-09-12
type: plan
tags: [runtime, effects, tooling]
sources: [questions/q18-main-and-the-platform.md, spec/grammar.md, spec/design-v0/03-semantics.md]
status: done
---

# Step 6: `main` and `Mo.Server`, brief for the worker

After step 6, Mo runs programs: `mo run file.mo -- args` executes `main` on a real platform with real files, stdout, a clock, and arguments. Q18 settled the shape; this step builds it and nothing more, so that program 2 (the CLI log analyzer) can be written in Mo next.

## Orientation

`toolchain/README.md`, `toolchain/src/` (`sim.zig` shows what a platform provides; `vm.zig` how capability calls dispatch; `prelude.zig` and `PRELUDE.md` the table), `mo-wiki/questions/q18-main-and-the-platform.md`, the `main` production and decision in `spec/grammar.md`, `spec/design-v0/03-semantics.md` (effects).

## Write scope

`toolchain/` and `examples/`, branch `session-05`, `git pull --rebase --autostash` before every push, one commit per part.

## Part A: `main` in the language

Parser: `fn main(platform: Platform)` with no return type, once per module, and only one module in a program may have it. Checker: `main` is the only place a `Platform` value exists; it is a capability that cannot be passed to another function or stored; its fields are read and narrowed on the way down as chapter 3 says. `Platform` and its parts join the prelude: `args: List(String)`, `env: Env` with `get(name) : Option(String)`, `stdout: Out` and `stderr: Out` with `write(s: String)` (cannot wait, no `within:`), `fs: Fs`, `clock: Clock`, `exit(code: UInt8)`. Effects in `main` follow every existing rule.

## Part B: `Mo.Server` (`server.zig`)

The real platform over `std.Io`: `args` and `env` from the process, `Out.write` to the real streams (buffered, flushed at exit), `Fs.read(path, within:)` from the real file system under the scope given by `scoped(...)` (a path outside the scope is `FsError.Missing`, never an escape; `read_only` refuses writes at check time already), `clock.now` from the wall clock, `exit(code)` recorded and applied when `main` returns. `within:` on a real read is enforced after the fact in this step: measure the call, return `Timeout` if it exceeded the deadline, and record in the code that true cancellation comes with the async runtime. Nothing else: no network, no database, no writes to the file system yet.

## Part C: `mo run`

`mo run file.mo -- args...` lexes, parses, checks (tier 1 only; tests are not run), then runs `main` on `Mo.Server`. Exit code 0, or the last `platform.exit(code)`, or 70 with the crash report on stderr if `main` crashes. `mo test` continues to ignore `main`. A file without `main` given to `mo run` is an error with a code.

## Part D: programs in the corpus

New folder `examples/programs/`, each program a `.mo` with `main` and a `.expected` file beside it holding the exact stdout for a fixed argument list written on the file's first line as `# run: arg1 arg2`. Write three: `hello.mo` (prints a greeting with an arg), `count-lines.mo` (reads a file under `examples/programs/data/` through a scoped read-only `fs` and prints a count), `exit-code.mo` (exits 3 after a stderr line). The corpus test runs each with `Mo.Server` as a subprocess of the test and compares stdout and the exit code. Programs also keep a `test` block for their pure functions, as every corpus file does.

## Part E: numbers

Bench: a `run-programs` row (the three programs end to end, including process start). `zig build bench -- ../examples 20 --record`, `bench/rebuild.sh --record`.

## Done when

`zig build test` green with the three programs verified, `mo run` works from the shell, `PRELUDE.md` updated, bench rows recorded, pushed. Then list, in the final message only, every decision the brief did not cover.

## Related
- [[q18-main-and-the-platform]]
- [[interpreter-step-5]]
- [[program-menu]]
