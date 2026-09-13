# Toolchain bugs found while writing logstat

Recorded while writing the program (its brief's write scope was `examples/`), and fixed by step 7 (`mo-wiki/plans/interpreter-step-7.md`). Each keeps its minimal reproduction, the workaround the program used until the fix, and the commit that fixed it.

## 1. One file sees one module: `use` loads nothing, so a multi-module program cannot run or be tested

**Fixed** by step 7 parts A and B (`8d220d6`, `f4e9804`): `use A.B{X, y}` names types and functions from `A.B`'s expose line, and `mo check`, `mo test`, and `mo run` load every module a file uses, by path from the program root (`examples/programs/mo.root`). The `# copy of` types are deleted; `mo test --all main.mo` runs all 43 tests from the four files.

`pipeline.zig` compiles exactly one source for `mo check`, `mo test`, and `mo run`. A `use` line only registers the named types as opaque (`check.zig`, `registerModule`), and a function from another module is not in scope.

```
# a/lib.mo
module A.Lib
expose Pair, twice

intent "probe"

struct Pair
  x: UInt32
end

fn twice(n: UInt32) : UInt32
  n * 2
end

# a/app.mo
module A.App

use A.Lib{Pair}

intent "probe"

fn main(platform: Platform)
  platform.stdout.write("#{twice(2)}\n")
end
```

`mo run a/app.mo` prints `a/app.mo:8:28: MO0201 there is no twice in scope`. The grammar's `use` braces take only `TypeName`s, so there is also no way to name a function from another module at all.

Consequences for logstat:
- `Logstat.Main` calls all three other modules, so `mo check main.mo` and `mo test main.mo` fail with MO0201 on their own.
- A module that takes another module's type (Stats takes `Record`, Report takes `Summary`) cannot build one in its tests from an opaque `use`, so it declares a copy of that type, marked `# copy of Logstat.X`.

Workaround until the fix: `check.sh` joined the four modules into one file (declarations in dependency order, the copies dropped, `use` lines dropped, tests after all declarations) in a temporary folder and ran `mo test` and `mo run` on that.

## 2. The corpus test cannot hold a program made of several files

**Fixed** by step 7 part C (`120483d`): a program is `programs/<name>.mo` or `programs/<name>/main.mo` beside its modules, and every `# run:` line of its main file is one run, matched against `<name>.expected`, `<name>-2.expected`, and so on, with the `# exit:` line after it. logstat's four runs (text, JSON, `--top 0` exits 2, no `.log` file exits 1) are in the corpus test; `check.sh` and `join.awk` are deleted.

`corpus.zig` treats every `.mo` under `programs/` as a program: its first line must be `# run:`, its output is `<name>.expected`, and the test expects exactly 3 programs (`expectEqual(@as(u32, 3), programs)`). `parse.mo`, `stats.mo`, and `report.mo` have no `main` and no `# run:` line, and `main.mo` cannot run alone (bug 1), so `zig build test` fails on `examples/programs/logstat/` for four reasons at once.

Workaround until the fix: the program-level check was a shell script, `check.sh`.

## 3. MO0302 says "split it into modules", which bug 1 makes impossible, so no program over 500 lines can run

**Fixed** by step 7 parts A and B (`8d220d6`, `f4e9804`): each file of a program keeps its own 500 lines, and the second module the message names now loads.

A file of 503 lines with a `main`:

```
long.mo:501:1: MO0302 this file is 503 lines long and the limit is 500; split it into modules.
  why: A file is at most 500 lines (chapter 2, shape laws), so a module is read in one sitting. The fix is a second module.
```

The law is right for a module, and the fix it names does not exist: a second module cannot be loaded (bug 1). Together they cap a runnable program at 500 lines. logstat's declarations alone are about 600 lines across four modules before any test, so the joined file of bug 1's workaround is refused too.

How logstat was verified before the fix: a scratch copy of the toolchain, never committed, whose only change was `lines > 500` to `lines > 5000` in `check.zig`, ran `check.sh` green. The joined file passed all 43 of its tests, 18 of them `test rejects` and 2 properties of 200 seeds; both runs matched `logstat.expected` and the JSON run's expected file byte for byte; `--top 0` exited 2 with one line on stderr and no `.log` name exited 1. The expected files came from an independent Python reading of the spec, not from the Mo program's output.

## 4. `push` copies the whole list, so a list built by pushing is quadratic

**Fixed** by step 7 part D: `push` appends in place when the list ends where its buffer's last push left it, and `mo run` frees what a frame, a `for` iteration, or a step of `map`, `filter`, or `reduce` allocated and did not keep (`toolchain/src/region.zig`, `vm.zig`). The probe below with 200_000 pushes takes 0.27 s in 51 MB (Debug build); logstat on 4_000 lines peaks at 15 MB, where 500 lines took 571 MB before. Step 7 part E took the time per line from 3.7 ms to 39 µs (ReleaseFast: 4_000 lines in 156 ms, 200_000 in 8.8 s); the table lookup in `text_of` was 75% of every instruction run, and `mo run` now remembers a pure call it has seen (`toolchain/src/memo.zig`).

```
module P.Push

intent "probe"

fn main(platform: Platform)
  big = (0..8_000).reduce([], fn(acc, i) acc.push(i) end)
  platform.stdout.write("#{big.size}\n")
end
```

2_000 pushes take 0.09 s, 4_000 take 0.17 s, 8_000 take 0.63 s, and 200_000 took 3 min 10 s. `push` is the only way to grow a list, so any program that builds one element by element pays this.

Workaround: logstat never builds a list longer than one line's bytes, the `--top` records, or the distinct paths; a file is folded into the tally line by line. Its run time is then linear, about 3.7 ms per log line on this machine (500 lines 1.8 s, 1_000 3.7 s, 2_000 7.4 s, 4_000 15.2 s). The spec's 100 MB file, about 2.2 million lines, would take about 2.3 hours, and `contents.bytes` would hold it as 100 million values. The time per line was not profiled; the per-byte table lookup in `text_of` and the tuple rebuilt by every `reduce` step are the likely costs.
